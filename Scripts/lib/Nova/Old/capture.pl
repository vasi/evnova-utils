use warnings;
use strict;

# Get capture-relevant info from a 'pilot' or 'log'
sub capturePilotInfo {
	my ($type, $file) = @_;
	my ($ship, %outfits, @escorts);

	if ($type eq 'log') {
		my $log = readPilotLog($file);
		$ship = logShip($log);
		@escorts = logEscorts($log);
		%outfits = logOutfits($log);
	} else {
		my $pilot = pilotParse($file);
		$ship = $pilot->{ship} + 128;
		@escorts = map { $_ + 128 } @{$pilot->{hired}}, @{$pilot->{captured}};
		for my $i (0..$#{$pilot->{outf}}) {
			$outfits{$i + 128} = $pilot->{outf}[$i] if $pilot->{outf}[$i];
		}
	}

	return { ship => $ship, outfits => \%outfits, escorts => \@escorts };
}

# Calculate effective crew, capture percentage bonus, and ship strength
sub captureCoefficients {
	my ($info) = @_;

	my $ships = resource('ship');
	my $outfs = resource('outf');

	my $ship = $ships->{$info->{ship}};
	my ($crew, $strength, $bonus) = ($ship->{Crew}, $ship->{Strength}, 0);

	# Add escorts
	for my $eid (@{$info->{escorts}}) {
		my $escort = $ships->{$eid};
		# next unless $escort->{EscortType} == 2; # Must be warship
		$crew += $escort->{Crew} / 10.0;
		$strength += $escort->{Strength} / 10.0;
	}

	# Add outfits
	while (my ($oid, $count) = each %{$info->{outfits}}) {
		my $outf = $outfs->{$oid};
		my %mods = multiPropsHash($outf, 'ModType', 'ModVal');
		foreach my $val (@{$mods{25}}) {
			if ($val < 0) {
				$bonus -= $val;
			} else {
				$crew += $val;
			}
		}
	}

	return { crew => $crew, strength => $strength, bonus => $bonus };
}

sub captureOdds {
	my ($coeff, $enemy) = @_;

	my $odds = $coeff->{crew} / $enemy->{Crew} * 10;
	if ($coeff->{strength} > 5 * $enemy->{Strength}) {
		$odds += 10;
	}
	$odds += $coeff->{bonus};

	my ($min, $max) = ($odds - 5, $odds + 5);
	my $trunc = 0; # How much of the avg comes from truncated areas?
	for my $o ($min, $max) {
		if ($o > 75) {
			$trunc += ($o - 75) * 75;
			$o = 75;
		}
		if ($o < 1) {
			$trunc += (1 - $o) * 1;
			$o = 1;
		}
	}

	my $avg = ($max - $min) * ($max + $min) / 2;
	$avg = ($avg + $trunc) / 10;

	return ($min, $max, $avg);
}

sub capture {
	my $verbose = 0;
	my ($pfile, $logfile);
	moreOpts(\@_,
		'verbose|v+' => \$verbose,
		'pilot|p=s' => \$pfile,
		'log|l=s' => \$logfile,
	);

	my ($spec) = @_;
	my $enemy = findRes(ship => $spec);

	my $info = $pfile ? capturePilotInfo('pilot', $pfile) :
		capturePilotInfo('log', $logfile);
	my $coeff = captureCoefficients($info);
	my ($min, $max, $avg) = captureOdds($coeff, $enemy);

	if ($verbose) {
		printf "Effective crew: %s%s\n", $coeff->{crew},
			$coeff->{bonus} ? " (+ $coeff->{bonus}%)" : '';
		printf "Effective strength: $coeff->{strength}\n";
		printf "\n";
	}

	printf "To capture %s\n", resName($enemy);
	printf "Min odds: %6.2f\n", $min;
	printf "Max odds: %6.2f\n", $max;
	if ($verbose) {
		printf "Avg odds: %6.2f\n", $avg;
	}
}

1;
