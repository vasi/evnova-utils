use warnings;
use strict;

our @misnNCBset = qw(OnSuccess OnRefuse OnAccept
    OnFailure OnAbort OnShipDone);

sub isAvail {
    my ($cache, $pilot, $misn, %options) = @_;
    return 0 if $misn->{AvailRandom} <= 0;
	return 0 if $options{bar} && $misn->{AvailLoc} != 1;
    return 1 unless $pilot;

    return 0 if !bitTestEvalPilot($misn->{AvailBits}, $pilot);
	return 0 if $options{rating} && $misn->{AvailRating} > $pilot->{rating};

	# Check if there's a system where this mission is available
	return 1 if $misn->{AvailStel} == -1;
	my $systs = resource('syst');
	my @avail = systsSelect($cache, { spob => $misn->{AvailStel} });
	for my $systID (@avail) {
		my $syst = $systs->{$systID};

		# Check visibility
		next unless bitTestEvalPilot($syst->{Visibility}, $pilot);

		# Check legal record
		if ($options{legal} && $misn->{AvailRecord}) {
			my $arec = $misn->{AvailRecord};
			my $srec = $pilot->{legal}[$systID - 128];
			next if $arec > 0 && $arec > $srec;
			next if $arec < 0 && $arec < $srec;
		}

		# This syst is ok
		return 1;
	}

	# Found no systs
	return 0;
}

sub availMisns {
	my ($verbose, $quiet, $secret, $unique, $fieldcheck, $idonly, $random) = (0, 0, 0, 0, 0, 0, 0);
	my %options;
	moreOpts(\@_, 'verbose|v+' => \$verbose,
	    'unique|u:+' => \$unique,
	    'fieldcheck|f' => \$fieldcheck,
        'idonly|i' => \$idonly,
		'rating|r' => \$options{rating},
		'legal|l' => \$options{legal},
		'nopers|p' => \$options{nopers},
		'bar|b' => \$options{bar},
		'random|1' => \$random,
		'secret|s' => \$secret,
		'quiet|q' => \$quiet);
	my ($pfile, $progress) = @_;

	# Read the progress
	my (%include, %exclude);
	if (defined $progress) {
		open my $fh, '<', $progress or die $!;
		while (<$fh>) {
			if (/^\s*(-?)(#?\d+)/) {
				my $h = $1 ? \%exclude : \%include;
				my $id = secretDecode('misn', $2);
				$h->{$id} = 1;
			}
		}
    }

	# Read the pilot
	my $pilot = pilotParse($pfile);

	# Find ok missions
	my (@ok, %bits);
	my %cache;
	my $misns = resource('misn');
	for my $misn (values %$misns) {
		next if $options{nopers} && $misn->{AvailLoc} == 2;
		next if $exclude{$misn->{ID}} || (%include && !$include{$misn->{ID}});
        next unless isAvail(\%cache, $pilot, $misn, %options);
		push @ok, $misn;
		push @{$bits{$misn->{AvailBits}}}, $misn;
	}

	# Filter interesting missions
	if ($unique) {
	    @ok = ();
	    for my $ms (values %bits) {
	        next unless @$ms <= $unique;
	        push @ok, @$ms;
	    }
	}
	if ($fieldcheck) {
    	@ok = grep {
    	    my $m = $_;
    	    $m->{AvailBits} &&
    	        grep { $m->{$_} } @misnNCBset;
    	} @ok;
    }

	# Print
    @ok = sort { $a->{ID} <=> $b->{ID} } @ok;
	if ($random && @ok) {
		@ok = ($ok[rand(@ok)]);
	}

    if ($idonly) {
        printf "%d\n", $_->{ID} for @ok;
    } else {
		printMisns({verbose => $verbose, quiet => $quiet, secret => $secret}, @ok);
	}
}

sub persMisns {
	my %selected = map { $_->{ID} => 1 }
		map { findRes('misn' => $_) } @_;
	
	my $misns = resource('misn');
	my %persMisns;
	for my $id (keys %$misns) {
		$persMisns{$id} = [] if $misns->{$id}->{AvailLoc} == 2;
	}

	my $perss = resource('pers');
	for my $id (keys %$perss) {
		my $pers = $perss->{$id};
		my $link = $pers->{LinkMission};
		next if $link == -1;
		push @{$persMisns{$link}}, $pers;
	}

	my $systs = resource('syst');
	my $ships = resource('ship');
	my $govts = resource('govt');
	my $strns = resource('STR#');
	for my $id (sort keys %persMisns) {
		next if %selected && !$selected{$id}; 

		my $misn = $misns->{$id};
		printf "%d: %s\n", $id, $misn->{Name};
		for my $fld (qw(AvailRecord AvailRating AvailRandom AvailShipType
				AvailBits CargoQty)) {
			printf "  %s: %s\n", $fld, $misn->{$fld};
		}
		print "  Unavailable if in freighter\n" if $misn->{Flags} & 0x2000;
		print "  Unavailable if in warship\n" if $misn->{Flags} & 0x4000;
		print "  Require sufficient cargo space\n" if $misn->{Flags2} & 0x0001;

		my @from = sort { $a->{ID} <=> $b->{ID} } @{$persMisns{$id}};
		my %from;
		for my $pers (@from) {
			my $ship = $ships->{$pers->{ShipType}};
			my $from = "    Ship: $ship->{Name}\n";
			my $lsyst = $pers->{LinkSyst};
			if ($lsyst >= 128 && $lsyst <= 2175) {
				$from .= "    LinkSyst: " . $systs->{$lsyst}->{Name} . "\n";
			} elsif ($lsyst != -1) {
				$from .= "    LinkSyst: " . govtRel($lsyst) . "\n";
			}
			if ($pers->{Govt} >= 128) {
				my $govt = $govts->{$pers->{Govt}};
				$from .= "    Govt: $govt->{Name}\n";
				$from .= "    Disabled\n" if $govt->{Flags} & 0x0800;
			}
			$from .= "    Board ship for mission\n"
				if $pers->{Flags} & 0x0200;
			$from .= "    Unavailable if in wimpy freighter\n"
				if $pers->{Flags} & 0x1000;
			$from .= "    Unavailable if in beefy freighter\n"
				if $pers->{Flags} & 0x2000;
			$from .= "    Unavailable if in warship\n"
				if $pers->{Flags} & 0x4000;
			my $hq = $pers->{HailQuote};
			if ($hq != -1) {
				$from .= "    HailQuote: " .
					$strns->{7101}->{Strings}->[$hq-1] . "\n";
			}
			push @{$from{$from}}, $pers;
		}
		for my $from (sort { $from{$a}[0]{ID} <=> $from{$b}[0]{ID} }
				keys %from) {
			for my $pers (@{$from{$from}}) {
				printf "  %d: %s\n", $pers->{ID}, $pers->{Name};
			}
			print $from;
		}
	}

}

1;
