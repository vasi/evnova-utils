use warnings;
use strict;

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
	print_breaking($out, 1, '', '         ');
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

1;
