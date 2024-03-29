use warnings;
use strict;

use utf8;

sub shipRankWeights {
	my (@fields) = @_;
	my $filter = sub { return 1 };
	if (ref($fields[-1]) eq 'CODE') {
		$filter = pop @fields;
	}

	my @names = map { $fields[2 * $_] } (0..$#fields/2); # Preserve order
	my %weights = @fields;

	my $calc = sub {
		my ($ship) = @_;
		my $sum = 0;
		while (my ($k, $weight) = each %weights) {
			my $v = $ship->{$k};
			$sum += $weight * $v;
		}
		return $sum;
	};

	shipRank(\@names, $calc, $filter);
}

sub shipRank {
	my ($fieldNames, $calc, $filter) = @_;
	$filter //= sub { return 1 };
	my @names = @$fieldNames;

	# Calculate ranks & lengths
	my (%rank, %lengths);
	my $ships = resource('ship');
	while (my ($id, $ship) = each %$ships) {
		next unless $filter->($ship);
		foreach my $k (@names) {
			my $v = $ship->{$k};
			push @{$lengths{$k}}, length $v;
		}
		my $sum = $calc->($ship);

		$rank{$id} = $sum;
		push @{$lengths{Sum}}, length int($sum);
		push @{$lengths{Cost}}, length commaNum($ship->{Cost} / 1000);
		push @{$lengths{Name}}, length resName($ship);
	}

	# Generate format string for each row
	my %flen = map { $_ => max @{$lengths{$_}} } keys %lengths;
	my (@fmts, @hdrs);
	for my $k (@names) {
		push @fmts, "%$flen{$k}d";
	}
	my $vfmt = "%$flen{Sum}d:   " . join('   ', @fmts);
	my $fmt = $vfmt . "   %-$flen{Name}s %4d  %$flen{Cost}sK\n";

	# Print headers
	my @hpos;
	for my $i (0..$#names) {
		my $sent = 123456789012;
		my @vs = (0) x (1 + @names);
		$vs[1 + $i] = $sent;
		my $tmpl = sprintf $vfmt, @vs;
		push @hpos, index $tmpl, $sent;
	}
	my $hdrs = '';
	for my $i (0..$#names) {
		my $h = $hpos[$i];
		$hdrs = sprintf "%-*.*s", $h, $h, $hdrs;
		if ($i < $#names) {
			my $l = $hpos[$i + 1] - $h - 1;
			substr($hdrs, $h, $l) = sprintf "%-*.*s", $l, $l, $names[$i];
		} else {
			substr($hdrs, $h, 0) = $names[$i];
		}
	}
	printf "%s\n", $hdrs;

	# Print rows
	my $sort = sub { $rank{$b} <=> $rank{$a} || $a <=> $b };
	for my $id (sort { $sort->() } keys %rank) {
		my $ship = $ships->{$id};
		my @vals = map { $ship->{$_} } @names;
		printf $fmt, $rank{$id}, @vals, resName($ship), $id,
			commaNum($ship->{Cost} / 1000);
	}
}

sub defense {
	my ($arm) = @_;
	shipRankWeights(Shield => 1, Armor => $arm // 1);
}

sub agilityWeights {
	my ($acc, $man) = @_;
	$acc //= 0.1;
	$man //= 1.5;
	return ($acc, $man);
}

sub myAgility {
	my ($file, @weights) = @_;
	my ($wacc, $wman) = agilityWeights(@weights);

	my $pilot = pilotParse($file);
	my $ship = findRes(ship => $pilot->{ship} + 128);
	my @names = qw(Speed Accel Maneuver);
	my %props = map { $_ => $ship->{$_} } @names;

	my %types = (7 => 'Accel', 8 => 'Speed', 9 => 'Maneuver');
	my %found;
	for my $item (pilotItems($pilot)) {
		my $outf = findRes(outf => $item->{id});
		my %mods = multiPropsHash($outf, 'ModType', 'ModVal', -1);
		while (my ($type, $vals) = each %mods) {
			my $name = $types{$type} or next;
			foreach my $val (@$vals) {
				push @{$found{$name}}, {outf => $outf, id => $outf->{ID},
					count => $item->{count}, val => $val };
			}
		}
	}

	for my $type (@names) {
		my $xtra = ($type eq 'Maneuver') ? ' / 10' : '     ';
		printf "%-8s                    %4d\n", $type, $props{$type};
		my @items = sort { $a->{id} <=> $b->{id} } @{$found{$type}};
		for my $item (@items) {
			my $mod = $item->{count} * $item->{val};
			$mod *= 0.1 if $type eq 'Maneuver';
			printf "%-8s   %2d * %4d$xtra = %4d   %s (%d)\n", $type, $item->{count},
				$item->{val}, $mod, resName($item->{outf}), $item->{id};
			$props{$type} += $mod;
		}
		printf "%-8s                    %4d\n", $type, $props{$type} if @items;
		print "\n";
	}

	printf "Agility = %4d + (%3d * %.1f) + (%3d * %.1f) = %d\n",
		$props{Speed}, $props{Accel}, $wacc, $props{Maneuver}, $wman,
		$props{Speed} + $props{Accel} * $wacc + $props{Maneuver} * $wman,
}

sub agility {
	my $buyable;
	moreOpts(\@_, 'buyable' => \$buyable);
	my ($wacc, $wman) = agilityWeights(@_);
	my $filter = sub { return 1 };
	if ($buyable) {
		$filter = sub { return int($_[0]->{BuyRandom}) != 0 };
	}

	shipRankWeights(Speed => 1, Accel => $wacc // 0.1, Maneuver => $wman // 1.5, $filter);
}

sub whereShip {
	my ($booty, $pilot);
	my $max = 20;
	moreOpts(\@_,
		'booty|b' => \$booty,
		'max|m=i' => \$max,
		'pilot|p=s' => sub { $pilot = pilotParse($_[1] )});

	my @ships = findRes(ship => \@_);
	my %ships = map { $_->{ID} => 1 } @ships;

	my %dudes;
	my $dudes = resource('dude');
	for my $dude (values %$dudes) {
		next if $booty && !($dude->{Booty} & 0x40);

		my $total = 0;
		my $want = 0;
		for my $kt (grep /^ShipTypes\d+/, keys %$dude) {
			(my $kp = $kt) =~ s/ShipTypes(\d+)/Probs$1/;
			my ($vt, $vp) = map { $dude->{$_} } ($kt, $kp);

			if ($pilot) {
				my $ship = findRes(ship => $vt);
				next unless bitTestEvalPilot($ship->{AppearOn}, $pilot);
			}
			$total += $vp;

			next unless $ships{$vt};
			$want += $vp;
		}

		next if $total == 0;
		$dudes{$dude->{ID}} = 100.0 * $want / $total;
	}

	my %systs;
	my $systs = resource('syst');
	for my $syst (values %$systs) {
		my $prob = 0;
		for my $kt (grep /^DudeTypes\d+/, keys %$syst) {
			(my $kp = $kt) =~ s/DudeTypes(\d+)/Probs$1/;
			my ($vt, $vp) = map { $syst->{$_} } ($kt, $kp);
			next unless $dudes{$vt};
			$prob += ($vp / 100) * $dudes{$vt};
		}
		$systs{$syst->{ID}} = 100 - 100*(1-($prob/100))**($syst->{AvgShips});
	}

	my $count = 0;
	my $names = join ', ', map { sprintf "%s (%d)", resName($_), $_->{ID} } @ships;
	printf "Systems with %s:\n", $names;
	for my $sid (sort { $systs{$b} <=> $systs{$a} } keys %systs) {
		last if $systs{$sid} == 0;

		my $syst = $systs->{$sid};
		my ($govt) = findRes(govt => $syst->{Govt});
		printf "%6.2f %% - %4d: %-20s %2d  %s\n", $systs{$sid}, $sid,
			$syst->{Name}, $syst->{AvgShips}, govtName($govt);
		last if $count++ >= $max;
	}
}

sub whereGovt {
	my $max = 20;
	my ($distance, $near) = (3);
	moreOpts(\@_, 'max|m=i' => \$max,
		'near|n=s' => \$near, 'distance|d=i' => \$distance);

	my (@govts) = @_;
	my %gids = map { $_->{ID} => 1 } findRes(govt => \@govts);

	my %strengths;
	for my $dude (values %{resource('dude')}) {
		next unless $gids{$dude->{Govt}};
		$strengths{$dude->{ID}} = dudeStrength($dude);
	}

	my @systs = values %{resource('syst')};
	if ($near) {
		@systs = systsNear(findRes(syst => $near), $distance);
	}

	my %systStrengths;
	for my $syst (@systs) {
		my %dudes = multiPropsHash($syst, 'DudeTypes', 'Probs');
		while (my ($dude, $prob) = each %dudes) {
			next unless $strengths{$dude};
			$systStrengths{$syst->{ID}} += 0.01 * @$prob[0] * $strengths{$dude}
				* $syst->{AvgShips};
		}
	}

	my @sorted = sort { $systStrengths{$b} <=> $systStrengths{$a} }
		keys %systStrengths;
	for my $sid (@sorted) {
		return unless $max--;
		my $syst = findRes(syst => $sid);
		printf "%6.2f - %4d: %-20s\n", $systStrengths{$sid}, $sid, $syst->{Name};
	}
}

sub shieldRegen {
	my ($rezFile, $remod, $smod, @fields) = @_;
	$remod ||= 0;
	$smod ||= 0;

	my $ships = resource('ship');

	# Read resource files
	my @rezSpecs = map { { type => 'shïp', id => $_ } } keys %$ships;
	my @rez = readResources($rezFile, @rezSpecs);
	my $pos = 0x10; # Position of ShieldRe in resource

	# Find recharge data
	my (%shieldre, %rate);
	for my $rez (@rez) {
		my $id = $rez->{id};
		my $ship = $ships->{$id};

		$shieldre{$id} = unpack('S>', substr($rez->{data}, $pos, 2));

		# Frames per shield percentage point
		my $re = $shieldre{$id};
		$re = 1 if $re < 1;

		# Total shield
		my $shield = $ship->{Shield} + $smod;

		my $onePct = $shield / 100.0;
		my $perFrame = $onePct / $re;
		my $perSecond = $perFrame * 30;
		$perSecond += $remod / 30;
		
		# Display hundredths-of-points-per-second
		$rate{$id} = int(100 * $perSecond);
	}

    rankHeaders('ShieldRe', @fields);
	listBuildSub(type => 'ship',
		value => sub { $rate{$::r{ID}} },
		filter => sub { exists $rate{$::r{ID}} },
        print => sub { $shieldre{$::r{ID}}, @::r{@fields} },
	);
}

sub maxGuns {
	# Reasonable turret factors, based on turret reload/strength differences,
	# and whether or not turrets count as guns too.
	#	EVC: laser - 1.75, proton - 3
	#	EVO: blaze, phase - 1, neutron, emalgha - 0
	#	EVN: light blaster - 1, med blaster - 1.3, fusion - 6, biorelay - 1,
	#		 100mm railgun - 0.65
	my ($turretFactor) = shift // 1;

	rankHeaders('MaxGun', 'MaxTur');
	listBuildSub(type => 'ship',
		value => sub { $::r{MaxGun} + $::r{MaxTur} * $turretFactor },
		print => sub { @::r{'MaxGun', 'MaxTur'} });
}

# The Strength field on ships is really poor.
sub betterStrength {
	my ($ship) = @_;
	return memoize($ship->{ID}, sub {
		my $strength = $ship->{Shield} + $ship->{Armor};
		for my $kweap (grep /^WType/, keys %$ship) {
			my $wtype = $ship->{$kweap};
			next if $wtype < 1;

			my $weap = findRes(weap => $wtype);
			if ($weap->{Guidance} == 99) {
				# Carrier bay. Add the strength of each carried ship.
				(my $kammo = $kweap) =~ s/WType/Ammo/;
				my $carriedCount = $ship->{$kammo};
				my $carried = findRes(ship => $weap->{AmmoType});
				$strength += $carriedCount * betterStrength($carried); 
			} else {
				(my $kcount = $kweap) =~ s/WType/WCount/;
				# Heuristically, add 200 per weapon
				$strength += 200 * $ship->{$kcount};
			}
		}
		return $strength;
	});
}

sub printStrength {
	shipRank([], sub { betterStrength($_[0]) });
}

1;
