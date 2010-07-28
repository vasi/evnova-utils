#!/usr/bin/perl
use warnings;
use strict;
use Data::Dumper;

use lib 'lib';

use Fink::CLI		qw(print_breaking);
use Fink::Command	qw(mkdir_p);
use Storable		qw(nstore retrieve freeze thaw dclone);
use Getopt::Long;
use File::Spec;
use DB_File;
use List::Util		qw(min first);
use File::Basename	qw(basename dirname);
use Date::Manip;
use Carp;
use Fcntl qw(:seek);

use ResourceFork;
use Encode		qw(decode encode decode_utf8);

use utf8;
binmode STDOUT, ":utf8";

our $pilotLog = '../EV Nova 1.0.9/pilotlog.txt';
our $globalCache;
{
	my $dir = File::Spec->rel2abs(dirname $0);
	$globalCache = File::Spec->catdir($dir, '.nova-cache');
}
our $conTextOpt;

sub parseData {
	my ($data) = @_;
	my ($type, $ret);
	
	if ($data =~ /^"(.*)"$/) {
		my $str = $1;
		$str =~ s/\\q/\"/g;
		$str =~ s/\\r/\n/g;
		($type, $ret) = (string => $str);
	} elsif ($data =~ /^(#)(.*)$/ || $data =~ /^(0x)(.*)$/) {
		($type, $ret) = ($1 eq '#' ? 'color' : ('hex' . length($2)), hex($2));
	} else {
		($type, $ret) = ('misc', $data);
	}
}

sub parseLine {
	my ($line) = @_;
	chomp $line;
	my @vals = split /\t/, $line;
	my @types;
	
	my $idx = 0;
	for my $v (@vals) {
		($types[$idx++], $v) = parseData($v);
	}
	return (\@vals, \@types);
}

sub deaccent {
	my ($s) = @_;
	$s =~ tr/äëïöüÿ/aeiouy/;
	return lc $s;
}

my %handlers; # predeclare
%handlers = (
	'str#' => sub {
		my ($vals, $types, $titles) = @_;
		my @t = @$titles;
		my @ty;
		my %res;
		$res{pop @t} = pop @$vals; # end of record
		while (scalar(@t) > 1) {
			$res{shift @t} = shift @$vals;
			push @ty, shift @$types;
		}
		$res{$t[0]} = $vals;
		@ty = (@ty, 'list', $types->[-1]);
		$res{_priv} = { types => \@ty, order => $titles };
		return %res;
	},
	default => sub {
		my ($vals, $types, $titles) = @_;
		my @t = @$titles;
		my @order;
		my %res;
		while (scalar(@$vals) > 1) {
			my $t = shift @t;
			$res{$t} = shift @$vals;
			push @order, $t;
		}
		$res{$t[-1]} = shift @$vals;
		$res{_priv} = { types => $types, order => [ @order, $t[-1] ] };
		return %res;
	},
	outf => sub {
		my %outfhex = map { $_ => 1 } (17, 30, 43);
		my %res = $handlers{default}->(@_);
		my @ktypes = grep /^ModType/, keys %res;
		@ktypes = grep { $outfhex{$res{ModType}} } @ktypes;
		my $order = $res{_priv}{order};
		for my $k (@ktypes) {
			(my $v = $k) =~ s/ModType/ModVal/;
			my ($idx) = grep { $order->[$_] eq $v } (0..$#$order);
			$res{_priv}{types}[$idx] = 'hex4';
		}
		
		
		return %res;
	},
	syst => sub {
		# Silly ConText spelling bug
		my ($vals, $types, $titles) = @_;
		map { s/^Visiblility$/Visibility/ } @$titles;
		return $handlers{default}->(@_);
	},
);

sub readLineSafe {
    my ($fh) = @_;
    
    # Ignore encoding errors
    my $w;
    local $SIG{__WARN__} = sub { $w = $_[0] };
    my $line = <$fh>;
    die $w if defined($w) && $w !~ /does not map to Unicode/;
    
    return $line;
}

sub readType {
	my ($fh, $type) = @_;
	my (%ret, $titles);
	my $handler = $handlers{$type};
	$handler = $handlers{default} unless defined $handler;
	
	($titles) = parseLine(scalar(<$fh>));
	while (my $line = readLineSafe($fh)) {
		$line =~ /^(\S*)/;
		my $begin = deaccent($1);
		if ($begin eq $type) {
			my ($vals, $types) = parseLine($line);				
			my %res = $handler->($vals, $types, $titles);
			$ret{$res{ID}} = \%res;
		} else {
			last;
		}
	}
	
	return \%ret;
}

sub openFindEncoding {
    my ($file) = @_;
    open my $fh, '<:raw', $file or return undef;
    
    my $block;
    read $fh, $block, 512;
    binmode $fh, ':eol(LF)' if index($block, "\r") != -1;
    
    eval { decode_utf8($block, Encode::FB_CROAK) };
    binmode $fh, ($@ ? ':encoding(MacRoman)' : ':utf8');
    
    seek $fh, 0, SEEK_SET;
    return $fh;
}

sub readContext {
	my ($file, @types) = @_;
	my %wantType = map { deaccent($_) => 1 } @types;
	
	my $txt = openFindEncoding($file) or die "Can't open ConText: '$file': $!\n";
	my %ret;
	while (%wantType && (my $line = readLineSafe($txt))) {
		next unless $line =~ /^..Begin (\S+)/;
		my $type = deaccent($1);
		next unless $wantType{$type};
		
		$ret{$type} = readType($txt, $type);
		delete $wantType{$type};
	}
	close $txt;
	return \%ret;
}

{
	my %cache;
	
	sub resource {
		my ($type, %opts) = @_;
		%opts = (cache => 1, %opts);
		$type = deaccent($type);
		
		delete $cache{$type} unless $opts{cache};
		unless (exists $cache{$type}) {
			my $dir = File::Spec->catdir(contextCache(), '.resource');
			my $cacheFile = File::Spec->catfile($dir, $type);
			if ($opts{cache} && -f $cacheFile && -M $cacheFile < -M getConText()) {
				$cache{$type} = retrieve $cacheFile;
			} else {
				my $ret = readContext(getConText(), $type)->{$type};
				if ($opts{cache}) {
					mkdir_p $dir unless -d $dir;
					nstore $ret, $cacheFile;
				}
				$cache{$type} = $ret;
			}
		}
		
		return $cache{$type};
	}
}

sub weaponOutfits {
	my ($outfs, $weaps) = @_;
	my $ret;

	# Find ammo source for each weapon
	for my $weapid (sort { $a <=> $b } keys %$weaps) {
		my $weap = $weaps->{$weapid};
		my $ammo = $weap->{AmmoType};
		my $source = $ammo + 128;
		
		# Some fighter bays seem to just pick this number at random, it 
		# appears meaningless. So only set the source if it seems meaningful.
		if ($ammo >= 0 && $ammo <= 255 && exists $weaps->{$source}) {
			$ret->{$weapid}->{source} = $source;
		} else {
			$ret->{$weapid}->{source} = 0; # sentinel
		}
	}
	
	# Find weapons provided by each outfit
	for my $outfid (sort { $a <=> $b } keys %$outfs) {
		my $outf = $outfs->{$outfid};
		my %mods = multiPropsHash($outf, 'ModType', 'ModVal');
		if (exists $mods{1}) {
			push @{$ret->{$mods{1}[0]}->{"weapon"}}, $outf;
		}
		if (exists $mods{3}) {
			push @{$ret->{$mods{3}[0]}->{"ammo"}}, $outf;
		}
	}
	
	return $ret;
}

sub outfitMass {
	my ($outfs, $id) = @_;
	unless (exists $outfs->{$id}) {
		warn "No outfit ID $id\n";
		return 0;
	}
	return $outfs->{$id}->{Mass};
}

sub weaponMass {
	my ($w2o, $id) = @_;
	unless (exists $w2o->{$id}->{weapon}) {
		warn "No outfit found for weapon ID $id\n";
		return 0;
	}
	return $w2o->{$id}->{weapon}->[0]->{Mass};
}

sub ammoMass {
	my ($w2o, $id) = @_;
	unless (exists $w2o->{$id}->{source}) {
		warn "No source found for weapon ID $id\n";
		return 0;
	}
	my $source = $w2o->{$id}->{source};
	return 0 if $source == 0;
	
	unless (exists $w2o->{$source}->{ammo}) {
		warn "No ammo found for weapon ID $source\n";
		return 0;
	}
	return $w2o->{$source}->{ammo}->[0]->{Mass};
}

sub shipDefaultItems {
    my ($ship) = @_;
    my @items;
    
    for my $kw (sort grep /^WType/, keys %$ship) {
        my $wi = $ship->{$kw};
        next if $wi == 0 || $wi == -1;
        
        (my $kc = $kw) =~ s/Type/Count/;
        (my $ka = $kw) =~ s/WType/Ammo/;
        my $ca = $ship->{$ka};
        
        push @items, { type => 'weapon', id => $wi, count => $ship->{$kc} };
        push @items, { type => 'ammo', id => $wi, count => $ca }
            unless $ca == 0 || $ca == -1;
        
    }
    for my $ko (sort grep /^DefaultItems/, keys %$ship) {
        my $oi = $ship->{$ko};
        next if $oi == 0 || $oi == -1;

        (my $kc = $ko) =~ s/DefaultItems/ItemCount/;
        push @items, { type => 'outfit', id => $oi, count => $ship->{$kc} };
    }
    return @items;
}

sub pilotItems {
    my ($pilot) = @_;
    my $outfs = $pilot->{outf};
    
    my @items;
    for my $i (0..$#$outfs) {
        my $count = $outfs->[$i];
        next if $count == 0 || $count == -1;
        push @items, { type => 'outfit', id => $i + 128, count => $count };
    }
    return @items;
}

sub initMeasureCache {
    my ($cache) = @_;
    my $weaps = ($cache->{weap} ||= resource('weap'));
    my $outfs = ($cache->{outf} ||= resource('outf'));
    my $w2o = ($cache->{w2o} ||= weaponOutfits($outfs, $weaps));
    return ($weaps, $outfs, $w2o);   
}

sub measureItems {
    my ($items, %opts) = @_;
    my ($weaps, $outfs, $w2o) = initMeasureCache($opts{cache});
    
    my $total = 0;
    for my $i (@$items) {
        unless (defined $i->{mass}) {
            $i->{mass} = $i->{type} eq 'weapon'   ? weaponMass($w2o, $i->{id})
                       : $i->{type} eq 'ammo'     ? ammoMass($w2o, $i->{id})
                       : outfitMass($outfs, $i->{id});
        }
        $total += $i->{mass} * $i->{count};
    }
    return $total;
}

sub shipTotalMass {
    my ($ship, %opts) = @_;
    my @items = shipDefaultItems($ship);
    return $ship->{freeMass} + measureItems(\@items, %opts);
}

sub showMass {
    my ($items, %opts) = @_;
    my ($weaps, $outfs, $w2o) = initMeasureCache($opts{cache} ||= {});
    my $free = $opts{free};
    my $total = $opts{total};
    my $filter = $opts{filter} || sub { 1 };
    
    my $accum = measureItems($items, %opts);
    $free = $total - $accum unless defined $free;
    $total = $free + $accum unless defined $total;
    
	printf "  %3d              - free\n", $free;
	for my $i (@$items) {
	    my $rtype = $i->{type} eq 'outfit' ? $outfs : $weaps;
	    my $rez = $rtype->{$i->{id}};
	    printf "  %3d = %4d x %3d - %-6s %4d: %s\n", $i->{mass} * $i->{count},
	        $i->{count}, $i->{mass}, $i->{type}, $i->{id}, resName($rez)
	            if $filter->($i, $rez);
    }
	print "  ", "-" x 50, "\n";
	printf "  %3d              - TOTAL\n", $total;
}

sub myMass {
    my ($file) = @_;
    my $pilot = pilotParse($file);
    my $ship = findRes(ship => $pilot->{ship} + 128);
    my @items = pilotItems($pilot);
    
    my $cache = {};
    my $total = shipTotalMass($ship, cache => $cache);
    showMass(\@items, total => $total, cache => $cache,
        filter => sub { $_[0]{mass} != 0 });
}

sub showShipMass {
	my ($find) = @_;
	my $ship = findRes(ship => $find);
	my @items = shipDefaultItems($ship);
	showMass(\@items, free => $ship->{freeMass});
}

sub tsv {
	my (@data) = @_;
	for my $d (@data) {
		$d =~ s/"/\\"/g;
		$d =~ s/^(.*\s.*)$/"$1"/; # quote;
		$d = '""' if $d eq '';
	}
	return join("\t", @data) . "\n";
}

sub massTable {
    my $cache = {};
    my $ships = resource('ship');
    my @ships = values %$ships;
	for my $ship (@ships) {
		$ship->{TotalMass} = shipTotalMass($ship, cache => $cache);
	}
	
	@ships = sort { $b->{TotalMass} <=> $a->{TotalMass} } @ships;
	print tsv(qw(ID Name SubTitle TotalMass));
	for my $ship (@ships) {
		print tsv(@$ship{qw(ID Name SubTitle TotalMass)});
	}
}

sub list {
	my ($type, $find) = @_;
	$find = '' unless defined $find;
	
	for my $res (findRes($type => $find)) {
		printf "%4d: %s\n", $res->{ID}, resName($res);
	}
}

sub formatField {
	my ($type, $data) = @_;
	if ($type eq 'color') {
		return sprintf '#%06x', $data;
	} elsif ($type =~ /hex(\d+)/) {
		return sprintf "0x%0${1}x", $data;
	} elsif ($type eq 'list') {
		return "\n" . join('',
			map { sprintf "  %3d: %s\n", $_, $data->[$_] } (0..$#$data)
		);
	} else {
		return $data;
	}
}
	
sub resDump {
	my ($type, $find, @fields) = @_;
	my %fields = map { $_ => 1 } @fields;
	
	my $res = findRes($type => $find);
	die "No such item '$find' of type '$type'\n" unless defined $res;
	
	my $idx = 0;
	for my $k (@{$res->{_priv}->{order}}) {
		printf "%s: %s\n", $k,
			formatField($res->{_priv}->{types}->[$idx], $res->{$k}),
			if !@fields || $fields{$k};
		++$idx;
	}
}

sub printMisns {
	my ($verbose, @misns) = @_;
	my $join = $verbose ? "\n\n" : "\n";
	print_breaking join $join,
		map { misnText($_, verbose => $verbose)	} @misns;
}	

sub moreOpts {
    my ($args, %opts) = @_;
    local @ARGV = @$args;
    GetOptions(%opts) or die "Can't get options: $!\n";
    @$args = @ARGV;
}

sub misn {
	my $verbose = 0;
	moreOpts(\@_, 'verbose|v+' => \$verbose);
	printMisns($verbose,
		map { findRes(misn => $_)				}
		map { /^(\d+)-(\d+)$/ ? ($1..$2) : $_	}
		split /,/, join ',', @_
	);
}

sub spobText {
	my ($spec) = @_;
	if ($spec == -2) {
		return "random inhabited";
	} elsif ($spec == -3) {
		return "random uninhabited";
	} elsif ($spec == -4) {
		return "same as AvailStel";
	} elsif ($spec < 5000) {
		my $spob = findRes(spob => $spec);
		my $syst = spobSyst($spec);
		return sprintf "%s in %s", $spob->{Name}, $syst->{Name};
	} elsif ($spec < 9999) {
		my $syst = findRes(syst => $spec - 5000 + 128);
		return sprintf "system adjacent to %s", $syst->{Name};
	} else {
		return govtRel($spec);
	}
}

sub systText {
	my ($spec) = @_;
	if ($spec == -1) {
		return "AvailStel syst";
	} elsif ($spec == -3) {
		return "TravelStel syst";
	} elsif ($spec == -4) {
		return "ReturnStel syst";
	} elsif ($spec == -5) {
		return "adjacent to AvailStel syst";
	} elsif ($spec == -6) {
		return "follow the player";
	} elsif ($spec < 5000) {
		my $syst = findRes(syst => $spec);
		return $syst->{Name};
	} else {
		return govtRel($spec);
	}
}

sub misnText {
	my ($m, %opts) = @_;
	my $ret = '';
	my $section = $opts{verbose} ? "\n\n" : "\n";
	
	# Name
	my $name = $m->{Name};
	if ($name =~ /^(.*);(.*)$/) {
		$ret .= sprintf "%s (%d): %s$section", $2, $m->{ID}, $1;
	} else {
		$ret .= sprintf "%s (%d)$section", $name, $m->{ID};
	}
	
	# Availability
	my %govstr;
	if ((my $spec = $m->{AvailStel}) != -1) {
		$ret .= "AvailStel: " . spobText($spec) . "\n";
	}
	if ((my $loc = $m->{AvailLoc}) != 1) {
		my %locs = (	0 => 'mission computer',	2 => 'pers',
						3 => 'main spaceport',		4 => 'trading',
						5 => 'shipyard',			6 => 'outfitters');
		$ret .= "AvailLoc: $locs{$loc}\n";
	}
	if ((my $rec = $m->{AvailRecord}) != 0) {
		$ret .=  "AvailRecord: $rec\n";
	}
	my $rating = $m->{AvailRating};
	if ($rating != 0 && $rating != -1) {
		$ret .= sprintf "AvailRating: %s\n", ratingStr($rating);
	}
	if ((my $random = $m->{AvailRandom}) != 100) {
		$ret .= "AvailRandom: $random%\n";
	}
	my $shiptype = $m->{AvailShipType};
	if ($shiptype != 00 && $shiptype != -1) { 
		$ret .= "AvailShipType: $shiptype\n";
	}
	if (my $bits = $m->{AvailBits}) {
		$ret .= "AvailBits: $bits\n";
	}
	if (my $succ = $m->{OnSuccess}) {
		$ret .= "OnSuccess: $succ\n";
	}
	$ret .= "\n" if $opts{verbose};
	
	# TODO
	
	# Descs
	if ($opts{verbose}) {
		my $where = 0;
		if ((my $spec = $m->{TravelStel}) != -1) {
			$where = 1;
			$ret .= "TravelStel: " . spobText($spec) . "\n";
		}
		if ((my $spec = $m->{ReturnStel}) != -1) {
			$where = 1;
			$ret .= "ReturnStel: " . spobText($spec) . "\n";
		}
		if ($m->{ShipCount} != -1 && (my $spec = $m->{ShipSyst}) != -2) {
			$where = 1;
			$ret .= "ShipSyst: " . systText($spec) . "\n";
		}
		$ret .= "\n" if $where;
		
		$m->{InitialText} = $m->{ID} + 4000 - 128;
		for my $type (qw(InitialText RefuseText BriefText QuickBrief
				LoadCargText ShipDoneText DropCargText CompText FailText)) {
			my $descid = $m->{$type};
			next if $descid < 128;
			my $txt = findRes(desc => $descid)->{Description};
			$ret .= sprintf "%s: %s$section", $type, $txt;
		}
	}
	return $ret;
}

sub rank {
	my ($type, $field) = @_;
	($type, $field) = ('ship', $type) unless defined $field;
	
	my $res = resource($type);
	for my $r (sort { $b->{$field} <=> $a->{$field} } values %$res) {
		my $cost = $r->{Cost};
		$cost = defined $cost ? commaNum($cost) : '';
		printf "%6s: %-30s %10s\n", $r->{$field}, resName($r), $cost;
	}
}

sub crons {
	my (@search) = @_;
	my $crons = resource('cron');
	my $govts = resource('govt');
	my $strs = resource('STR#');
	
	my @matches;
	if (@search) {
		my %matches;
		my @crons = values %$crons;
		while (my $s = shift @search) {
			my @ok;
			if ($s =~ /^\d+$/) {
				@ok = grep { $_->{ID} eq $s } @crons;
			} else {
				@ok = grep { $_->{Name} =~ /$s/i } @crons;
			}
			$matches{$_} = 1 for map { $_->{ID} } @ok;
		}
		@matches = @$crons{keys %matches};
	} else {
		@matches = values %$crons;
	}
	@matches = sort { $a->{ID} <=> $b->{ID} } @matches;
	
	my @times = map { my $r = $_; map { "$r$_" } qw(Day Month Year) }
		qw(First Last);
	my @defaults = (
		( map { $_ => undef } @times ),
		Random => 100,
		( map { $_ => 0	 } qw(Duration PreHoldoff PostHoldoff) ),
		( map { $_ => '' } qw(EnableOn OnStart OnEnd) ),
	);
	my @flags = ("Iterative entry", "Iterative exit");
	
	for my $c (@matches) {
		printf "%d: %s\n", $c->{ID}, $c->{Name};				# Name
		
		my @df = @defaults;
		while (@df) {										# Field with
			my ($f, $d);										# defaults
			($f, $d, @df) = @df;
			my $v = $c->{$f};
			if (defined $d) {
				next if $v eq $d;
			} else {
				next if $v == 0 || $v == -1;
			}
			print "$f: $v\n";
		}
		
		my $flags = $c->{Flags};								# Flags
		my @pflags;
		for my $i (0..$#flags) {
			my $mask = 1 << $i;
			push @pflags, $flags[$i] if $flags & $mask;
		}
		printf "Flags: %s\n", join ', ', @pflags if @pflags;
		
		for my $cr (qw(Contrib Require)) {						# Contrib/
			my @v = map { (int($_/(1<<16)), $_ % (1<<16)) }		# Require
				map { $c->{"$cr$_"} } (0, 1);
			next unless grep { $_ } @v;
			printf "$cr: 0x%s\n", join ' ', map { sprintf "%04x", $_ } @v;
		}
		
		my $printNews = sub {									# News
			my ($govtname, $strid) = @_;
			my $prefix = "News for $govtname:";
			my @strs = @{$strs->{$strid}{Strings}};
			if (scalar(@strs) == 1 && length($strs[0]) + length($prefix) < 80) {
				print "$prefix $strs[0]\n";
			} else {
				print "$prefix\n";
				print_breaking $_, 1, '  * ', '    ' for @strs;
			}
		};
		
		for my $i (1..4) {
			my $govtid = $c->{"NewsGovt0$i"};
			next if $govtid == 0 || $govtid == -1;
			$printNews->($govts->{$govtid}{Name}, $c->{"GovtNewsStr0$i"});
		}
		my $indie = $c->{"IndNewsStr"};
		$printNews->("Independent", $indie) unless $indie == 0 || $indie == -1;
		
		print "\n";
	}
}

sub rsrc {
	my (@files) = @_;
	
	for my $file (@files) {
	    my $rf = eval { ResourceFork->rsrcFork($file) };
	    $rf ||= eval { ResourceFork->new($file) };
	    if ($@) {
	        print "$file not a resource fork\n";
	        next;
	    }		
		print "File: $file\n";
		for my $type ($rf->types) {
		    my @rs = $rf->resources($type);
			printf "  %4s: %d\n", $type, scalar(@rs);
		}
	}
}

# 0 => no bit, + => positive, - => negative
sub hasBit {
	my ($fld, $bit) = @_;
	
	return 0 unless $fld =~ /(.?)\bb$bit\b/;
	return $1 eq '!' ? -1 : 1;
}

sub bit {
	my ($bit) = @_;
	
	my $bitInResource = sub {
	    my ($type, @fields) = @_;
	    @fields = sort @fields;
	    my $resources = resource($type);
	    for my $r (values %$resources) {
	        my @has;
	        for my $f (@fields) {
	            push @has, $f if hasBit($r->{$f}, $bit);
	        }
	        
	        if (@has) {
	            printf "%s %4d: %s\n", $type, $r->{ID}, resName($r);
				printf "     %s: %s\n", $_, $r->{$_} foreach @has;
	        }
	    }
	};
	
	$bitInResource->('misn', qw(OnSuccess OnRefuse OnAccept OnFailure OnAbort
	        OnShipDone AvailBits));
	$bitInResource->('cron', qw(EnableOn OnStart OnEnd));
	$bitInResource->('outf', qw(Availability OnPurchase OnSell));
	$bitInResource->('ship', qw(Availability AppearOn OnPurchase
	        OnCapture OnRetire));
    $bitInResource->('syst', qw(Visibility));
	
	$bitInResource->('char', qw(onStart));
	$bitInResource->('pers', qw(ActivateOn));
	$bitInResource->('flet', qw(ActivateOn));
	$bitInResource->('spob', qw(OnDominate OnRelease OnDestroy OnRegen));
	$bitInResource->('junk', qw(BuyOn SellOn));
	$bitInResource->('oops', qw(ActivateOn));
	$bitInResource->('desc', qw(Description));
}

sub commodities {
	my ($search) = @_;
	my $spobs = resource('spob');
	
	# Find the spob
	my $spob;
	if ($search =~ /^\d+$/) {
		$spob = $spobs->{$search};
	} else {
		my $re = qr/$search/i;
		($spob) = grep { $_->{Name} =~ /$re/ } values %$spobs;
	}
	printf "%d: %s\n", $spob->{ID}, $spob->{Name};
	my $flags = $spob->{Flags};
	return unless $flags & 0x2;
	
	# Get the prices and names
	my $strs = resource('str#');
	my @prices = @{$strs->{4004}->{Strings}};
	my @names =	@{$strs->{4000}->{Strings}};
	my %mults = (0 => 0, 1 => .8, 2 => 1, 4 => 1.25);
	my %indic = (1 => 'L', 2 => 'M', 4 => 'H');
	
	# Get the status per commodity
	my @status;
	for my $i (0..5) {
		my $shift = (8 - $i - 1) * 4;
		my $status = ($flags & (0xF << $shift)) >> $shift;
		my $price = $prices[$i] * $mults{$status};
		printf "  %-12s: %4d (%s)\n", $names[$i], $price, $indic{$status}
			if $price != 0;
	}
}

sub defense {
	my $ships = resource('ship');
	
	my %def;
	for my $ship (values %$ships) {
		my $total = $ship->{Shield} + $ship->{Armor};
		my $name = $ship->{Name};
		$name .= ", $ship->{SubTitle}" if $ship->{SubTitle};
		
		my $text = sprintf "%5d = %5d + %5d : %-25s %6d K\n", $total,
			@$ship{qw(Shield Armor)}, $name, $ship->{Cost} / 1000;
		$def{$text} = $total;
	}
	
	for my $text (sort { $def{$b} <=> $def{$a} } keys %def) {
		print $text;
	}
}

sub persistent {
	my $outfs = resource('outf');
	
	for my $id (sort keys %$outfs) {
		my $o = $outfs->{$id};
		my $flags = $o->{Flags};
		next unless $flags & 0x4;
		
		printf "%4d: %s\n", $id, $o->{Name};
	}
}

sub cantSell {
	my $outfs = resource('outf');
	
	for my $id (sort keys %$outfs) {
		my $o = $outfs->{$id};
		my $flags = $o->{Flags};
		next unless $flags & 0x8;
		
		printf "%4d: %s\n", $id, $o->{Name};
	}
}

sub govtName {
	my ($govt) = @_;
	return defined $govt ? $govt->{Name} : "independent";
}

sub govtRel {
	my ($spec) = @_;
	
	my $cat = int(($spec+1)/1000);
	my $govid = $spec - ($cat * 1000) + 128;
	my $govt = findRes(govt => $govid);
	
	my %cats = (
		10 => 'govt %s',
		15 => 'ally of govt %s',
		20 => 'any govt but %s',
		25 => 'enemy of govt %s',
		30 => 'class-mate of govt %s',
		31 => 'non-class-mate of govt %s'
	);
	die "No category $cat for spec $spec\n" unless exists $cats{$cat};
	die "No govt id $govid for spec $spec\n"
		unless defined($govt) || $govid == 127;
	
	my $govstr = sprintf "%s (%d)", govtName($govt), $govid;
	return sprintf "$cats{$cat}", $govstr;
}

sub pers {
	my $misns = resource('misn');
	my %persMisns;
	for my $id (keys %$misns) {
		$persMisns{$id} = [] if $misns->{$id}->{AvailLoc} == 2;
	}
	
	my $perss = resource('pers');
	for my $id (keys %$perss) {
		my $pers = $perss->{$id};
		my $link = $pers->{LinkMission};
		next if $link == -1;
		push @{$persMisns{$link}}, $pers;
	}
	
	my $systs = resource('syst');
	my $ships = resource('ship');
	my $govts = resource('govt');
	my $strns = resource('STR#');
	for my $id (sort keys %persMisns) {
		my $misn = $misns->{$id};
		printf "%d: %s\n", $id, $misn->{Name};
		for my $fld (qw(AvailRecord AvailRating AvailRandom AvailShipType
				AvailBits CargoQty)) {
			printf "  %s : %s\n", $fld, $misn->{$fld};
		}
		print "  Unavailable if in freighter\n" if $misn->{Flags} & 0x2000;
		print "  Unavailable if in warship\n" if $misn->{Flags} & 0x4000;
		print "  Require sufficient cargo space\n" if $misn->{Flags2} & 0x0001;
		
		my @from = sort { $a->{ID} <=> $b->{ID} } @{$persMisns{$id}};
		my %from;
		for my $pers (@from) {
			my $ship = $ships->{$pers->{ShipType}};
			my $from = "    Ship: $ship->{Name}\n";
			my $lsyst = $pers->{LinkSyst};
			if ($lsyst >= 128 && $lsyst <= 2175) {
				$from .= "    LinkSyst: " . $systs->{$lsyst}->{Name} . "\n";
			} elsif ($lsyst != -1) {
				$from .= "    LinkSyst: " . govtRel($lsyst) . "\n";
			}
			if ($pers->{Govt} >= 128) {
				my $govt = $govts->{$pers->{Govt}};
				$from .= "    Govt: $govt->{Name}\n";
				$from .= "    Disabled\n" if $govt->{Flags} & 0x0800;
			}
			$from .= "    Board ship for mission\n"
				if $pers->{Flags} & 0x0200;
			$from .= "    Unavailable if in wimpy freighter\n"
				if $pers->{Flags} & 0x1000;
			$from .= "    Unavailable if in beefy freighter\n"
				if $pers->{Flags} & 0x2000;
			$from .= "    Unavailable if in warship\n"
				if $pers->{Flags} & 0x4000;
			my $hq = $pers->{HailQuote};
			if ($hq != -1) {
				$from .= "    HailQuote: " .
					$strns->{7101}->{Strings}->[$hq-1] . "\n";
			}
			push @{$from{$from}}, $pers;
		}
		for my $from (sort { $from{$a}[0]{ID} <=> $from{$b}[0]{ID} }
				keys %from) {
			for my $pers (@{$from{$from}}) {
				printf "  %d: %s\n", $pers->{ID}, $pers->{Name};
			}
			print $from;
		}
	}
		
}

sub djikstra {
	my ($systs, $s1, $s2, %opts) = @_;
	my $cachefun = $opts{cache} || sub { };
	my $debug = $opts{debug};
	my $type = $opts{type} || 'path';	# 'dist' or 'path'
										# 'dist' assumes total coverage
	
	if ($s1 == $s2) {
		return $type eq 'path' ? ($s1, $s2) : 0;
	}
	
	my %seen = ( $s1 => undef );
	my %new = %seen;
	my $dist = 0;
	my $found;
	
	while (1) {
		$dist++;
		
		my @edge = keys %new;
		%new = ();
		for my $systid (@edge) {
			my $syst = $systs->{$systid};
			print "Looking at $syst->{ID}: $syst->{Name}\n" if $debug;
			for my $kcon (grep /^con/, keys %$syst) {
				my $con = $syst->{$kcon};
				next if $con == -1;
				
				unless (exists $seen{$con}) {
					print "Adding $con\n" if $debug;
					$seen{$con} = $systid;
					$cachefun->($s1, $con, $dist);
					$new{$con} = 1;
					
					if ($con == $s2) {
						$found = $dist;
						if ($type eq 'path') {
							my @path;
							my $cur = $s2;
							while (defined $cur) {
								unshift @path, $cur;
								$cur = $seen{$cur};
							}
							return @path;
						}
					}
				}
			}
		}
		
		last unless %new;
	}
	
	die "Can't find connection between $s1 and $s2\n" unless defined $found;
	return $found;
}

sub systDist {
	return memoize(@_, sub {
		my ($memo, $s1, $s2) = @_;
		return djikstra(resource('syst'), $s1, $s2, type => 'dist',
			cache => sub { $memo->(@_); $memo->(@_[1,0,2]) });
	});
}

sub spobDist {
	return memoize(@_, sub {
		my ($memo, $s1, $s2) = @_;
		return systDist(spobSyst($s1)->{ID}, spobSyst($s2)->{ID});
	});
}

sub refSystDist {
	my ($ref, $s1, $s2) = @_;
	return 0 if $s1 == $s2;
	return $ref->{systDist}{$s1}{$s2} if exists $ref->{systDist}{$s1}{$s2};
	
	# Djikstra
	djikstra($ref->{syst}, $s1, $s2, type => 'dist',
		cache => sub {
			$ref->{systDist}{$_[0]}{$_[1]} = $ref->{systDist}{$_[1]}{$_[0]}
				= $_[2];
		}
	);
	
	return $ref->{systDist}{$s1}{$s2};
}

{
	my $cache;
	
	sub spobSyst {
		my ($spobid) = @_;
		
		unless (defined $cache) {
			my $cacheFile = File::Spec->catfile(
				contextCache(), '.spobSyst');
			my $inited = -f $cacheFile;
			
			my %h;
			tie %h, DB_File => $cacheFile
				or die "Can't tie cache: $!\n";
			$cache = \%h;
			
			unless ($inited) {
				my $systs = resource('syst');
				
				for my $systid (sort keys %$systs) {
					my $syst = $systs->{$systid};
					for my $knav (grep /^nav/, keys %$syst) {
						my $nav = $syst->{$knav};
						next if $nav == -1;
						$cache->{$nav} = $syst->{ID};
					}
				}
			}
		}
		
		my $systid = $cache->{$spobid};
		return findRes(syst => $systid) if defined $systid;
		die "Can't find syst for spob $spobid\n";
	}
}

sub refSpobSyst {
	my ($ref, $spob) = @_;
	return $ref->{spobSyst}{$spob} if exists $ref->{spobSyst}{$spob};
	return spobSyst($spob, sub {
		$ref->{spobSyst}{$_[1]} = $_[0]->{ID}
			unless defined $ref->{spobSyst}{$_[1]}
	})->{ID};
}

sub govtsMatching {
	my ($spec) = @_;
	memoize_complex($spec, sub {
		die "Not a govt spec\n" if $spec < 9999 || $spec >= 31000;
		my $cat = int(($spec + 1) / 1000);
		my $id = $spec - 1000 * $cat + 128;
		$id = -1 if $id == 127;
		
		my @govts;
		if ($cat == 10) {
			@govts = ($id);
		} elsif ($cat == 20) {
			@govts = grep { $_ != $id } (-1, keys %{resource('govt')});
		} elsif ($cat == 15 || $cat == 25) {
			my $govt = findRes(govt => $id);
			my $str = $cat == 15 ? "Ally" : "Enemy";
			my @kt = grep /^$str\d/, keys %$govt;
			my @vt = map { $govt->{$_} } @kt;
			@govts = grep { $_ != -1 } @vt;
		} else {
			die "Don't know what to do about govt spec $spec\n";
		}
		my %govts = map { $_ => 1 } @govts;
		return \%govts;
	});
}

sub itemsMatching {
	my ($type, $spec) = @_;
	memoize_complex($type, $spec, sub {
		if ($spec >= 128 && $spec <= 2175) {
			return ($spec);
		} elsif ($spec >= 9999 && $spec < 31000)  {
			my $res = resource($type);
			my $govts = govtsMatching($spec);
			my @items = grep { $govts->{$_->{Govt}} } values %$res;
			my @ids = map { $_->{ID} } @items;
			return @ids;
		} else {
			die "Don't know what to do with spec $spec\n";
		}
	});
}

sub spobsMatching {
	my ($p) = @_;
	
	if ($p == -1 || $p == -2) {
		return map { $_->{ID} }	grep { !($_->{Flags} & 0x20) }
			values %{resource('spob')};
	} else {
		return itemsMatching(spob => $p);
	}
}

sub systsMatching {
	my ($p) = @_;
	
	if ($p == -1 || $p == -32000) {
		return keys %{resource('syst')};
	} else {
		return itemsMatching(syst => $p);
	}
}

sub systsSelect {
	my ($ref, $p) = @_;
	my ($type) = keys %$p;
	my $id = $p->{$type};
	
	unless (exists $ref->{systsSelect}{$type}{$id}) {
		if ($type eq 'spob') {
			my @spobs = spobsMatching($id);
			$ref->{systsSelect}{$type}{$id} =
				[ map { refSpobSyst($ref, $_) } @spobs ];
		} elsif ($type eq 'syst') {
			$ref->{systsSelect}{$type}{$id} = [ $id ];
		} elsif ($type eq 'adjacent') {
			my @systs = systsSelect($ref, { spob => $id });
			my %matches;
			for my $systid (@systs) {
				my $syst = $ref->{syst}{$systid};
				my @kcon = grep /^con/, keys %$syst;
				my @con = map { $syst->{$_} } @kcon;
				@con = grep { $_ != -1 } @con;
				$matches{$_} = 1 for @con;
			}
			my @matches = keys %matches;
			$ref->{systsSelect}{$type}{$id} = [ @matches ];
		} else {
			die "Don't know what to do for type $type\n";
		}
	}
	return @{$ref->{systsSelect}{$type}{$id}}
}

sub placeDist {
	my ($ref, $p1, $p2) = @_;
	return placeDist($ref, $p2, $p1) if $p1 > $p2;
	
	my $key = freeze [ $p1, $p2 ];
	unless (exists $ref->{placeDist}{$key}) {
		my @s1 = systsSelect($ref, $p1);
		my @s2 = systsSelect($ref, $p2);
		
		my $max = 0;
		my $min = 1e6;
		for my $s1 (@s1) {
			for my $s2 (@s2) {
				my $dist = refSystDist($ref, $s1, $s2);
				$max = $dist if $dist > $max;
				$min = $dist if $dist < $min;
			}
		}
		
		my $ret;
		if ($min == $max) {
			$ret = $min;
		} elsif ($max < 2) {
			$ret = $max;
		} elsif ($min <= 2) {
			$ret = 2;
		} else {
			$ret = $min;
		}
		$ref->{placeDist}{$key} = $ret;
	}
	return $ref->{placeDist}{$key};
}

# FIXME: Pretends that each pair of places is independent, when of course
# each intermediate place must remain the same in the next pair. 
sub placeListDist {
	my ($ref, @places) = @_;
	
	my $jump = 0;
	for (my $i = 0; $i < $#places; ++$i) {
		my $src = $places[$i];
		my $dst = $places[$i+1];
		$jump += placeDist($ref, $src, $dst);
	}
	return $jump;
}

sub misnDist {
	my ($ref, $misn) = @_;
	die "Can't do pers-missions yet\n" if $misn->{AvailLoc} == 2;
	my $land = 0;
	
	my $avail = $misn->{AvailStel};
	my $travel = $misn->{TravelStel};
	my $return = $misn->{ReturnStel};
	$return = $avail if $return == -4;
	
	my @places = ({ spob => $avail });
	
	my $shipsyst = $misn->{ShipSyst};
	my $shipgoal = $misn->{ShipGoal};
	if (grep { $shipgoal == $_ } (0, 1, 2, 4, 5, 6)) {
		my %misnSysts = (-1 => $avail, -3 => $travel, -4 => $return);
		if (exists $misnSysts{$shipsyst}) {
			push @places, { spob => $misnSysts{$shipsyst} };
		} elsif ($shipsyst == -5) {
			push @places, { adjacent => $avail };
		} else {
			push @places, { syst => $shipsyst };
		}
	}
	
	if ($travel != -1) {
		push @places, { spob => $travel };
		$land++;
	}
	if ($return != -1) {
		push @places, { spob => $return };
		$land++;
	}
	
	return ($land, placeListDist($ref, @places));
}

sub limit {
	my $misns = resource('misn');
	
	my $ref;
	my $cache = 'cache/dist';
	if (-f $cache) {	# FIXME: Check out-of-date?
		$ref = retrieve($cache);
	} else {
		$ref = { map { $_ => resource($_) } qw(spob syst govt) };
	}
	
	my @limited;
	for my $misnid (sort keys %$misns) {
		my $misn = $misns->{$misnid};
		my $limit = $misn->{TimeLimit};
		next if $limit == -1 || $limit == 0;
		
		my ($land, $jump);
		eval { ($land, $jump) = misnDist($ref, $misn) };
		if ($@) {
			print "WARNING: $misnid: $@";
		} else {
			my $jumpdays = 100;
			$jumpdays = ($limit - $land) / $jump unless $jump == 0;
			push @limited, {
				limit	=> $limit,
				land	=> $land,
				jump	=> $jump,
				jumpdays => $jumpdays,
				misn	=> $misn
			};
		}
	}
	
	for my $h (sort { $b->{jumpdays} <=> $a->{jumpdays} } @limited) {
		my $m = $h->{misn};
		printf "Days: %6.2f  Time: %3d  Land: %d  Jump: %2d   %4d: %s\n",
			@$h{qw(jumpdays limit land jump)}, @$m{qw(ID Name)};
	}
	nstore $ref, $cache;
}

sub dist {
	my @searches = @_;
	my $systs = resource('syst');
	
	my ($p1, $p2) = map { findRes(syst => $_)->{ID} } @searches;
	my @path = djikstra($systs, $p1, $p2, type => 'path');
	
	printf "Distance: %d\n", scalar(@path) - 1;
	for (my $i = 0; $i <= $#path; ++$i) {
		printf "%2d: %s\n", $i, $systs->{$path[$i]}{Name};
	}
}

sub printTechs {
	my ($h) = @_;
	for my $t (sort { $b <=> $a } keys %$h) {
		my @sps = @{$h->{$t}};
		
		# uniquify
		my %sps = map { $_->{ID} => $_ } @sps;
		@sps = values %sps;
		@sps = sort { $a->{Name} cmp $b->{Name} } @sps;
		
		my $first = shift @sps;
		printf "  %4d: %s (%d)\n", $t, $first->{Name},
			$first->{ID};
		printf "        %s (%d)\n", $_->{Name} , $_->{ID}
			for @sps;
	}
}

sub spobtech {
	my ($filtType, @filtVals) = @_;
	$filtType = 'none' unless defined $filtType;
	if ($filtType =~ /^\d+$/) {
		($filtType, @filtVals) = ('tech', $filtType, @filtVals);
	}
	
	my $sps = resource('spob');
	my $govt;
	if ($filtType eq 'govt') {
		my @govts = map { findRes(govt => $_) } @filtVals;
		$govt = { map { $_->{ID} => 1 } @govts };
	}
	
	my %tech;
	my %special;
	for my $sid (sort keys %$sps) {
		my $s = $sps->{$sid};
		next if defined $govt && !$govt->{$s->{Govt}};
		push @{$tech{$s->{TechLevel}}}, $s;
		for my $kst (grep /^SpecialTech/, keys %$s) {
			my $st = $s->{$kst};
			next if $st == -1;
			push @{$special{$st}}, $s;
		}
	}
	
	if ($filtType eq 'tech') {
		my %ok = map { $_ => 1 } @filtVals;
		for my $t (keys(%tech), keys(%special)) {
			next if $ok{$t};
			delete $tech{$t};
			delete $special{$t};
		}
	}
	
	print "Tech levels:\n";
	printTechs \%tech;
	print "Special techs:\n";
	printTechs \%special;
}

sub outftech {
	my $os = resource('outf');
	my %tech;
	for my $oid (sort keys %$os) {
		my $o = $os->{$oid};
		push @{$tech{$o->{TechLevel}}}, $o;
	}
	printTechs \%tech;
}

sub shiptech {
	my $ss = resource('ship');
	my %tech;
	for my $sid (sort keys %$ss) {
		my $s = $ss->{$sid};
		push @{$tech{$s->{TechLevel}}}, $s;
	}
	printTechs \%tech;
}

sub readPilotLogItem {
	my $lines = shift;
	return { } unless @$lines;
	
	# Get the lines for this sub-item
	my $first = shift @$lines;
	$first =~ /^(\s*)/;
	my $indent = length($1);
	my @mine = ($first);
	while (defined (my $line = shift @$lines)) {
		$line =~ /^(\s*)/;
		if (length($1) < $indent || $line =~ /- end of log -/) {
			unshift @$lines, $line;
			last;
		} else {
			push @mine, $line;
		}
	}
		
	# Parse the lines
	if ($first !~ /:/) {	# simple array
		return [ map { s/^\s*(\S.*?)\s*$/$1/; $_ } @mine ];
	} else {				# hash
		my %data;
		while (defined (my $line = shift @mine)) {
			if ($line =~ /^\s*(\S.*?):\s*(\S.*?)\s*$/) {	# simple Key: Value
				$data{$1} = $2;
			} elsif ($line =~ /^\s*(\S.*?):\s*$/) {			# sub-item
				my $key = $1;
				$data{$key} = readPilotLogItem(\@mine);
			} else {
				die "Can't parse line $line\n";
			}
		}
		return \%data;
	}
}

{
	my $cache;
	
	sub readPilotLog {
		my (%opts) = (cache => 1, @_);
		return $cache if defined $cache && $opts{cache};
		
		# Read
		open my $log, $pilotLog or die "Can't read pilot log: $!\n";
		my $txt = join('', <$log>);
		close $log;
		
		# Decode
		$txt = decode('MacRoman', $txt);
		my @lines = split /\r/, $txt;
		@lines = grep /\S/, @lines; # remove whitespace lines
		
		# Read the header info
		my %header;
		while (defined(local $_ = shift @lines)) {
			next if /EV Nova pilot data dump/;
			if (/^Output on (\S+) at (.*?)\s*$/) {
				@header{qw(Date Time)} = ($1, $2);
				last;
			} else {
				die "Can't parse line $_\n";
			}
		}
		
		my $data = readPilotLogItem(\@lines);
		$data->{$_} = $header{$_} for keys %header;
		
		$cache = $data if $opts{cache};
		return $data;
	}
}

sub allRatings {
	my $strs = resource('STR#');
	my @ratings = @{$strs->{138}{Strings}};
	my @kills = (0, 1, 100, 200, 400, 800, 1600, 3200, 6400, 12_800, 25_600);
	return map { $kills[$_] => $ratings[$_] } (0..$#ratings);
}

sub myRating {
	my ($pilot) = @_;
	
	my $mine;
	if (defined $pilot) {
		$mine = pilotParse($pilot)->{rating};
	} else {
		$mine = readPilotLog->{Kills};
	}
	my %ratings = allRatings;
	my ($r) = grep { $_ <= $mine } sort { $b <=> $a } keys %ratings;
	return wantarray ? ($r, $mine) : $ratings{$r};
}

sub ratingStr {
	my ($rating) = @_;
	my %ratings = allRatings();
	my ($cat) = grep { $_ <= $rating } sort { $b <=> $a } keys %ratings;
	my $str = ($rating == $cat) ? $ratings{$cat}
		: sprintf "%s + %s", $ratings{$cat}, commaNum($rating - $cat); 
	return sprintf "%s (%s)", commaNum($rating), $str;
}

sub commaNum {
	my ($n) = @_;
	return $n if $n < 1000;
	return commaNum(int($n/1000)) . sprintf ",%03d", $n % 1000;
}

sub rating {
	my ($pilot) = @_;
	
	my %ratings = allRatings;
	my ($myRating, $myKills) = myRating($pilot);
	for my $kills (sort { $a <=> $b } keys %ratings) {
		my $k = commaNum($kills);
		my $r = $ratings{$kills};
		if ($kills == $myRating) {
			printf "%7s: %s    <== %s\n", $k, $r, ratingStr($myKills);
		} else {
			printf "%7s: %s\n", $k, $r;
		}
	}
}

sub dude {
	my ($dudeid) = @_;
	my $dudes = resource('dude');
	my $dude = $dudes->{$dudeid};
	
	my %ships;
	for my $kt (grep /^ShipTypes\d+/, keys %$dude) {
		(my $kp = $kt) =~ s/ShipTypes(\d+)/Probs$1/;
		my ($vt, $vp) = map { $dude->{$_} } ($kt, $kp);
		next if $vt == -1;
		$ships{$vt} += $vp;
	}

	printf "Dude %d: %s\n", $dudeid, $dude->{Name};
	my $ships = resource('ship');
	for my $s (sort { $ships{$b} <=> $ships{$a} } keys %ships) {
		printf "%3d%% - %s\n", $ships{$s}, resName($ships->{$s});
	}
	printf "\nStrength: %.2f\n", scalar(dudeStrength($dude));
}

sub records {
	my $strs = resource('STR#');
	my @recs = @{$strs->{134}{Strings}};
	
	shift @recs; # N/A
	my @bad = splice @recs, 0, 9;
	my @good = splice @recs, 0, 6;
	for my $r (reverse(@bad), @good) {
		print "$r\n";
	}
}

sub suckUp {
	my (@govts) = @_;
	@govts = map { scalar(findRes(govt => $_)) } @govts;
	my %govts = map { $_->{ID} => 1 } @govts;
	
	my $ms = resource('misn');
	my %ms;
	for my $mid (sort keys %$ms) {
		my $m = $ms->{$mid};
		my $gv = $m->{CompGovt};
		next unless $govts{$gv};
		push @{$ms{$m->{CompReward}}}, $m;
	}
	
	for my $cr (sort { $b <=> $a } keys %ms) {
		for my $m (@{$ms{$cr}}) {
			printf "%3d: %s (%d)\n", $cr, $m->{Name}, $m->{ID};
		}
	}
}

sub resName {
	my ($res) = @_;
	my $name = $res->{Name};
	my $sub = $res->{SubTitle};
	if (deaccent($res->{Type}) eq 'ship' && $sub) {
		return "$name, $sub";
	} else {
		return $name;
	}
}

sub findRes {
	my ($type, $find) = @_;
	
	my $res = resource($type, cache => 1);
	if ($find =~ /^\d+$/) {
		my $r = $res->{$find};
		return wantarray ? ($r) : $r;
	}
	
    my @res = sort { $a->{ID} <=> $b->{ID} } values %$res;
    
    $find =~ s/\W//g; # strip punct
    return @res if $find eq '';
    
    $find = qr/$find/i;
	my $whole = qr/^$find$/i;
	my @found;
	for my $r (@res) {
		my $name = resName($r);
		$name =~ s/\W//g; # strip punct
		return $r if $name =~ /$whole/ && !wantarray;
		push @found, $r if $name =~ /$find/;
	}
	
	return wantarray ? @found : $found[0];
}

sub escorts {
	my $pl = readPilotLog(cache => 1);
	my $escorts = $pl->{Escorts};
	
	return () if scalar(@$escorts) == 1 && $escorts->[0] eq 'none';
	my @escorts;
	for my $e (@$escorts) {
		$e =~ /.*\((\d+)\) -/ or die "Can't parse escort '$e'\n";
		push @escorts, $1;
	}
	return @escorts;
}

sub myShip {
	my $pl = readPilotLog(cache => 1);
	my $type = $pl->{'Ship type'};
	$type =~ /\((\d+)\)$/ or die "Can't parse ship type '$type'\n";
	return $1;
}

sub myOutfits {
	my $pl = readPilotLog(cache => 1);
	my $outfits = $pl->{'Items currently owned'};
	
	return () if scalar(@$outfits) == 1 && $outfits->[0] eq 'none';
	my %outfits;
	for my $o (@$outfits) {
		$o =~ /^(\d+).*\((\d+)\)$/ or die "Can't parse outfit '$o'\n";
		$outfits{$2} = $1;
	}
	return %outfits;
}

sub capture {
	my ($find) = @_;
	my $ships = resource('ship');
	my $outfs = resource('outf');
	
	my $self = $ships->{myShip()};
	my $enemy = findRes(ship => $find);
	
	# Add escorts
	my $crew = $self->{Crew};
	my $strength = $self->{Strength};
	for my $e (escorts) {
		my $s = $ships->{$e};
		$crew += $s->{Crew} / 10;
		$strength += $s->{Strength} / 10;
	}
	
	# Add outfits
	my $pct = 0;
	my %myOutfs = myOutfits;
	for my $outfid (keys %myOutfs) {
		my $count = $myOutfs{$outfid};
		my $o = $outfs->{$outfid};
		for my $kmt (grep /^ModType\d*$/, keys %$o) {
			my $mt = $o->{$kmt};
			next if $mt != 25;
			(my $kmv = $kmt) =~ s/^ModType(\d*)$/ModVal$1/;
			my $mv = $o->{$kmv};
			if ($mv > 0) {
				$crew += $count * $mv;
			} else {
				$pct -= $count * $mv;
			}
		}
	}
	
	# Calculate
	my $capture = $crew / $enemy->{Crew} * 10;
	if ($strength > 5 * $enemy->{Strength}) {
		$capture += 10;
	}
	$capture += $pct;
	my ($min, $max) = ($capture - 5, $capture + 5);
	for my $o ($min, $max) {
		$o = 75 if $o > 75;
		$o = 1 if $o < 1;
	}
	
	printf "To capture %s\n", resName($enemy);
	printf "Min odds: %6.2f\n", $min;
	printf "Max odds: %6.2f\n", $max;
}

sub where {
	my ($find, $max) = @_;
	$max = 20 unless defined $max;
	my $ship = findRes(ship => $find);
	
	my %dudes;
	my $dudes = resource('dude');
	for my $dude (values %$dudes) {
		for my $kt (grep /^ShipTypes\d+/, keys %$dude) {
			(my $kp = $kt) =~ s/ShipTypes(\d+)/Probs$1/;
			my ($vt, $vp) = map { $dude->{$_} } ($kt, $kp);
			next if $vt != $ship->{ID};
			$dudes{$dude->{ID}} += $vp;
		}
	}
	
	my %systs;
	my $systs = resource('syst');
	for my $syst (values %$systs) {
		my $prob = 0;
		for my $kt (grep /^DudeTypes\d+/, keys %$syst) {
			(my $kp = $kt) =~ s/DudeTypes(\d+)/Probs$1/;
			my ($vt, $vp) = map { $syst->{$_} } ($kt, $kp);
			next unless $dudes{$vt};
			$prob += ($vp / 100) * $dudes{$vt};
		}
		$systs{$syst->{ID}} = 100 - 100*(1-($prob/100))**($syst->{AvgShips});
	}
	
	my $count = 0;
	printf "Systems with %s (%d):\n", resName($ship), $ship->{ID};
	for my $sid (sort { $systs{$b} <=> $systs{$a} } keys %systs) {
		my $syst = $systs->{$sid};
		my ($govt) = findRes(govt => $syst->{Govt});
		printf "%6.2f %% - %4d: %-20s (%-20s)\n", $systs{$sid}, $sid, $syst->{Name}, govtName($govt);
		last if $count++ >= $max;
	}
}

{
	my %memory;
	
	sub memory {
		my ($name) = @_;
		unless (defined $memory{$name}) {
			my $dir = File::Spec->catfile(contextCache(), '.memoize');
			mkdir_p $dir unless -d $dir;
			my $file = File::Spec->catfile($dir, $name);
			
			my %hash;
			tie %hash, 'DB_File', $file or die "Can't tie cache: $!\n";
			$memory{$name} = \%hash;
		}
		return $memory{$name};
	}
}			

sub memoize {
	memoize_internal(
		args => \@_,
		encode => sub { join(',', @_) },
		decode => sub { $_[0] },
	);
}

sub memoize_complex {
	memoize_internal(
		args => \@_,
		encode => sub { freeze \@_ },
		decode => sub { (thaw $_[0])->[0] },
	);
}

sub memoize_internal {
	my %opts = @_;
	my @args = @{$opts{args}};
	
	my $code = pop @args;
	my $name = (caller(2))[3];
	my $memory = memory($name);
	my $key = $opts{encode}->($name, @args);
	
	my $ret;
	if (exists $memory->{$key}) {
		$ret = $opts{decode}->($memory->{$key});
	} else {
		my $memo = sub {
			my $ret = pop @_;
			my $key = $opts{encode}->($name, @_);
			$memory->{$key} = $opts{encode}->($ret);
		};
		unshift @args, $memo;
		$ret = wantarray ? [ $code->(@args) ] : scalar( $code->(@args) );
		$memory->{$key} = $opts{encode}->($ret);
	}
	return wantarray ? @$ret : $ret;
}

sub cargoName {
	my ($id) = @_;
	return 'Empty' if $id == -1;
	
	if ($id < 128) {
		return resource('str#')->{4000}{Strings}[$id];
	} else {
		return resource('junk')->{$id}{Name};
	}
}

sub cargoShortName {
	my ($id) = @_;
	return 'Empty' if $id == -1;
	
	if ($id < 128) {
		return resource('str#')->{4002}{Strings}[$id];
	} else {
		return resource('junk')->{$id}{Abbrev};
	}
}

sub cargoPrice {
	my ($id, $level) = @_;
	return 0 if $id == -1;
	
	my $base;
	if ($id < 128) {
		$base = resource('str#')->{4004}{Strings}[$id];
	} else {
		$base = resource('junk')->{$id}{BasePrice};
	}
	
	my %levels = (
		Low		=> 0.8,
		Med		=> 1,
		High	=> 1.25,
	);
	return $levels{$level} * $base;
}
	
sub spobJunks {
	my ($spob) = @_;
	memoize_complex($spob->{ID}, sub {
		my ($memo, $spobid) = @_;
		
		my %spobs;
		my $junks = resource('junk');
		for my $junkid (sort keys %$junks) {
			my $junk = $junks->{$junkid};
			for my $k (grep /^(Bought|Sold)At\d$/, keys %$junk) {
				my $v = $junk->{$k};
				$k =~ /^(.*)At/;
				$spobs{$v}{$junkid} = $1 unless $v == 0 || $v == -1;
			}
		}
		
		$memo->($_, $spobs{$_}) for keys %spobs;
		return $spobs{$spobid};
	});
}

# (ID of cargo type => price level) at a spob (below 128 = commodities)
sub cargo {
	my ($spob) = @_;
	
	# Junks
	my $cargo = spobJunks($spob);
	for my $k (keys %$cargo) {
		$cargo->{$k} = $cargo->{$k} eq 'Bought' ? 'High' : 'Low';
	}
	
	# Commodities
	my $flags = $spob->{Flags};
	my %levels = (1 => 'Low', 2 => 'Med', 4 => 'High');
	my @status;
	for my $i (0..5) {
		my $shift = (8 - $i - 1) * 4;
		my $status = ($flags & (0xF << $shift)) >> $shift;
		$cargo->{$i} = $levels{$status} if $status != 0;
	}
	
	return $cargo;
}

sub legsForSpobs {
	my ($s1, $s2, $c1, $c2, $dist) = @_;
	
	my @routes;
	for my $c (keys %$c1) {
		next unless exists $c2->{$c};
		next if $c1->{$c} eq $c2->{$c};
		
		my ($p1, $p2) = map { cargoPrice($c, $_->{$c}) } ($c1, $c2);
		my $diff = $p1 - $p2;
		
		my ($src, $dst) = $diff > 0 ? ($s2, $s1) : ($s1, $s2);
		push @routes, {
			src		=> $src,
			dst		=> $dst,
			profit	=> abs($diff),
			dist	=> $dist,
			cargo	=> $c,
		};
	}
	
	my %empty = (profit => 0, dist => $dist, cargo => -1);
	push @routes, { %empty, src => $s1, dst => $s2 },
		{ %empty, src => $s2, dst => $s1 };
	return @routes;
}

sub tradeLegs {
	memoize_complex(sub {
		my $spobs = resource('spob');
		my @spobids = sort keys %$spobs;
		
		# Only keep spobs that are present at the start
		@spobids = grep {
			my $syst = eval { spobSyst($_) };
			$spobs->{$_}{Flags} & 0x2 && !$@
				&& initiallyTrue($syst->{Visibility});
		} @spobids;
		
		my %cargos = map { $_ => cargo($spobs->{$_}) } @spobids;
		
		# Get all the trade routes
		my @routes;
		while (defined(my $spobID = shift @spobids)) {
			my $cargo = $cargos{$spobID};
			for my $otherID (@spobids) {
				my $dist = spobDist($spobID, $otherID);
				
				my $otherCargo = $cargos{$otherID};
				push @routes, legsForSpobs($spobID, $otherID,
					$cargo, $otherCargo, $dist);
			}
		}
		return @routes;
	});
}

sub orderedLegs {
	my @legs = @_;
	my %legs;
	
	for my $leg (@legs) {
		push @{$legs{$leg->{src}}}, $leg;
	}
	return \%legs;
}

sub legToRoute {
	my ($leg) = @_;
	
	my $ret = {
		legs	=> [ $leg ],
		numlegs	=> 1,
		( map { $_ => $leg->{$_} } qw(src dst dist profit) ),
		seen	=> { $leg->{dst} => 1 },
	};
	$ret->{rating} = rateRoute($ret);
	return $ret;
}

sub tryAddLeg {
	my ($route, $leg) = @_;

	return undef if $route->{seen}{$leg->{dst}};
	
	my $new = addLeg($route, $leg);
	
	# Heuristics for rejection
#	return undef if $new->{rating} < $route->{rating}
#		&& spobDist(@$new{'src', 'dst'}) > spobDist(@$route{'src', 'dst'});
	
	return $new;
}

sub addLeg {
	my ($route, $leg) = @_;
		
	my $ret = {
		legs	=> [ @{$route->{legs}}, $leg ],
		src		=> $route->{src},
		dst		=> $leg->{dst},
		dist	=> $route->{dist} + $leg->{dist},
		profit	=> $route->{profit} + $leg->{profit},
		numlegs	=> $route->{numlegs} + 1,
		seen	=> { %{$route->{seen}}, $leg->{dst} => 1 },
	};
	$ret->{rating} = rateRoute($ret);
	return $ret;
}

sub rateRoute {
	my ($route) = @_;
	return $route->{profit} / (3 * $route->{dist} + $route->{numlegs});
}

sub completeRoute {
	my ($route) = @_;
	return ($route->{src} == $route->{dst});
}

sub printRoute {
	my ($route) = @_;
	
	my $spobs = resource('spob');
	my $legs = '';
	for my $leg (@{$route->{legs}}) {
		$legs .= sprintf "%s (%s) => ", $spobs->{$leg->{src}}{Name},
			cargoShortName($leg->{cargo});
	}
	
	my $out = sprintf "%7.2f: %s%s", rateRoute($route), $legs, 
		$spobs->{$route->{dst}}{Name};
	print_breaking $out, 1, '', '         ';
}

sub dumpRoutes {
	my ($title, $routes) = @_;
	print "$title:\n";
	for (my $i = 0; $i < 10 && $i <= $#$routes; ++$i) {
		printRoute($routes->[$i]);
	}
	print "\n";
}

sub dumpTrade {
	my ($iters, $routes, $complete) = @_;
	printf "ITERATIONS: %6d\n", $iters;
	dumpRoutes('ROUTES', $routes);
	dumpRoutes('COMPLETE', $complete);
	print "\n\n";
}

sub routeUniq {
	my ($route) = @_;
	my @spobs = map { $_->{src} } @{$route->{legs}};
	my $min = min(@spobs);
	my ($idx) = grep { $spobs[$_] == $min } (0..$#spobs);
	push @spobs, splice @spobs, 0, $idx;
	return join ',', @spobs;
}

sub trade {
	my $max = shift || 1000;
	my @legs = tradeLegs();
	my $legs = orderedLegs(@legs);
	
	# Transform to routes
	my @routes = map { legToRoute($_) } grep { $_->{profit} > 0 } @legs;
	@routes = sort { $b->{rating} <=> $a->{rating} } @routes;
	my @complete;
	my %dupCheck;
	
	my $iters = 0;
	while ($iters < $max) {		
		++$iters;
		dumpTrade($iters, \@routes, \@complete) if $iters % 10 == 0;
		
		my $r = shift @routes;
		next unless defined $legs->{$r->{dst}};
		my @next = @{$legs->{$r->{dst}}};
		for my $leg (@next) {
			my $new = tryAddLeg($r, $leg);
			next unless defined $new;
			if (completeRoute($new)) {
				push @complete, $new unless $dupCheck{routeUniq($new)}++;
				@complete = sort { $b->{rating} <=> $a->{rating} } @complete;
			} else {
				push @routes, $new;
			}
		}
		
		@routes = sort { $b->{rating} <=> $a->{rating} } @routes;
	}
	
}

sub printLegs {
	my @legs = tradeLegs();
	my @routes = map { legToRoute($_) } grep { $_->{profit} > 0 } @legs;
	@routes = sort { $b->{rating} <=> $a->{rating} } @routes;
	
	
	my $spobs = resource('spob');
	for my $r (@routes) {
		printf "%6.2f (%4d, %2d): %-12s from %-15s to %-15s\n", $r->{rating},
			$r->{profit}, $r->{dist}, cargoName($r->{legs}[0]{cargo}),
			$spobs->{$r->{src}}{Name}, $spobs->{$r->{dst}}{Name};
	}
}	

{
	my %single = map { $_ => 1 } qw(! g | &);
	my %num = map { $_ => 1 } qw (b p o e);
	my %plevel = ( '(' => 1, ')' => -1 );
	
	sub bitTestTokenize {
		my (@chars) = @_;
		
		# Tokenize
		my @toks;
		while (defined(my $c = shift @chars)) {
			if ($single{$c}) {
				push @toks, { type => $c };
			} elsif ($num{$c}) {
				my $n = '';
				$n .= shift @chars while @chars && $chars[0] =~ /\d/;
				die "Incomplete bit term\n" if $n eq '';
				push @toks, { type => $c, num => $n };
			} elsif ($c =~ /\d/) {
				$c .= shift @chars while @chars && $chars[0] =~ /\d/;
				push @toks, { type => '1', num => $c };
			} elsif ($c eq '(') {
			    my $count = 1;
			    my @s;
			    while (1) {
			        defined(my $s = shift @chars) or croak "Incomplete parens\n";
			        $count += $plevel{$s} || 0;
			        last unless $count;
			        push @s, $s;
			    }
				push @toks, { type => $c, expr => bitTestParseInner(@s) };
			} else {
				die "Unknown character $c\n";
			}
		}
		
		return @toks;
	}
}

sub bitTestResolveToks {
	my (@toks) = @_;
	die "No tokens\n" unless @toks;
	
	# and, or
	for my $op (qw(& |)) {
		if (grep { $_->{type} eq $op } @toks) {
			my $etype = $op eq '&' ? 'and' : 'or';
			
			my (@subs, @cur);
			while (defined (my $t = shift @toks)) {
				if ($t->{type} eq $op) {
					push @subs, bitTestResolveToks(@cur);
					@cur = ();
				} else {
					push @cur, $t;
				}
			}
			push @subs, bitTestResolveToks(@cur);
			return [ $etype => \@subs ];
		}
	}
	
	# not
	if ($toks[0]{type} eq '!') {
		shift @toks;
		return [ 'not' => bitTestResolveToks(@toks) ];
	}
	
	die "Too many tokens\n" if scalar(@toks) != 1;
	my $tok = $toks[0];
	
	# parens
	if ($tok->{type} eq '(') {
		return $tok->{expr};
	}
	
	my %terms = ( b => 'bit', p => 'paid', g => 'gender', o => 'outfit',
		e => 'explored', '1' => 'constant' );
	die "Bad token $tok->{type}\n" unless $terms{$tok->{type}};
	my $etype = $terms{$tok->{type}};
	my $val = $tok->{num}; # possibly undef
	return [ $etype => $val ];
}

sub bitTestParseInner {
	my (@chars) = @_;
	my @toks = bitTestTokenize(@chars);
	return bitTestResolveToks(@toks);
}	

sub bitTestParse {
	my ($expr) = @_;
	$expr =~ s/\s//g;
	$expr = lc $expr;
	return [ constant => 1 ] unless $expr; # empty means true
	return bitTestParseInner(split //, $expr);
}

sub bitTestEvalParsed {
	my ($termSub, $parsed) = @_;
	my ($etype, $val) = @$parsed;
	if ($etype eq 'and') {
		return !grep { !bitTestEvalParsed($termSub, $_) } @$val;
	} elsif ($etype eq 'or') {
		return grep { bitTestEvalParsed($termSub, $_) } @$val;
	} elsif ($etype eq 'not') {
		return !bitTestEvalParsed($termSub, $val);
	} elsif ($etype eq 'constant') {
		return $val;
	} else {
		return $termSub->($etype, $val);
	}
}

sub bitTestEval {
	my ($termSub, $expr) = @_;
	return bitTestEvalParsed($termSub, bitTestParse($expr));
}

sub bitTestEvalSimple {
	my ($expr, @bits) = @_;
	my %bits = map { $_ => 1 } @bits;
	
	my $termSub = sub {
		my ($type, $val) = @_;
		return exists $bits{$val} if $type eq 'bit';
		return 1;
	};
	return bitTestEval($termSub, $expr);
}

sub bitTestEvalPilot {
	my ($expr, $pilot) = @_;
	my $termSub = sub {
		my ($type, $val) = @_;
		return $pilot->{bit}[$val] if $type eq 'bit';
		return 1;
	};
	return bitTestEval($termSub, $expr);
}

sub bitTestPrint {
	my $ret = bitTestEvalSimple(@_);
	print($ret ? "True" : "False", "\n");
}

sub initiallyTrue {
	my ($val) = @_;
	return bitTestEvalSimple($val);
}

sub printSpobSyst {
	my ($find) = @_;
	my $spob = findRes(spob => $find);
	my $syst = spobSyst($spob->{ID});
	print $syst->{Name}, "\n";
}

sub diff {
	my ($type, $f1, $f2) = @_;
	my ($r1, $r2) = map { findRes($type => $_) } ($f1, $f2);
	
	my $idx = 0;
	for my $k (@{$r1->{_priv}->{order}}) {
		my ($v1, $v2) = map { $_->{$k} } ($r1, $r2);
		
		if ($v1 ne $v2) {
			my $type = $r1->{_priv}->{types}->[$idx];
			printf "%15s: %-31s %-31s\n", $k,
				map { formatField($type, $_) } ($v1, $v2);
		}
		++$idx;
	}
}

sub fieldType {
	my ($res, $field) = @_;
	
	my @order = @{$res->{_priv}{order}};
	my ($idx) = grep { $order[$_] eq $field } (0..$#order);
	return $res->{_priv}{types}[$idx];
}

sub mapOver {
	my ($type, $field) = @_;
	return find($type, $field, "1 == 1");
}

sub find {
	my ($type, $field, $spec) = @_;
	$spec = "\$_ == $spec" unless $spec =~ m,[<>=!/&|^()],;
	
	my $filt = eval "sub { $spec }";
	die $@ if $@;
	
	my $res = resource($type);
	my $ftype;
	for my $id (sort keys %$res) {
		my $r = $res->{$id};
		$ftype = fieldType($r, $field) unless defined $ftype;
		
		my $val = $r->{$field};
		local $_ = $val;
		next unless $filt->();
		
		printf "%6s: %s (%d)\n", formatField($ftype, $val), resName($r), $id;
	}
}

sub readResources {
	my ($file, @specs) = @_;
	
	my @ret;
    my $rf = eval { ResourceFork->rsrcFork($file) };
    $rf ||= ResourceFork->new($file);		
	for my $spec (@specs) {
		my $r = $rf->resource($spec->{type}, $spec->{id});
		my %res = %$spec;
		$res{name} = $r->{name};
		$res{data} = $r->read;
		push @ret, \%res;
	}
	
	return @ret;
}

sub writeResources {
	my ($file, @specs) = @_;
    my $rf = eval { ResourceFork->rsrcFork($file) };
    $rf ||= ResourceFork->new($file);		
	for my $spec (@specs) {
		my $r = $rf->resource($spec->{type}, $spec->{id});
		# no name?
		die "Can't change name" unless $r->{name} eq $spec->{name};
		$r->write($spec->{data});
	}
}

sub hexdump {
	my ($data) = @_;
	my @bytes = unpack 'C*', $data;
	
	my $last;
	my $continuing = 0;
	my $offset = 0;
	my $perline = 16;
	my $linelen = 3 * $perline + int($perline / 8);
	while (scalar(@bytes) >= $offset) {
		my $max = $offset + $perline - 1;
		$max = $#bytes if $#bytes < $max;
		my @line = @bytes[$offset..$max];
		
		my $key = pack 'C*', @line;
		if (defined $last && $last eq $key) {
			printf "%8s\n", '*' unless $continuing;
			$continuing = 1;
		} else {
			$continuing = 0;
			$last = $key;
			
			my ($text, $line) = ('', '');
			for my $i (0..$#line) {
				$line .= ' ' if $i % 8 == 0;
				my $v = $line[$i];
				$line .= sprintf ' %02x', $v;
				
				my $chr = $v > 31 ? ($v > 127 ? '?' : chr($v)) : '.';
				$text .= $chr;
			}
			printf "%8x%-*s  |%-*s|\n", $offset, $linelen, $line, $perline,
				$text;
		}
		$offset += $perline;
	}
}

sub simpleCrypt {
	my ($key, $data) = @_;
	my $size = length($data);
	
	my @longs = unpack 'L>*', $data;
	my $li = 0;
	for (my $i = int($size/4); $i > 0; $i--) {
		$longs[$li++] ^= $key;
		if ($key >= 0x21524110) { # no overflow
			$key -= 0x21524111;
		} else {
			$key += 0xDEADBEEF;
		}		
		$key ^= 0xDEADBEEF;
	}
	my $ret = pack 'L>*', @longs;
	if ($size % 4) {
		my $end = substr $data, $size - $size % 4;
		my $lend = $end . chr(0) x 4;
		$key ^= unpack 'L>', $lend;
		my @bytes = unpack 'C*', $end;
		my $bi = 0;
		for (my $i = $size % 4; $i > 0; $i--) {
			$bytes[$bi++] = $key >> 24;
			$key &= 0xFFFFFF; # no overflow
			$key <<= 8;
		}
		$ret .= pack 'C*', @bytes;
	}
	return $ret;
}

sub fileType {
	my ($file) = @_;
	return FinderInfo::typeCode($file);
}

sub pilotVers {
	my ($file) = @_;
	my $type = fileType($file);

	my %vers = (
		'MpïL'	=> { game => 'classic',		key => 0xABCD1234 },
		'OpïL'	=> { game => 'override',	key => 0xABCD1234 },
		'NpïL'	=> { game => 'nova',		key => 0xB36A210F },
	);
	$vers{$type}{type} = $type;
	return $vers{$type};
}

sub pilotHex {
	my ($file) = @_;
	my $vers = pilotVers($file);
	
	my ($player, $globals) = readResources($file,
		map { { type => $vers->{type}, id => $_ } } (128, 129));
	
	print $globals->{name}, "\n";
	print "\nPLAYER:\n";
	hexdump(simpleCrypt($vers->{key}, $player->{data}));
	print "\nGLOBALS:\n";
	hexdump(simpleCrypt($vers->{key}, $globals->{data}));
}

sub pilotEdit {
	my ($file, $rsrc, $code) = @_;
	my $vers = pilotVers($file);
	my $spec = { type => $vers->{type}, id => $rsrc };
	my ($res) = readResources($file, $spec);
	$spec->{name} = $res->{name};
	
	my $data = $res->{data};
	$data = simpleCrypt($vers->{key}, $data);
	$data = $code->($data);
	$data = simpleCrypt($vers->{key}, $data);
	
	$spec->{data} = $data;
	writeResources($file, $spec);
}

sub pilotDump {
	my ($file, $rid, $out) = @_;
	my $vers = pilotVers($file);
	
	my ($res) = readResources($file, { type => $vers->{type}, id => $rid });
	my $data = simpleCrypt($vers->{key}, $res->{data});
	
	open my $fh, '>', $out;
	print $fh $data;
	close $fh;
}

sub resForkDump {
	my ($file, $type, $id) = @_;
	$type = decode_utf8($type);
	
	# Hack for pilot files
	if ($type =~ /[MON]piL/) {
		$type =~ tr/i/ï/;
	}
	
	my ($res) = readResources($file, { type => $type, id => $id });
	print $res->{name}, "\n";
	hexdump($res->{data});
}

sub resourceLength {
	my ($r) = @_;
	return length $r->{data};
}

sub skipTo {
	my ($r, $offset) = @_;
	$r->{offset} = $offset;
}

sub readItem {
	my ($r, $len, $fmt) = @_;
	my $offset = $r->{offset} || 0;
	my $d = substr $r->{data}, $offset, $len;
	$offset += $len;
	$r->{offset} = $offset;
	return unpack $fmt, $d;
}

sub readShort {
	readItem(@_, 2, 's>');
}

sub readLong {
	readItem(@_, 4, 'l>');
}

sub readChar {
	readItem(@_, 1, 'C');
}

sub readString {
	my ($r, $len) = @_;
	my @bytes = readItem($len + 1, 'C*');
	my $strlen = shift @bytes;
	return '' if $strlen == 0;
	return join('', @bytes[0..$strlen-1]);
}

sub readDate {
	my ($r) = @_;
	my $year = readShort($r);
	my $month = readShort($r);
	my $day = readShort($r);
	readShort($r) for (1..4);
	return ParseDate(sprintf "%d-%d-%d", $year, $month, $day);
}

sub readSeq {
	my ($r, $sub, $num) = @_;
	return [ map { $sub->($r) } (1..$num) ];
}

sub pilotLimits {
	my ($pilot) = @_; # pilot or vers object
	
	my %l;
	if ($pilot->{game} eq 'nova') {
		%l = (
			cargo		=> 6,
			syst		=> 2048,
			outf		=> 512,
			weap		=> 256,
			misn		=> 10,
			bits		=> 10000,
			escort		=> 74,
			fighter 	=> 54,
			posBits		=> 0xb81e,
			spob		=> 2048,
			skipBeforeDef => 'true',
			pers		=> 1024,
			posCron     => 0x3590,
			cron        => 512,
		);
	} else {
		%l = (
			cargo		=> 6,
			syst		=> 1000,
			outf		=> 128,
			weap		=> 64,
			escort		=> 36,
			fighter 	=> 36,
			posBits		=> 0x1e7e,
			spob		=> 1500,
			pers		=> 512,
		);
		$l{bits} = $pilot->{game} eq 'override' ? 512 : 256;
	}
	$l{posCash} = 2 * (7 + $l{cargo} + 2*$l{syst} + $l{outf} + 2*$l{weap});
	return %l;
}

sub pilotParsePlayer {
	my ($p, $r) = @_;	
	my %limits = pilotLimits($p);
	
	$p->{lastSpob} = readShort($r);
	$p->{ship} = readShort($r);
	$p->{cargo} = readSeq($r, \&readShort, $limits{cargo});
	readShort($r); # unused? val = 300
	$p->{fuel} = readShort($r);
	$p->{month} = readShort($r);
	$p->{day} = readShort($r);
	$p->{year} = readShort($r);
	$p->{explore} = readSeq($r, \&readShort, $limits{syst});
	$p->{outf} = readSeq($r, \&readShort, $limits{outf});
	$p->{legal} = readSeq($r, \&readShort, $limits{syst});
	$p->{weap} = readSeq($r, \&readShort, $limits{weap});
	$p->{ammo} = readSeq($r, \&readShort, $limits{weap});
	$p->{cash} = readLong($r);
	
	if ($p->{game} eq 'nova') {
		for my $i (0..$limits{misn}-1) {
			my %m;
			$m{active} = readChar($r);
			$m{travelDone} = readChar($r);
			$m{shipDone} = readChar($r);
			$m{failed} = readChar($r);
			$m{flags} = readShort($r);
			$m{limit} = readDate($r);
			$p->{misnObjectives}[$i] = \%m if $m{active};
		}
		for my $i (0..$limits{misn}-1) {
			my %m;
			$m{travelSpob} = readShort($r);
			$m{travelSyst} = readShort($r); # unused?
			$m{returnSpob} = readShort($r);
			$m{shipCount} = readShort($r);
			$m{shipDude} = readShort($r);
			$m{shipGoal} = readShort($r);
			$m{shipBehavior} = readShort($r);
			$m{shipStart} = readShort($r);
			$m{shipSyst} = readShort($r);
			$m{cargoType} = readShort($r);
			$m{cargoQty} = readShort($r);
			$m{pickupMode} = readShort($r);
			$m{dropoffMode} = readShort($r);
			
			# TODO
			
			$p->{misnData}[$i] = \%m if exists $p->{misnObjectives}[$i];
		}
	}
	
	# TODO
	skipTo($r, $limits{posBits});
	
	$p->{bit} = readSeq($r, \&readChar, $limits{bits});
	$p->{dominated} = readSeq($r, \&readChar, $limits{spob});
	for my $i (0..$limits{escort}-1) {
		my $v = readShort($r);
		next if $v == -1;
		if ($v >= 1000) {
			push @{$p->{hired}}, $v - 1000;
		} else {
			push @{$p->{captured}}, $v;
		}
	}
	for my $i (0..$limits{fighter}-1) {
		my $v = readShort($r);
		next if $v == -1;
		push @{$p->{fighter}}, $v;
	}
	
	# TODO: ranks? contribute bits? other cargo?
	
	skipTo($r, resourceLength($r) - 4);
	$p->{rating} = readLong($r);
}

sub pilotParseGlobals {
	my ($p, $r) = @_;
	my %limits = pilotLimits($p);
	
	$p->{version} = readShort($r);
	$p->{strict} = readShort($r);
	readShort($r) if $limits{skipBeforeDef}; # unused?
	
	$p->{defense} = readSeq($r, \&readShort, $limits{spob});
	
	$p->{persAlive} = readSeq($r, \&readShort, $limits{pers});
	$p->{persGrudge} = readSeq($r, \&readShort, $limits{pers});
	
	if (exists $limits{posCron}) {
    	skipTo($r, $limits{posCron});
    	$p->{cronDurations} = readSeq($r, \&readShort, $limits{cron});
    	$p->{cronHoldoffs} = readSeq($r, \&readShort, $limits{cron});
	}
}

sub pilotParse {
	my ($file) = @_;
	my $vers = pilotVers($file);
	my ($player, $globals) = readResources($file,
		map { { type => $vers->{type}, id => $_ } } (128, 129));
	map { $_->{data} = simpleCrypt($vers->{key}, $_->{data}) }
		($player, $globals);
	
	my %pilot = (
		name		=> basename($file),
		shipName	=> $globals->{name},
		game		=> $vers->{game},
	);
	pilotParsePlayer(\%pilot, $player);
	pilotParseGlobals(\%pilot, $globals);
	return \%pilot;
}

sub systCanLand {
    my ($syst) = @_;
    for my $spobid (multiProps($syst, 'nav')) {
        my $spob = findRes(spob => $spobid);
        return 1 if $spob->{Flags} & 0x1    # can land here
            && !($spob->{Flags2} & 0x3000); # not a wormhole or hypergate
    }
    return 0;
}

# To be localized
our ($id, $idx, $rez, $val, $name, @lines);

sub pilotPrint {
	my ($p, @wantcats) = @_;
	my $cat = sub {
	    my ($c, @items) = @_;
	    my $nl = ($c =~ s/\s$//);
	    return if @wantcats && !grep { $c =~ /$_/i } @wantcats;
	    
	    my $sub = $items[0];
	    local @lines = ();
	    @items = $sub->() if ref($sub) =~ /^CODE/;
	    
	    if ($nl) {
	        printf "%s:\n", $c;
	        printf "  %s\n", $_ foreach @items, @lines;
	    } else {
	        printf "%s: %s\n", $c, $items[0];
	    }
	};
	my $catfor = sub {
	    my ($c, $key, $type, $sub) = @_;
	    $cat->("$c ", sub {
    	    my $resources = resource($type);
    	    for $id (sort keys %$resources) {
    	        local ($idx, $rez) = ($id - 128, $resources->{$id});
    	        local ($val, $name) = ($p->{$key}[$idx], resName($rez));
    	        my $line = $sub->();
    	        push @lines, $line if $line;
    	    } ();
	    });
	};
	
	# GAME
	$cat->('Game', $p->{game});
	$cat->('Version', $p->{version});
	
	# PLAYER
	$cat->('Name', $p->{name});
	$cat->('Ship name', $p->{shipName});
	$cat->('Strict', $p->{strict} ? 'true' : 'false');
	$cat->('Game date', sub {
	    my $date = ParseDate(sprintf "%d-%d-%d", @$p{qw(year month day)});
	    UnixDate($date, "%b %E, %Y");
	});
    $cat->('Rating', ratingStr($p->{rating}));
    $cat->('Cash', commaNum($p->{cash}));
	$cat->('Last landed', sub {
	    my $s = findRes(spob => $p->{lastSpob} + 128);
	    sprintf "%d - %s", $s->{ID}, resName($s);
	});
	
	# SHIP
	$cat->('Ship', findRes(ship => $p->{ship} + 128)->{Name});
    $cat->('Fuel', sprintf("%.2f", $p->{fuel} / 100));
	$cat->('Cargo ', map {
    	my $qty = $p->{cargo}[$_];
    	$qty ? sprintf("%s: %d", cargoName($_), $qty) : ();
    } (0..$#{$p->{cargo}}));
	$catfor->(qw(Outfits outf outf), sub {
	    !$val ? 0 : sprintf "%s: %d", $name, $val;
	});
	$catfor->(qw(Weapons weap weap), sub {
	    my $ammo = $p->{ammo}[$idx];
	    !$val ? 0 : sprintf "%s: %d (ammo: %d)", $name, $val, $ammo;
	});
	$cat->('Escorts ', sub {
	    for my $type (qw(captured hired fighter)) {
	        my $escs = $p->{$type} or next;
	        push @lines, sprintf "%d - %s: %s", $_ + 128,
	            findRes(ship => $_ + 128)->{Name}, $type
	            foreach @$escs;
	    } ();
	});
	
	# GALAXY
	$catfor->(qw(Unexplored explore syst), sub {
	    return 0 if $val == 2;
		my $details = $val == 1 ? ' (not landed)' : '';
		
		return 0 unless bitTestEvalPilot($rez->{Visibility}, $p);
		return 0 if $val == 1 && !systCanLand($rez);
		sprintf "%d - %s%s", $id, $name, $details;
	});
	$cat->('Records ', sub {
	    my ($systs, %gov) = resource('syst');
	    for my $s (values %$systs) {
	        my $g = $s->{Govt};
	        push @{$gov{$g}}, { syst => $s,
	            legal => $p->{legal}[$s->{ID} - 128],
	        };
	    }
	    for my $g (sort keys %gov) {
	        my @ss = sort { $a->{legal} <=> $b->{legal} } @{$gov{$g}};
	        push @lines, sprintf("%d - %s", $g, govtName(findRes(govt => $g))),
                sprintf("  Min: %5d (%s)", $ss[0]{legal}, $ss[0]{syst}{Name}),
                sprintf("  Max: %5d (%s)", $ss[-1]{legal}, $ss[-1]{syst}{Name});
	    } ();
	});
	$catfor->(qw(Dominated dominated spob), sub {
	    sprintf "%d - %s", $id, $name if $val;
	});
	$catfor->('Defense fleets', 'defense', 'spob', sub {
	    return 0 if $p->{dominated}[$idx] || $val == 0 || $val == -1;
	    my $cnt = $rez->{DefCount};
	    return 0 if $cnt == 0 || $cnt == -1;
	    $cnt = int(($cnt - 1000) / 10) if $cnt > 1000;
	    return 0 if $cnt == $val;
	    sprintf "%d - %s: %4d / %4d", $id, $name, $val, $cnt;
	});
	
	# GAME GLOBALS
	$cat->('Bits ', sub {
	    my @bits = map { $p->{bit}[$_] ? sprintf("%4d", $_) : (' ' x 4) }
	        (0..$#{$p->{bit}});
	    while (my @line = splice(@bits, 0, 10)) {
	        push @lines, join '  ', @line if grep /\S/, @line;
	    } ();
	});
	$catfor->(qw(Crons cronDurations cron), sub {
	    my $hold = $p->{cronHoldoffs}[$idx];
	    return 0 if $val == -1 && $hold == -1;
		sprintf "%d - %-40s: duration = %4d, holdoff = %4d",
		    $id, $name, $val, $hold;
	}) if exists $p->{cronDurations};
	$catfor->(qw(Persons persAlive pers), sub {
	    my $grudge = $p->{persGrudge}[$idx];
	    return 0 if $val && !$grudge;
		sprintf "%d - %s: %s", $id, $name, ($val ? 'grudge' : 'killed');
	});
}

sub pilotShow {
	my ($file) = shift;
	my $pilot = pilotParse($file);
	pilotPrint($pilot, @_);
}

sub descName {
	my ($d) = @_;
	my $id = $d->{ID};
	my ($type, $res);
	
	if ($id >= 128 && $id <= 2175) {
		($type, $res) = ('spob', 'spob');
	} elsif ($id >= 3000 && $id <= 3511) {
		($type, $res, $id) = ('outf', 'outf', $id - 3000 + 128);
	} elsif ($id >= 4000 && $id <= 4999) {
		($type, $res, $id) = ('misn', 'misn', $id - 4000 + 128);
	} elsif ($id >= 13000 && $id <= 13767) {
		($type, $res, $id) = ('ship buy', 'ship', $id - 13000 + 128);
	} elsif ($id >= 14000 && $id <= 14767) {
		($type, $res, $id) = ('ship hire', 'ship', $id - 14000 + 128);
	}
	
	if (defined $type) {
		my $r = findRes($res => $id);
		return sprintf "%d: %s %d - %s", $d->{ID}, $type, $id, resName($r);
	} else {
		return sprintf "%d: %s", $d->{ID}, resName($d);
	}
}

sub grepDescs {
	my ($re) = @_;
	$re = qr/$re/i;
	
	my $descs = resource('desc');
	for my $id (sort keys %$descs) {
		my $d = $descs->{$id};
		my $str = sprintf "%s\n%s\n", descName($d), $d->{Description};
		if ($str =~ /$re/) {
			print "$str\n";
		}
	}
}

sub legalFromPilot {
	my ($file, @finds) = @_;
	my $pilot = pilotParse($file);
	for my $find (@finds) {
		my $syst = findRes(syst => $find);
		my $legal = $pilot->{legal}[$syst->{ID} - 128];
		printf "%-10s: %4d\n", $syst->{Name}, $legal;
	}
}

sub killable {
	my $perss = resource('pers');
	for my $id (sort keys %$perss) {
		my $p = $perss->{$id};
		next if $p->{Flags} & 0x2;
		printf "%4d: %s\n", $id, $p->{Name};
	}
}

sub dudeStrength {
	my ($dude) = @_;
	memoize ($dude->{ID}, sub {
		my $strength = 0;
		for my $kt (grep /^ShipTypes\d+/, keys %$dude) {
			(my $kp = $kt) =~ s/ShipTypes(\d+)/Probs$1/;
			my ($vt, $vp) = map { $dude->{$_} } ($kt, $kp);
			next if $vt == -1;
			
			my $ship = findRes(ship => $vt);
			$strength += ($vp / 100) * $ship->{Strength};
		}
		return $strength;
	});
}	

sub dominate {
    my $pilot;
    moreOpts(\@_, 'pilot|p=s' => sub { $pilot = pilotParse($_[1]) });
	
	my (@finds) = @_;
	my @spobs = @finds ? map { findRes(spob => $_) } @finds
		: values %{resource('spob')};
	
	my %defense;
	for my $spob (@spobs) {
		next if $spob->{Flags} & 0x20 || !($spob->{Flags} & 0x1);
		next if $spob->{DefDude} == -1;
		
		my $wave;
		my $count = $spob->{DefCount};
		$count = $pilot->{defense}[$spob->{ID} - 128]
		    if defined $pilot;
		if ($count <= 1000) {
			$wave = $count;
		} else {
			$wave = $count % 10;
			$count -= 1000;
			$count = int($count / 10);
		}
		
		my $dude = findRes(dude => $spob->{DefDude});
		my $strength = $count * dudeStrength($dude);
		
		my $def = {
			spob		=> $spob,
			count		=> $count,
			wave		=> $wave,
			dude		=> $dude,
			strength	=> $strength,
		};
		push @{$defense{$strength}}, $def;
	}
	
	for my $strength (sort { $b <=> $a } keys %defense) {
		printf "Strength: %10s\n", commaNum($strength);
		my @subs = sort { $a->{spob}{ID} <=> $b->{spob}{ID} }
			@{$defense{$strength}};
		for my $sub (@subs) {
			my $desc;
			my $dudestr = sprintf "%s (%d)", @{$sub->{dude}}{'Name', 'ID'};
			my $spobstr = sprintf "%d %s", @{$sub->{spob}}{'ID', 'Name'};
			if ($sub->{count} == $sub->{wave}) {
				$desc = sprintf "%4d - %s", $sub->{count}, $dudestr;
			} else {
				$desc = sprintf "%4d - %d x %s", $sub->{count}, $sub->{wave},
					$dudestr;
			}
			printf "  %-20s (%2dK): %s\n", $spobstr,
				$sub->{spob}{Tribute} / 1000, $desc;
		}
		print "\n";
	}
}

sub wherePers {
	my ($pilotFile, $find) = @_;
	my $pilot = pilotParse($pilotFile);
	
	my %systsPers;
	for my $p (values %{resource('pers')}) {
		next unless $pilot->{persAlive}[$p->{ID} - 128];
		my @systs = systsMatching($p->{LinkSyst});
		push @{$systsPers{$_}}, $p for @systs;
	}
	
	my $pers = findRes(pers => $find);
	my @systs = systsMatching($pers->{LinkSyst});
	my %pcts;
	for my $s (@systs) {
		my $count = scalar(@{$systsPers{$s}});
		my $frac = 1 / $count;
		$frac /= 20;
		
		my $syst = findRes(syst => $s);
		$frac = 1 - ((1-$frac) ** $syst->{AvgShips});
		$pcts{$s} = $frac * 100;
	}
	
	my $count = 0;
	printf "Systems with %s (%d):\n", resName($pers), $pers->{ID};
	for my $sid (sort { $pcts{$b} <=> $pcts{$a} } @systs) {
		my $syst = findRes(syst => $sid);
		printf "%5.3f %% - %4d: %s\n", $pcts{$sid}, $sid, $syst->{Name};
		last if $count++ >= 20;
	}
}

sub legalGovt {
	my ($pilotFile, $find, $count) = @_;
	my $govt = findRes(govt => $find) if defined $find;
	my $pilot = pilotParse($pilotFile);
	my $systs = resource('syst');
	
	my %legal;
	for my $s (values %$systs) {
		next if defined $govt && $s->{Govt} != $govt->{ID};
		next unless bitTestEvalPilot($s->{Visibility}, $pilot);
		$legal{$s->{ID}} = $pilot->{legal}[$s->{ID} - 128];
	}
	
	my @sorted = sort { $legal{$b} <=> $legal{$a} } keys %legal;
	$count = 8 unless $count;
	for my $idx (0..$#sorted) {
		next unless $idx < $count || $#sorted - $idx < $count;
		my $sid = $sorted[$idx];
		printf "%5d: %s (%d)\n", $legal{$sid}, $systs->{$sid}{Name}, $sid;
		print "-----\n" if $idx == $count - 1 && $idx <= $#sorted - $count;
	}
}

sub multiProps {
	my ($obj, $prefix, $ignore) = @_;
	$ignore = -1 unless defined $ignore;
	
	my @keys = grep /^$prefix\d*$/, keys %$obj;
	my @vals = @$obj{@keys};
	@vals = grep { $_ ne $ignore} @vals;
	return @vals;
}

sub multiPropsHash {
	my ($obj, $prefix, $valpref, $ignore) = @_;
	$ignore = -1 unless defined $ignore;
	
	my %ret;
	for my $kk (sort keys %$obj) {
		(my $vk = $kk) =~ s/^$prefix(\d*)$/$valpref$1/ or next;		
		next if $obj->{$kk} eq $ignore;
		push @{$ret{$obj->{$kk}}}, $obj->{$vk};
	}
	return %ret;
}

sub hiddenSpobs {
	for my $syst (values %{resource('syst')}) {
		my %spobs;
		my @spobids = multiProps($syst, 'nav');
		for my $spobid (@spobids) {
			my $spob = findRes(spob => $spobid);
			my ($x, $y) = @$spob{'xPos', 'yPos'};
			push @{$spobs{$x,$y}}, $spob;
		}
		for my $loc (keys %spobs) {
			my @spobs = @{$spobs{$loc}};
			next unless scalar(@spobs) > 1;
			printf "%4d: %s\n", $syst->{ID}, $syst->{Name};
			printf "      %4d: %s\n", $_->{ID}, $_->{Name} for @spobs;
		}
	}
}

sub getConText {
	return File::Spec->rel2abs($conTextOpt) if defined $conTextOpt;
	my $file = File::Spec->catfile($globalCache, '.context');
	die "No context set!\n" unless -f $file;
	
	open my $fh, '<', $file;
	my $context = <$fh>;
	chomp $context;
	close $fh;
	return $context;
}

sub setConText {
	my ($context) = @_;
	$context = File::Spec->rel2abs($context);
	mkdir_p $globalCache;
	my $file = File::Spec->catfile($globalCache, '.context');
	open my $fh, '>', $file;
	print $fh $context;
	close $fh;
}

sub contextCache {
	my $context = getConText();
	$context =~ s,/,_,g;
	return File::Spec->catdir($globalCache, $context);
}	

sub printConText {
	my $context = getConText();
	print "$context\n";
}

sub revivePers {
	my ($file, @find) = @_;
	my @pers = map { findRes(pers => $_) } @find;
	my $vers = pilotVers($file);
	my %limits = pilotLimits($vers);
	my $posPers = $limits{posPers};
	
	pilotEdit($file, 129, sub {
		my ($data) = @_;
		print "Reviving:\n";
		for my $p (@pers) {
			printf "  %4d - %s\n", $p->{ID}, $p->{Name};
			my $pos = $posPers + 2 * ($p->{ID} - 128);
			substr($data, $pos, 2) = pack('s>', 1);
		}
		return $data;
	});
}

sub setCash {
	my ($file, $cash) = @_;
	my $vers = pilotVers($file);
	my %limits = pilotLimits($vers);
	
	pilotEdit($file, 128, sub {
		my ($data) = @_;
		substr($data, $limits{posCash}, 4) = pack('L>', $cash);
		return $data;
	});
}

sub setBits {
	my ($file, @specs) = @_;
	@specs = split ' ', join ' ', @specs;
	
	my $vers = pilotVers($file);
	my %limits = pilotLimits($vers);
	my $posBits = $limits{posBits};
	
	pilotEdit($file, 128, sub {
		my ($data) = @_;
		print "Changing bits:\n";
		for my $spec (@specs) {
			my $bit;
			my $set = 1;
			
			$spec =~ /(\d+)/ or next;
			$bit = $1;
			
			$set = 0 if $spec =~ /!/;
			
			printf "  %4d - %s\n", $bit, $set ? "set" : "clear";
			my $pos = $posBits + $bit;
			substr($data, $pos, 1) = pack('C', $set);
		}
		return $data;
	});
}

sub availMisns {
	my ($verbose, $interesting);
	moreOpts(\@_, 'verbose|v+' => \$verbose,
	    'interesting|i' => \$interesting);
	my ($pfile, $progress) = @_;
	
	# Read the progress
	my %completed;
	if (defined $progress) {
    	open my $fh, '<', $progress or die $!;
    	while (<$fh>) {
    		if (/^\s*[^\s\d]\s*(\d+)/) {
    			$completed{$1} = 1;
    		}
    	}
    }
	
	# Read the pilot
	my $pilot = pilotParse($pfile);
	
	# Find ok missions
	my (@ok, %bits);
	my $misns = resource('misn');
	for my $misn (values %$misns) {
		next if $completed{$misn->{ID}};
		next unless $misn->{AvailRandom} > 0;
		next unless bitTestEvalPilot($misn->{AvailBits}, $pilot);
		push @ok, $misn;
		push @{$bits{$misn->{AvailBits}}}, $misn;
	}
	
	if ($interesting) {
	    @ok = ();
	    for my $ms (values %bits) {
	        next unless @$ms <= 3;
	        push @ok, @$ms;
	    }
	}
	
	# Print
    @ok = sort { $a->{ID} <=> $b->{ID} } @ok;
	if ($verbose) {
		printMisns($verbose > 1, @ok);
	} else {
		for my $misn (@ok) {
			printf "%4d: %s\n", $misn->{ID}, $misn->{Name};
		}
	}
}

sub closestTech {
	my ($curSyst, @techs) = @_;	
	$curSyst = findRes(syst => $curSyst);
	
	my %dists;
	SPOB: for my $spob (values %{resource('spob')}) {
		my $syst = eval { spobSyst($spob->{ID}) };
		next if $@;
		
		my $dist = systDist($curSyst->{ID}, $syst->{ID});
		my @special = multiProps($spob, 'SpecialTech');
		
		for my $tech (@techs) {
			next SPOB unless $spob->{TechLevel} >= $tech
				|| grep { $_ == $tech } @special;
		}
		push @{$dists{$dist}}, sprintf "%s in %s",
			$spob->{Name}, $syst->{Name}; 
	}
	
	my $count = 20;
	my @dists = sort { $a <=> $b } keys %dists;
	for my $dist (@dists) {
		last if $count <= 0;		
		my @spobs = sort @{$dists{$dist}};
		$count -= scalar(@spobs);
		
		for my $idx (0..$#spobs) {
			my $pre = $idx ? ' ' x 5 : sprintf "%4d:", $dist;
			print "$pre $spobs[$idx]\n";
		}
	}
}

my %cmds = (
	misc		=> \&misc,
	masstable	=> \&massTable,
	mass		=> \&showShipMass,
	mymass		=> \&myMass,
	'dump'		=> \&resDump,
	list		=> \&list,
	rank		=> \&rank,
	misn		=> \&misn,
	crons		=> \&crons,
	rsrc		=> \&rsrc,
	bit			=> \&bit,
	comm		=> \&commodities,
	defense		=> \&defense,
	persistent	=> \&persistent,
	pers		=> \&pers,
	limit		=> \&limit,
	dist		=> \&dist,
	spobtech	=> \&spobtech,
	outftech	=> \&outftech,
	rating		=> \&rating,
	dude		=> \&dude,
	records		=> \&records,
	suckup		=> \&suckUp,
	capture		=> \&capture,
	where		=> \&where,
	trade		=> \&trade,
	legs		=> \&printLegs,
	bitTest		=> \&bitTestPrint,
	spobsyst	=> \&printSpobSyst,
	cantsell	=> \&cantSell,
	diff		=> \&diff,
	find		=> \&find,
	resdump		=> \&resForkDump,
	pilotdump	=> \&pilotDump,
	pilothex	=> \&pilotHex,
	pilot		=> \&pilotShow,
	'map'		=> \&mapOver,
	shiptech	=> \&shiptech,
	'grep'		=> \&grepDescs,
	legal		=> \&legalFromPilot,
	legalgovt	=> \&legalGovt,
	killable	=> \&killable,
	dominate	=> \&dominate,
	wherepers	=> \&wherePers,
	hiddenspobs	=> \&hiddenSpobs,
	getcontext	=> \&printConText,	
	setcontext	=> \&setConText,
	revive		=> \&revivePers,
	cash		=> \&setCash,
	avail		=> \&availMisns,
	setbits		=> \&setBits,
	closetech	=> \&closestTech,
);

sub misc {
	my ($file) = @_;
	my $vers = pilotVers($file);
	my ($res) = readResources($file, { type => $vers->{type}, id => 129 });
	my $data = simpleCrypt($vers->{key}, $res->{data});
	my $spobid = 502;
	my $defPos = 4;
	my $pos = $defPos + 2 * ($spobid - 128);
	my $str = substr $data, $pos, 2;
	my $count = unpack 's>', $str;
	printf "Remaining: %3d\n", $count;
}

Getopt::Long::Configure(qw(pass_through bundling));
GetOptions(
	'context|c=s'	=> \$conTextOpt,
);

my $cmd = lc shift;
die "No such command \"$cmd\"\n" unless exists $cmds{$cmd};
&{$cmds{$cmd}}(@ARGV);


__DATA__
