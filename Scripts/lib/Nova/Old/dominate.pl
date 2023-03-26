use warnings;
use strict;

sub dudeStrength {
	my ($dude) = @_;
	memoize ($dude->{ID}, sub {
		my $strength = 0;
		for my $kt (grep /^ShipTypes\d+/, keys %$dude) {
			(my $kp = $kt) =~ s/ShipTypes(\d+)/Probs$1/;
			my ($vt, $vp) = map { $dude->{$_} } ($kt, $kp);
			next if $vt == -1;

			my $ship = findRes(ship => $vt);
			$strength += ($vp / 100) * betterStrength($ship);
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
		if (defined $pilot) {
		    my $syst = spobSyst($spob->{ID});
            next unless bitTestEvalPilot($syst->{Visibility}, $pilot);
            next if $pilot->{dominated}->[$spob->{ID} - 128];
		}

		my $wave;
		my $count = $spob->{DefCount};
		if ($count <= 1000) {
			$wave = $count;
		} else {
			$wave = $count % 10;
			$count = int($count / 10);
            $count -= 10 ** int(log($count) / log(10));
		}
		$count = $pilot->{defense}[$spob->{ID} - 128]
		    if defined $pilot;

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
		for my $sub (sort { $b->{spob}{Tribute} <=> $a->{spob}{Tribute} } @subs) {
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

1;
