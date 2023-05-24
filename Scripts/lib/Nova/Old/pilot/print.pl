use warnings;
use strict;

sub pilotPrintExplored {
	my ($pilot, $syst, $val) = @_;
	return 0 if $val == 2;
	my $details = $val == 1 ? ' (not landed)' : '';

	return 0 unless bitTestEvalPilot($syst->{Visibility}, $pilot);
	return 0 if $val == 1 && !systCanLand($syst);
	return sprintf "%d - %s%s", $syst->{ID}, $syst->{Name}, $details;
}

# To be localized
our ($id, $idx, $rez, $val, $name, @lines);

sub pilotPrint {
	my ($p, @wantcats) = @_;
	my $cat = sub {
	    my ($c, @items) = @_;
	    my $nl = ($c =~ s/\s$//);
	    return if @wantcats && !grep { $c =~ /$_/i } @wantcats;

	    my $sub = $items[0];
	    local @lines = ();
	    @items = $sub->() if ref($sub) =~ /^CODE/;

	    if ($nl) {
	        printf "%s:\n", $c;
	        printf "  %s\n", $_ foreach @items, @lines;
	    } else {
	        printf "%s: %s\n", $c, $items[0];
	    }
	};
	my $catfor = sub {
	    my ($c, $key, $type, $sub) = @_;
	    $cat->("$c ", sub {
    	    my $resources = resource($type);
			my $size = @{$p->{$key}};
    	    for $id (sort keys %$resources) {
    	        local ($idx, $rez) = ($id - 128, $resources->{$id});
				next if $idx >= $size;
    	        local ($val, $name) = ($p->{$key}[$idx], resName($rez));
    	        my $line = $sub->();
    	        push @lines, $line if $line;
    	    } ();
	    });
	};

	# GAME
	$cat->('Game', $p->{game});
	$cat->('Version', $p->{version});

	# PLAYER
	$cat->('Name', $p->{name});
	$cat->('Ship name', $p->{shipName});
  $cat->('Nickname', $p->{nick}) if $p->{nick};
	$cat->('Strict', $p->{strict} ? 'true' : 'false');
	$cat->('Gender', $p->{gender} ? 'male' : 'female');
	$cat->('Game date', UnixDate($p->{date}, "%b %E, %Y"));
    $cat->('Rating', ratingStr($p->{rating}));
    $cat->('Cash', commaNum($p->{cash}));
	$cat->('Last landed', sub {
	    my $s = findRes(spob => $p->{lastSpob} + 128);
	    sprintf "%d - %s", $s->{ID}, resName($s);
	});

	$cat->('Missions ', sub {
		pilotMisn($p, $_) for (@{$p->{missions}}); ()
	});

	# SHIP
	my $ship = findRes(ship => $p->{ship} + 128) // { Name => 'Unknown' };
	$cat->('Ship', sprintf("%d - %s", $ship->{ID}, resName($ship)));
    $cat->('Fuel', sprintf("%.2f", $p->{fuel} / 100));
	$cat->('Cargo ', map {
    my $qty = $_ < 128 ? $p->{cargo}[$_] : $p->{junk}[$_-128];
			$qty ? sprintf("%s: %d", cargoName($_), $qty) : ();
    } (0..$#{$p->{cargo}}, 128..(128+$#{$p->{junk}})));
	$catfor->(qw(Outfits outf outf), sub {
	    !$val ? 0 : sprintf "%s: %d", $name, $val;
	});
	$catfor->(qw(Weapons weap weap), sub {
	    my $ammo = $p->{ammo}[$idx];
	    (!$val && !$ammo) ? 0
	        : sprintf "%s: %d (ammo: %d)", $name, $val, $ammo;
	});
	$cat->('Escorts ', sub {
	    for my $type (qw(captured hired fighter)) {
	        my $escs = $p->{$type} or next;
	        push @lines, sprintf "%d - %s: %s", $_ + 128,
	            findRes(ship => $_ + 128)->{Name}, $type
	                foreach @$escs;
	    } ();
	});

	# GALAXY
	$catfor->(qw(Unexplored explore syst), sub {
		pilotPrintExplored($p, $rez, $val);
	});
	$cat->('Records ', sub {
	    my ($systs, %gov) = resource('syst');
	    for my $s (values %$systs) {
	        my $g = $s->{Govt};
	        push @{$gov{$g}}, { syst => $s,
	            legal => $p->{legal}[$s->{ID} - 128],
	        };
	    }
	    for my $g (sort keys %gov) {
	        my @ss = sort { $a->{legal} <=> $b->{legal} } @{$gov{$g}};
	        push @lines, sprintf("%d - %s", $g, govtName(findRes(govt => $g))),
                sprintf("  Min: %5d (%s)", $ss[0]{legal}, $ss[0]{syst}{Name}),
                sprintf("  Max: %5d (%s)", $ss[-1]{legal}, $ss[-1]{syst}{Name});
	    } ();
	});
	$catfor->(qw(Dominated dominated spob), sub {
	    sprintf "%d - %s", $id, $name if $val;
	});
	$catfor->('Defense fleets', 'defense', 'spob', sub {
	    return 0 if $p->{dominated}[$idx] || $val == 0 || $val == -1;
	    my $cnt = $rez->{DefCount};
	    return 0 if $cnt == 0 || $cnt == -1;
	    $cnt = int(($cnt - 1000) / 10) if $cnt > 1000;
	    return 0 if $cnt == $val;
	    sprintf "%d - %s: %4d / %4d", $id, $name, $val, $cnt;
	});

	# GAME GLOBALS
	$cat->('Bits ', sub {
	    my @bits = map { $p->{bit}[$_] ? sprintf("%4d", $_) : (' ' x 4) }
	        (0..$#{$p->{bit}});
	    while (my @line = splice(@bits, 0, 10)) {
	        push @lines, join '  ', @line if grep /\S/, @line;
	    } ();
	});
	$catfor->(qw(Crons cronDurations cron), sub {
	    my $hold = $p->{cronHoldoffs}[$idx];
	    return 0 if $val == -1 && $hold == -1;
		sprintf "%d - %-40s: duration = %4d, holdoff = %4d",
		    $id, $name, $val, $hold;
	}) if exists $p->{cronDurations};
	$catfor->(qw(Persons persAlive pers), sub {
	    my $grudge = $p->{persGrudge}[$idx];
	    return 0 if $val && !$grudge;
		sprintf "%d - %s: %s", $id, $name, ($val ? 'grudge' : 'killed');
	});
  $catfor->(qw(Ranks rank rank), sub {
    return 0 unless $val;
    return sprintf "%d - %s", $id, $name;
  }) if exists $p->{rank};
}

sub pilotMisn {
	my ($p, $m) = @_;
	my $misn = findRes(misn => $m->{id} + 128);
	push @lines, sprintf "%d: %s", $misn->{ID}, $misn->{Name};
	push @lines, sprintf "  Failed!" if $m->{failed};
	if ($m->{travelSpob} != -1) {
		push @lines, sprintf "  Travel: %s%s",
			findRes(spob => $m->{travelSpob} + 128)->{Name},
			$m->{travelDone} ? " (done)" : '';
	}
	if ($misn->{ReturnStel} != -1) {
		push @lines, sprintf "  Return: %s",
			findRes(spob => $m->{returnSpob} + 128)->{Name};
	}
	if (!grep { $_ == $misn->{TimeLimit} } (0, -1)) {
		push @lines, sprintf "  DaysLeft: %s",
			Delta_Format(DateCalc($m->{limit}, $p->{date}), "%dt");
	}
	if ($misn->{ShipCount} != -1) {
		my $syst = $m->{shipSyst};
		my $sname;
		if ($syst == -6) {
			$sname = "follow player";
		} else {
			$sname = findRes(syst => $m->{shipSyst} + 128)->{Name};
		}
		push @lines, "  ShipSyst: $sname";

		my $count = grep { $_ == $misn->{ShipGoal} } (0, 1, 2, 5, 6);
		if ($count) {
			my $line = sprintf "%d / %d", $m->{shipCount}, $misn->{ShipCount};
			$line .= sprintf(" (%d disabled)", $m->{shipsDisabled})
				if $m->{shipsDisabled} && $misn->{ShipGoal} == 1;
			$line .= " (done)" if $m->{shipDone};
			push @lines, sprintf "  Ships: $line";
		}
	}
	if (!grep { $_ == $misn->{AuxShipCount} } (0, -1)) {
		push @lines, sprintf "  AuxShips: %d / %d",
			$m->{auxLeft}, $misn->{AuxShipCount};
	}
}

sub pilotShow {
	my ($file) = shift;
	my $pilot = pilotParse($file);
	pilotPrint($pilot, @_);
}

1;
