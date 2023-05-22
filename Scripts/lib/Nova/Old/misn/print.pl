use warnings;
use strict;

our @misnNCBset;

sub govtRel {
	my ($spec) = @_;

	my $cat = int(($spec+1)/1000);
	my $govid = $spec - ($cat * 1000) + 128;
	my $govt = findRes(govt => $govid);

	my %cats = (
		10 => 'govt %s',
		15 => 'ally of govt %s',
		20 => 'any govt but %s',
		25 => 'enemy of govt %s',
		30 => 'class-mate of govt %s',
		31 => 'non-class-mate of govt %s'
	);
	die "No category $cat for spec $spec\n" unless exists $cats{$cat};
	die "No govt id $govid for spec $spec\n"
		unless defined($govt) || $govid == 127;

	my $govstr = sprintf "%s (%d)", govtName($govt), $govid;
	return sprintf "$cats{$cat}", $govstr;
}

sub spobText {
	my ($spec) = @_;
	if ($spec == -2) {
		return "random inhabited";
	} elsif ($spec == -3) {
		return "random uninhabited";
	} elsif ($spec == -4) {
		return "same as AvailStel";
	} elsif ($spec < 5000) {
		my $spob = findRes(spob => $spec);
		my $syst = spobSyst($spec);
		return sprintf "%s (%d) in %s", $spob->{Name}, $spob->{ID}, $syst->{Name};
	} elsif ($spec < 9999) {
		my $syst = findRes(syst => $spec - 5000 + 128);
		return sprintf "system adjacent to %s", $syst->{Name};
	} else {
		return govtRel($spec);
	}
}

sub systText {
	my ($res, $field) = @_;
	my $spec = $res->{$field};
	if ($spec == -1) {
		if ($field eq 'ShipSyst') {
			return "AvailStel syst";
		} else {
			return "follow the player";
		}
	} elsif ($spec == -3) {
		return "TravelStel syst";
	} elsif ($spec == -4) {
		return "ReturnStel syst";
	} elsif ($spec == -5) {
		return "adjacent to AvailStel syst";
	} elsif ($spec == -6) {
		return "follow the player";
	} elsif ($spec < 5000) {
		my $syst = findRes(syst => $spec);
		return $syst->{Name};
	} else {
		return govtRel($spec);
	}
}

sub shipGoal {
	my ($i) = @_;
	my @goals = qw(destroy disable board escort observe rescue chase);
	return $i > 0 ? $goals[$i] : undef;
}

sub misnText {
	my ($m, %opts) = @_;
	my $ret = '';
	my $section = $opts{details} ? "\n\n" : "\n";

	# Name
	if ($opts{secret}) {
		$ret .= sprintf "SecretID: %s\n", secretEncode('misn', $m->{ID});
	} else {
		my $name = $m->{Name};
		if ($name =~ /^(.*);(.*)$/) {
			$ret .= sprintf "%s (%d): %s$section", $2, $m->{ID}, $1;
		} else {
			$ret .= sprintf "%s (%d)$section", $name, $m->{ID};
		}
	}

	# Availability
	my %govstr;
	if ((my $spec = $m->{AvailStel}) != -1) {
		$ret .= "AvailStel: " . spobText($spec) . "\n";
	}
	if ((my $loc = $m->{AvailLoc}) != 1) {
		my %locs = (	0 => 'mission computer',	2 => 'pers',
						3 => 'main spaceport',		4 => 'trading',
						5 => 'shipyard',			6 => 'outfitters');
		$ret .= "AvailLoc: $locs{$loc}\n";
		if ($loc == 2) {
			# Find a ship that matches this mission
			my @pers = grep { $_->{LinkMission} == $m->{ID} } values %{resource('pers')};
			my $chosen = @pers[rand(@pers)];
			$ret .= sprintf "Pers: %s (%d)\n", resName($chosen), $chosen->{ID};
		}
	}
	if ((my $rec = $m->{AvailRecord}) != 0) {
		$ret .=  "AvailRecord: $rec\n";
	}
	unless ($opts{secret}) {
		my $rating = $m->{AvailRating};
		if ($rating != 0 && $rating != -1) {
			$ret .= sprintf "AvailRating: %s\n", ratingStr($rating);
		}
	}
	if ((my $random = $m->{AvailRandom}) != 100) {
		$ret .= "AvailRandom: $random%\n";
	}
	my $shiptype = $m->{AvailShipType};
	if ($shiptype >= 128) {
		$ret .= "AvailShipType: $shiptype\n";
	}
	unless ($opts{secret}) {
		for my $f ('AvailBits', @misnNCBset) {
				my $v = $m->{$f} or next;
				$ret .= "$f: $v\n";
		}
	}
	if ($m->{CargoQty} != -1 && $m->{CargoQty} != 0) {
		$ret .= "CargoQty: $m->{CargoQty}\n";
	}
	if ($m->{Flags} & 0x40) {
		$ret .= "Abortable: with penalty\n";
	}

	if ($opts{details}) {
		$ret .= "\n";

		# Reward
		my $hasReward;
		if ($m->{PayVal} > 0) {
			$ret .= sprintf "PayVal: %dK\n", $m->{PayVal} / 1000;
			$hasReward = 1;
		}
		if ($m->{CompReward} > 0) {
			my $govt = findRes(govt => $m->{CompGovt});
			$ret .= sprintf "CompGovt: %s (%d)\n", resName($govt), $govt->{ID};
			$ret .= sprintf "CompReward: %d\n", $m->{CompReward};
			$hasReward = 1;
		}
		$ret .= "\n" if $hasReward;

		# Ships
		my $ships = 0;
		if ($m->{ShipCount} > 0) {
			$ships = 1;
			my $dude = findRes(dude => $m->{ShipDude});
			my $goal = shipGoal($m->{ShipGoal});
			$ret .= sprintf "Ships: %s%s%s (%d)\n",
				($goal ? ucfirst "$goal " : ''),
				"$m->{ShipCount} ",
				$dude->{Name}, $dude->{ID};
			$ret .= "ShipSyst: " . systText($m, 'ShipSyst') . "\n";
		}
		if ($m->{AuxShipCount} > 0) {
			$ships = 1;
			my $dude = findRes(dude => $m->{AuxShipDude});
			$ret .= sprintf "AuxShips: %s%s (%d)\n",
				($m->{AuxShipCount} > 1 ? "$m->{AuxShipCount} " : ''),
				$dude->{Name}, $dude->{ID};
			$ret .= "AuxShipSyst: " . systText($m, 'AuxShipSyst') . "\n";
		}
		if ($m->{Flags} & 0x20) {
			$ships = 1; # best category
			my @govts = scanGovts($m->{ScanMask});
			$ret .= sprintf "NoScan: %s\n", join(', ', map {
				sprintf "%s (%d)", resName($_), $_->{ID}
			} @govts);
		}
		$ret .= "\n" if $ships;

		# Places to go
		my $where = 0;
		if ((my $spec = $m->{TravelStel}) != -1) {
			$where = 1;
			$ret .= "TravelStel: " . spobText($spec) . "\n";
		}
		if ((my $spec = $m->{ReturnStel}) != -1) {
			$where = 1;
			$ret .= "ReturnStel: " . spobText($spec) . "\n";
		}
		my $limit = $m->{TimeLimit};
		if ($limit != 0 && $limit != -1) {
			$ret .= "TimeLimit: " . $limit . "\n";
		}
		$ret .= "\n" if $where;

		# Descs
		$m->{InitialText} = $m->{ID} + 4000 - 128;
		my @fields = qw(InitialText QuickBrief);
		@fields = (@fields, qw(RefuseText BriefText LoadCargText ShipDoneText
			DropCargText CompText FailText)) if $opts{verbose};
		for my $type (@fields) {
			my $descid = $m->{$type};
			next if $descid < 128;
			my $r = findRes(desc => $descid);
			if ($r) {
				$ret .= sprintf "%s: %s$section", $type, $r->{Description};
			}
		}
	}
	return $ret;
}

sub printMisns {
	my ($opts, @misns) = @_;
	if ($opts->{quiet}) {
		for my $misn (@misns) {
			printf "%4d: %s\n", $misn->{ID}, resName($misn);
		}
	} else {
		my $join = $opts->{verbose} ? "\n\n" : "\n";
		my @text = map { misnText($_, %$opts) } @misns;
		print_breaking(join $join, @text);
	}
}

sub misn {
	my ($details, $verbose, $secret, $quiet, $pilotfile) = (0, 0, 0, 0);
	moreOpts(\@_,
		'details|d+' => \$details,
		'verbose|v+' => \$verbose,
		'secret|s' => \$secret,
		'quiet|q' => \$quiet,
		'pilot|p=s' => \$pilotfile);

	my @misns;
	if ($pilotfile) {
		my $pilot = pilotParse($pilotfile);
		my @finds = map { $_->{id} + 128 } @{$pilot->{missions}};
		@misns = @finds ? findRes('misn' => \@finds) : ();
	} else {
		@misns = map { findRes(misn => $_)	}
			map { secretDecode('misn', $_) }
			map { /^(\d+)-(\d+)$/ ? ($1..$2) : $_	}
			split /,/, join ',', @_;
	}

	printMisns({
		details => $details || $verbose,
		verbose => $verbose,
		secret => $secret,
		quiet => $quiet
	}, @misns);
}

1;
