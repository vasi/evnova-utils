use warnings;
use strict;

our $pilotLog = 'pilotlog.txt';

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
		my @lines = split /[\r\n]/, $txt;
		@lines = grep /\S/, @lines; # remove whitespace lines
		#@lines = grep !/Plugins loaded/, @lines; # breaks format

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

1;
