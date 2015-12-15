use warnings;
use strict;


sub printTechs {
	my ($h) = @_;
	for my $t (sort { $b <=> $a } keys %$h) {
		my @sps = @{$h->{$t}};

		# uniquify
		my %sps = map { $_->{ID} => $_ } @sps;
		@sps = values %sps;
		@sps = sort { $a->{Name} cmp $b->{Name} } @sps;

		my $first = shift @sps;
		printf "  %4d: %s (%d)\n", $t, $first->{Name},
			$first->{ID};
		printf "        %s (%d)\n", $_->{Name} , $_->{ID}
			for @sps;
	}
}

sub spobtech {
	my ($flags) = 0x1;
	moreOpts(\@_, 'outfit|o' => sub { $flags = 0x5 },
        'ship|s' => sub { $flags = 0x9 });

	my ($filtType, @filtVals) = @_;
	$filtType = 'none' unless defined $filtType;
	if ($filtType =~ /^\d+$/) {
		($filtType, @filtVals) = ('tech', $filtType, @filtVals);
	}

	my $sps = resource('spob');
	my $govt;
	if ($filtType eq 'govt') {
		my @govts = map { findRes(govt => $_) } @filtVals;
		$govt = { map { $_->{ID} => 1 } @govts };
	}

	my %tech;
	my %special;
	for my $sid (sort keys %$sps) {
		my $s = $sps->{$sid};
		next if defined $govt && !$govt->{$s->{Govt}};
        next unless ($s->{Flags} & $flags) == $flags;
		push @{$tech{$s->{TechLevel}}}, $s;
		for my $kst (grep /^SpecialTech/, keys %$s) {
			my $st = $s->{$kst};
			next if $st == -1;
			push @{$special{$st}}, $s;
		}
	}

	if ($filtType eq 'tech') {
		my %ok = map { $_ => 1 } @filtVals;
		for my $t (keys(%tech), keys(%special)) {
			next if $ok{$t};
			delete $tech{$t};
			delete $special{$t};
		}
	}

	print "Tech levels:\n";
	printTechs \%tech;
	print "Special techs:\n";
	printTechs \%special;
}

sub outftech {
	my $os = resource('outf');
	my %tech;
	for my $oid (sort keys %$os) {
		my $o = $os->{$oid};
		push @{$tech{$o->{TechLevel}}}, $o;
	}
	printTechs \%tech;
}

sub shiptech {
	my $ss = resource('ship');
	my %tech;
	for my $sid (sort keys %$ss) {
		my $s = $ss->{$sid};
		push @{$tech{$s->{TechLevel}}}, $s;
	}
	printTechs \%tech;
}

sub closestTech {
	my ($curSyst, @techs) = @_;
	$curSyst = findRes(syst => $curSyst);

	my %dists;
	SPOB: for my $spob (values %{resource('spob')}) {
		my $syst = eval { spobSyst($spob->{ID}) };
		next if $@;

		my $dist = systDist($curSyst->{ID}, $syst->{ID});
		my @special = multiProps($spob, 'SpecialTech');

		for my $tech (@techs) {
			next SPOB unless $spob->{TechLevel} >= $tech
				|| grep { $_ == $tech } @special;
		}
		push @{$dists{$dist}}, sprintf "%s in %s",
			$spob->{Name}, $syst->{Name};
	}

	my $count = 20;
	my @dists = sort { $a <=> $b } keys %dists;
	for my $dist (@dists) {
		last if $count <= 0;
		my @spobs = sort @{$dists{$dist}};
		$count -= scalar(@spobs);

		for my $idx (0..$#spobs) {
			my $pre = $idx ? ' ' x 5 : sprintf "%4d:", $dist;
			print "$pre $spobs[$idx]\n";
		}
	}
}

sub closestOutfit {
	my $systSpec;
	moreOpts(\@_, 'syst|s=s' => \$systSpec);

	my $syst;
	if (defined $systSpec) {
		$syst = findRes(syst => $systSpec);
	} else {
		my $pfile = shift;
	    my $pilot = pilotParse($pfile);
	    $syst = spobSyst($pilot->{lastSpob} + 128);
	}

    my ($spec) = @_;

	my $outf = findRes(outf => $spec);
    my $tech = $outf->{TechLevel};

    closestTech($syst->{ID}, $tech);
}

1;
