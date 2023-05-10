use warnings;
use strict;

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

sub itemOutfit {
	my ($w2o, $outfs, $item) = @_;
	my ($type, $id) = @$item{'type', 'id'};

	return $outfs->{$id} if $type eq 'outfit';

	if ($type eq 'ammo') {
		die "No source found for weapon ID $id\n"
			unless exists $w2o->{$id}{source};
		my $source = $w2o->{$id}{source};
		return undef if $source == 0;
		die "No ammo found for weapon ID $source\n"
			unless exists $w2o->{$source}{ammo};
		return $w2o->{$source}{ammo}[0];
	} elsif ($type eq 'weapon') {
		die "No outfit found for weapon ID $id\n"
			unless exists $w2o->{$id}{weapon};
		return $w2o->{$id}{weapon}[0];
	}
	return undef;
}

sub itemMass {
	my ($w2o, $outfs, $item, %opts) = @_;
	my $outf = eval {
		itemOutfit($w2o, $outfs, $item);
	};
	warn $@ if $@;
	return 0 unless $outf;
	return 0 if $opts{removable} && ($outf->{Flags} & 0x8);
	return $outf->{Mass};
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
			$i->{mass} = itemMass($w2o, $outfs, $i, %opts);
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

		my %typeOrder = (weapon => 1, ammo => 1, outfit => 2);
		my %subOrder = (weapon => 1, ammo => 2, outfit => 2);
		$items = [sort {
			$typeOrder{$a->{type}} <=> $typeOrder{$b->{type}} or
			$a->{id} <=> $b->{id} or
			$subOrder{$a->{type}} <=> $subOrder{$b->{type}}
		} @$items];

	printf "  %3d              - free\n", $free;
	for my $i (@$items) {
		my $outf = eval { itemOutfit($w2o, $outfs, $i) };
		my $nonremovable = $outf && ($outf->{Flags} & 0x8);
		my $remc = $nonremovable ? '*' : '-';

	    my $rtype = $i->{type} eq 'outfit' ? $outfs : $weaps;
	    my $rez = $rtype->{$i->{id}};
	    printf "  %3d = %4d x %3d %s %-6s %4d: %s\n", $i->{mass} * $i->{count},
	        $i->{count}, $i->{mass}, $remc, $i->{type}, $i->{id}, resName($rez)
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

sub massTable {
	my ($tsv, $removable, $buyable) = (0, 0);
	moreOpts(\@_, 'tsv|t+' => \$tsv, 'removable|r+' => \$removable, 'buyable' => \$buyable);

	my $cache = {};
    my $ships = resource('ship');
    my @ships = values %$ships;
	for my $ship (@ships) {
		$ship->{TotalMass} = shipTotalMass($ship, cache => $cache,
            removable => $removable);
	}

	@ships = sort { $b->{TotalMass} <=> $a->{TotalMass} } @ships;
	print tsv(qw(ID Name SubTitle TotalMass)) if $tsv;
	for my $ship (@ships) {
		next if $buyable && int($ship->{BuyRandom}) == 0;
		if ($tsv) {
			print tsv(@$ship{qw(ID Name SubTitle TotalMass)});
		} else {
			printf "%4d  %s (%d)\n", $ship->{TotalMass}, resName($ship),
				$ship->{ID};
		}
	}
}

1;
