use warnings;
use strict;

sub killable {
	my $perss = resource('pers');
	for my $id (sort keys %$perss) {
		my $p = $perss->{$id};
		next if $p->{Flags} & 0x2;
		printf "%4d: %s\n", $id, $p->{Name};
	}
}

sub persBySyst {
    my ($pilot, $all) = @_;

	my %systsPers;
	for my $p (values %{resource('pers')}) {
        if (!$all) {
			next unless bitTestEvalPilot($p->{ActivateOn}, $pilot);
			next unless $pilot->{persAlive}[$p->{ID} - 128];
		}
		my @systs = systsMatching($p->{LinkSyst});
		push @{$systsPers{$_}}, $p for @systs;
	}

    return %systsPers;
}

sub wherePers {
	my ($pilotFile, $find) = @_;

    my $pilot = pilotParse($pilotFile);
    my %systsPers = persBySyst($pilot);

	my $pers = findRes(pers => $find);
    my $systs = resource('syst');
	my @systs = grep { bitTestEvalPilot($systs->{$_}{Visibility}, $pilot) }
        systsMatching($pers->{LinkSyst});
	my %pcts;
	for my $s (@systs) {
		my $count = scalar(@{$systsPers{$s}});
		my $frac = 1 / $count;
		$frac /= 20;

		my $syst = findRes(syst => $s);
        # FIXME: no replacement of pers ships
		$frac = 1 - ((1-$frac) ** $syst->{AvgShips});
		$pcts{$s} = $frac * 100;
	}

	my $count = 0;
	printf "Systems with %s (%d):\n", resName($pers), $pers->{ID};
	for my $sid (sort { $pcts{$b} <=> $pcts{$a} } @systs) {
		my $syst = findRes(syst => $sid);
		printf "%5.3f %% - %4d: %s\n", $pcts{$sid}, $sid, $syst->{Name};
		last if $count++ >= 20;
	}
}

sub systPers {
    my ($pilotFile, $systSpec) = @_;

    my $pilot = pilotParse($pilotFile);
    my %systsPers = persBySyst($pilot);

    my $syst = findRes(syst => $systSpec);
    list('pers', map { $_->{ID} } @{$systsPers{$syst->{ID}}});
}

1;
