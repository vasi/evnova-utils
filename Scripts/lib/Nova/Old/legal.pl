use warnings;
use strict;

sub suckUp {
    my ($pfile);
	moreOpts(\@_, 'pilot|p=s' => \$pfile);
	my (@govts) = @_;

    my $pilot = pilotParse($pfile) if defined $pfile;

	@govts = map { scalar(findRes(govt => $_)) } @govts;
	my %govts = map { $_->{ID} => 1 } @govts;

	my $ms = resource('misn');
	my %ms;
	my %cache;
	for my $mid (sort keys %$ms) {
		my $m = $ms->{$mid};
		my $gv = $m->{CompGovt};
		next unless $m->{CompReward} > 0;
		next unless $govts{$gv};
		next unless !$pilot ||
			isAvail(\%cache, $pilot, $m, legal => 1, rating => 1);
		push @{$ms{$m->{CompReward}}}, $m;
	}

	for my $cr (sort { $b <=> $a } keys %ms) {
		for my $m (@{$ms{$cr}}) {
			printf "%3d: %s (%d)\n", $cr, $m->{Name}, $m->{ID};
		}
	}
}

sub legalFromPilot {
	my ($file, @finds) = @_;
	my $pilot = pilotParse($file);
	for my $find (@finds) {
		my $syst = findRes(syst => $find);
		my $legal = $pilot->{legal}[$syst->{ID} - 128];
		printf "%-10s: %4d\n", $syst->{Name}, $legal;
	}
}

sub records {
	my $strs = resource('STR#');
	my @recs = @{$strs->{134}{Strings}};

	shift @recs; # N/A
	my @bad = splice @recs, 0, 9;
	my @good = splice @recs, 0, 6;
	for my $r (reverse(@bad), @good) {
		print "$r\n";
	}
}

sub legalGovt {
	my ($pilotFile, $find, $count) = @_;

	my $govt;
	if (defined $find) {
		if ($find eq '-1') {
				$govt = -1;
		} else {
			my $govtRsrc = findRes(govt => $find) if defined $find;
			$govt = $govtRsrc->{ID};
		}
	}
	my $pilot = pilotParse($pilotFile);
	my $systs = resource('syst');

	my %legal;
	for my $s (values %$systs) {
		next if defined $govt && $s->{Govt} != $govt;
		next unless bitTestEvalPilot($s->{Visibility}, $pilot);
		$legal{$s->{ID}} = $pilot->{legal}[$s->{ID} - 128];
	}

	my @sorted = sort { $legal{$b} <=> $legal{$a} } keys %legal;
	$count = 8 unless $count;
	for my $idx (0..$#sorted) {
		next unless $idx < $count || $#sorted - $idx < $count;
		my $sid = $sorted[$idx];
		printf "%5d: %s (%d)\n", $legal{$sid}, $systs->{$sid}{Name}, $sid;
		print "-----\n" if $idx == $count - 1 && $idx <= $#sorted - $count;
	}
}

1;
