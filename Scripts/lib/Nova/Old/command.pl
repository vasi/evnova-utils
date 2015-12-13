use warnings;
use strict;

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
		printf "%3d%% - %s (%d)\n", $ships{$s}, resName($ships->{$s}),
			$ships->{$s}{Strength};
	}
	printf "\nStrength: %.2f\n", scalar(dudeStrength($dude));
}

1;
