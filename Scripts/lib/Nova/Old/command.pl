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

sub dudes {
	my ($systSpec) = @_;
	my ($syst) = findRes(syst => $systSpec);

	my %dudes = multiPropsHash($syst, 'DudeTypes', 'Probs', 0);
	my @objs = 
		sort { $b->{prob} <=> $a->{prob} or $a->{id} cmp $b->{id} }
		map { {id => $_, prob => $dudes{$_}->[0] } }
		keys %dudes;
	foreach my $o (@objs) {
		my $dude = findRes(dude => $o->{id});
		my $govt = findRes(govt => $dude->{Govt});
		printf "%3d%%: %s (%d), govt: %s\n", $o->{prob}, resName($dude), $o->{id},
			resName($govt);
	}
}

1;
