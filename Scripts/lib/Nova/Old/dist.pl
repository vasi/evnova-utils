use warnings;
use strict;

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
				my $dist = systDist($s1, $s2);
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

sub systDist {
	return memoize(@_, sub {
		my ($memo, $s1, $s2) = @_;
		my %seen = djikstra(edgesSyst(), $s1, end => $s2);
		while (my ($sid, $r) = each %seen) {
			$memo->($s1, $sid, $r->{dist});
			$memo->($sid, $s1, $r->{dist});
		}
		return $seen{$s2}{dist};
	});
}

sub spobDist {
	return memoize(@_, sub {
		my ($memo, $s1, $s2) = @_;
		return systDist(spobSyst($s1)->{ID}, spobSyst($s2)->{ID});
	});
}

sub systSetDist {
	my ($src, $dest) = @_;
	my $best;
    my @bestEnds = ();

    for my $s1 (@$src) {
        for my $s2 (@$dest) {
            my $dist = systDist($s1, $s2);
			if (!defined($best) || $best > $dist) {
				@bestEnds = ($s1, $s2);
				$best = $dist;
			}
        }
    }

	return djikstraPath(edgesSyst(), @bestEnds);
}

sub showPlaceDist {
    my $ref = { syst => resource('syst') };
	my @s1 = systsSelect($ref, placeSpec(\@_));
	my @s2 = systsSelect($ref, placeSpec(\@_));
	printPath(systSetDist(\@s1, \@s2));
}

sub printPath {
    my @path = @_;
    my $systs = resource('syst');

	printf "Distance: %d\n", scalar(@path) - 1;
	for (my $i = 0; $i <= $#path; ++$i) {
		printf "%2d: %s\n", $i, $systs->{$path[$i]}{Name};
	}
}

sub showDist {
    my ($landingPenalty, $jumps) = (2, undef);
	moreOpts(\@_, 'jumps|j=s' => \$jumps, 'land|l=s' => \$landingPenalty);
	my ($src, $dst) = @_;
	$src = findRes(syst => $src);
	$dst = findRes(syst => $dst);

	my $edge = $jumps ? edgesSegment($jumps, $landingPenalty) : edgesSyst();
	my @path = djikstraPath($edge, $src->{ID}, $dst->{ID});
	printPath(@path);
}

sub limitMisns {
	my $misns = resource('misn');

	my $ref;
	my $cache = File::Spec->catfile(contextCache(), 'dist');
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

1;
