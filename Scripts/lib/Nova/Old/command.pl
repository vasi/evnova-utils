use warnings;
use strict;

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
		printf "%3d%% - %s (ID: %d, strength: %d)\n", $ships{$s}, resName($ships->{$s}),
			$s, $ships->{$s}{Strength};
	}
	printf "\nStrength: %.2f\n", scalar(dudeStrength($dude));
}

1;
