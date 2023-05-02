use warnings;
use strict;

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

# (ID of cargo type => price) at a spob (below 128 = commodities)
sub cargo {
	my ($spob) = @_;

	# Junks
	my $cargo = spobJunks($spob);
	for my $k (keys %$cargo) {
		$cargo->{$k} = $cargo->{$k} eq 'Bought' ? cargoPrice($k, 'High') : cargoPrice($k, 'Low');
	}

	# Commodities
	my $flags = $spob->{Flags};
	my %levels = (1 => 'Low', 2 => 'Med', 4 => 'High');
	my @status;
	for my $i (0..5) {
		my $shift = (8 - $i - 1) * 4;
		my $status = ($flags & (0xF << $shift)) >> $shift;
		$cargo->{$i} = cargoPrice($i, $levels{$status}) if $status != 0;
	}

	return $cargo;
}

sub legForSpobPair {
	my ($srcCargo, $dstCargo) = @_;

	for my $cargo (keys %$srcCargo) {
		next unless exists $dstCargo->{$cargo};
		my $diff = $dstCargo->{$cargo} - $srcCargo->{$cargo};
		next if $diff <= 0;

		return {cargo => $cargo, profit => $diff};
	}

	# empty leg
	return {cargo => -1, profit => 0};
}

sub routeForSpobPair {
	my ($spob1, $spob2, $cargo1, $cargo2) = @_;
	my $leg1 = legForSpobPair($cargo1, $cargo2);
	my $leg2 = legForSpobPair($cargo2, $cargo1);
	my $profit = $leg1->{profit} + $leg2->{profit};
	my $dist = spobDist($spob1->{ID}, $spob2->{ID});
	my $score = $profit / (1 * $dist + 1) / 2;
	return {
		spob1 => $spob1,
		cargo1 => $leg1->{cargo},
		spob2 => $spob2,
		cargo2 => $leg2->{cargo},
		dist => $dist,
		profit => $profit,
		score => $score,
	}
}

sub tradeString {
	my ($spob, $cargo) = @_;
	my $c = $cargo == -1 ? 'empty' : sprintf "buy %s", cargoName($cargo);
	sprintf "%-18s   %-18s", $spob->{Name}, $c;
}

sub trade {
	my $spobs = resource('spob');

	# Only keep spobs that are present at start of game
	my @spobids = grep {
		my $syst = eval { spobSyst($_) };
		($spobs->{$_}{Flags} & 0x2) && !$@
			&& initiallyTrue($syst->{Visibility});
	} sort keys %$spobs;

	my %cargos = map { $_ => cargo($spobs->{$_}) } @spobids;

	my @routes;
	for my $i (0..($#spobids - 1)) {
		my $iid = $spobids[$i];
		for my $j (($i+1)..$#spobids) {
			my $jid = $spobids[$j];
			my $route = routeForSpobPair($spobs->{$iid}, $spobs->{$jid},
				$cargos{$iid}, $cargos{$jid});
			push @routes, $route if $route->{score} > 0;
		}
	}

	@routes = sort { $b->{score} <=> $a->{score} } @routes;
	for (my $i = 0; $i < 30 && $i <= $#routes; $i++) {
		my $route = $routes[$i];
		my $out = sprintf "%7.2f: %s   %s", $route->{score},
			tradeString($route->{spob1}, $route->{cargo2}),
			tradeString($route->{spob2}, $route->{cargo1});
		print_breaking($out, 1, '', '         ');
	}
}

1;
