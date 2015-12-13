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

sub junkSpobs {
	my ($junk) = @_;
	return map {
		[ map { findRes(spob => $_) }
			grep { $_ > 0 } multiProps($junk, $_ . 'At') ]
	} ('Bought', 'Sold');
}

sub junkSpobNames {
	my ($spobs) = @_;
	my (%seen, @names);
	for my $name (map { resName($_) } @$spobs) {
		push @names, $name unless $seen{$name}++;
	}
	return join ', ', @names;
}

sub junkRoute {
	my ($bought, $sold) = @_;
	return unless @$bought && @$sold;

	my %spobs = map { spobSyst($_->{ID})->{ID} => $_ } @$bought, @$sold;
	my %systs = reverse %spobs;
	my @route = eval {
		systSetDist([ @systs{@$sold} ], [ @systs{@$bought} ]);
	};
	return if $@;
	return (dist => scalar(@route), start => $spobs{$route[0]},
		end => $spobs{$route[-1]});
}

sub listJunk {
	my (@specs) = @_;
	my @junks = findRes(junk => \@specs);

	my @all;
	for my $junk (@junks) {
		my $text;
		my ($bought, $sold) = junkSpobs($junk);
		my %route = junkRoute($bought, $sold);

		$text .= sprintf "Name: %s\n", resName($junk);
		$text .= sprintf "Buy:  %4d\n", cargoPrice($junk->{ID}, 'Low');
		$text .= sprintf "Sell: %4d\n", cargoPrice($junk->{ID}, 'High');
		$text .= sprintf "BuyAt: %s\n", junkSpobNames($sold);
		$text .= sprintf "SellAt: %s\n", junkSpobNames($bought);
		if (%route) {
			my $printRoute = '';
			if (scalar(@$bought) > 1 || scalar(@$sold) > 1) {
				# Only show the start/end if it's helpful
				$printRoute = sprintf " (%s -> %s)",
					resName($route{start}), resName($route{end});
			}
			$text .= sprintf "Trade: %d jumps%s\n", $route{dist}, $printRoute;
		}

		push @all, $text;
	}

	print_breaking(join "\n", @all);
}

1;
