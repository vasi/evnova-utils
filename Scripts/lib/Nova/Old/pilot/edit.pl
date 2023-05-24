use warnings;
use strict;

sub pilotEdit {
	my ($file, $rsrc, $code) = @_;
	my $vers = pilotVers($file);
	my $spec = { type => $vers->{type}, id => $rsrc };
	my ($res) = readResources($file, $spec);
	$spec->{name} = $res->{name};

	my $data = $res->{data};
	$data = simpleCrypt($vers->{key}, $data);
	$data = $code->($data);
	$data = simpleCrypt($vers->{key}, $data);

	$spec->{data} = $data;
	writeResources($file, $spec);
}

sub revivePers {
	my $alive = 1;
	my @systSpecs;
    moreOpts(\@_,
		'--kill|k' => sub { $alive = 0 },
		'--syst|s=s' => \@systSpecs);

	my ($file, @find) = @_;

	my $pilot = pilotParse($file);
	my $posPers = $pilot->{limits}{posPers};

	my @pers = map { findRes(pers => $_) } @find;
	if (@systSpecs) {
		my %bySyst = persBySyst($pilot, 'all');
		for my $syst (findRes(syst => @systSpecs)) {
			push @pers, @{$bySyst{$syst->{ID}}};
		}
	}

	# Filter out Bounty Hunter
	@pers = grep { $_->{ID} != 1150 } @pers;

	pilotEdit($file, 129, sub {
		my ($data) = @_;
		printf "%s:\n", $alive ? 'Reviving' : 'Killing';
		for my $p (@pers) {
			printf "  %4d - %s\n", $p->{ID}, $p->{Name};
			my $pos = $posPers + 2 * ($p->{ID} - 128);
			substr($data, $pos, 2) = pack('s>', $alive);
		}
		return $data;
	});
}

sub setCash {
	my ($file, $cash) = @_;
	my $vers = pilotVers($file);
	my %limits = pilotLimits($vers);

	pilotEdit($file, 128, sub {
		my ($data) = @_;
		substr($data, $limits{posCash}, 4) = pack('L>', $cash);
		return $data;
	});
}

sub setBits {
	my ($file, @specs) = @_;
	@specs = split ' ', join ' ', @specs;

	my $vers = pilotVers($file);
	my %limits = pilotLimits($vers);
	my $posBits = $limits{posBits};

	pilotEdit($file, 128, sub {
		my ($data) = @_;
		print "Changing bits:\n";
		for my $spec (@specs) {
			my $bit;
			my $set = 1;

			$spec =~ /(\d+)/ or next;
			$bit = $1;

			$set = 0 if $spec =~ /!/;

			printf "  %4d - %s\n", $bit, $set ? "set" : "clear";
			my $pos = $posBits + $bit;
			substr($data, $pos, 1) = pack('C', $set);
		}
		return $data;
	});
}

sub setOutf {
	my ($file, $spec, $count) = @_;
	my $outf = findRes('outf' => $spec);

	my $vers = pilotVers($file);
	my %limits = pilotLimits($vers);
	my $posOutf = $limits{posOutf};
	my $pos = $posOutf + 2 * ($outf->{ID} - 128);

	# Special handling for weapons and ammo
	my @wpos;
	my %mods = multiPropsHash($outf, 'ModType', 'ModVal');
	for my $type (1, 3) {
		next unless exists $mods{$type};
		for my $val (@{$mods{$type}}) {
			my $w = $limits{posWeap} + 2 * ($val - 128);
			$w += 2 * $limits{weap} if $type == 3;
			push @wpos, $w;
		}
	}

	pilotEdit($file, 128, sub {
		my ($data) = @_;

		my $cur = unpack('S>', substr($data, $pos, 2));
		if (!defined($count)) {
			# Default to one more than we have
			$count = $cur + 1;
		}
		my $diff = $count - $cur;

		substr($data, $pos, 2) = pack('S>', max($count, 0));

		# Handle weapons and ammo
		for my $w (@wpos) {
			$cur = unpack('S>', substr($data, $w, 2));
			my $new = max($cur + $diff, 0);
			substr($data, $w, 2) = pack('S>', $new);
		}

		printf "Pilot now has %d %s\n", $count, resName($outf);
		return $data;
	});
}

sub setShip {
	my ($file, $spec) = @_;
	my $ship = findRes('ship' => $spec);

	pilotEdit($file, 128, sub {
		my ($data) = @_;
		substr($data, 2, 2) = pack('S>', $ship->{ID} - 128);
		printf "Pilot is now in a %s\n", resName($ship);
		return $data;
	});
}

sub setRating {
	my ($file, $rating) = @_;

	pilotEdit($file, 128, sub {
		my ($data) = @_;

		my $pos = length($data) - 4;
		substr($data, $pos, 4) = pack('L>', $rating);
		return $data;
	});
}

sub setRecord {
	my $govt = 0;
    moreOpts(\@_, '--govt|g' => \$govt);

	my ($file, $record, @spec) = @_;
	my $pilot = pilotParse($file);
	my %limits = %{$pilot->{limits}};

	my @systs;
	if ($govt) {
		my %govts = map { $_->{ID} => 1 } findRes(govt => \@spec);
		my $allSyst = resource('syst');
		@systs = grep { $govts{$_->{Govt}} } values %$allSyst;
	} else {
		@systs = findRes(syst => \@spec);
	}

	# Filter out invisible systs
	@systs = grep { bitTestEvalPilot($_->{Visibility}, $pilot) } @systs;

	pilotEdit($file, 128, sub {
		my ($data) = @_;
		foreach my $syst (@systs) {
			my $pos = $limits{posLegal} + 2 * ($syst->{ID} - 128);
			substr($data, $pos, 2) = pack('s>', $record);
		}
		return $data;
	});
}

sub setSpob {
	my ($file, $spec) = @_;
	my $spob = findRes('spob' => $spec);

	pilotEdit($file, 128, sub {
		my ($data) = @_;
		substr($data, 0, 2) = pack('S>', $spob->{ID} - 128);
		printf "Pilot is now at %s\n", resName($spob);
		return $data;
	});
}

sub addExplore {
	my ($file, @specs) = @_;
	my @origSpecs = @specs;
	my @systs = findRes('syst' => \@specs);

	my $vers = pilotVers($file);
	my %limits = pilotLimits($vers);

	if (!@origSpecs) {
		# Limit to visible map
		my $pilot = pilotParse($file);
		@systs = grep { bitTestEvalPilot($_->{Visibility}, $pilot) } @systs;
	}

	pilotEdit($file, 128, sub {
		my ($data) = @_;
		for my $syst (@systs) {
			my $pos = $limits{posExplore} + 2 * ($syst->{ID} - 128);
			my $val = systCanLand($syst) ? 2 : 1;
			substr($data, $pos, 2) = pack('S>', $val);
		}
		return $data;
	});
}

sub addEscort {
	my $clear = 0;
    moreOpts(\@_, '--clear|C' => \$clear);

	my ($file, @ships) = @_;

	# Figure out what we want added
	my @add;
	while (my ($spec, $count) = splice(@ships, 0, 2)) {
		$count //= 1;
		my $ship = findRes(ship => $spec);
		push @add, $ship for 1..$count;
	}

	my $vers = pilotVers($file);
	my %limits = pilotLimits($vers);
	my $maxEscorts = 6; # Hard max in EV

	pilotEdit($file, 128, sub {
		my ($data) = @_;

		my @free;
		my $existing = 0;
		for my $i (0..$limits{escort} - 1) {
			my $pos = $limits{posEscort} + 2 * $i;

			my $val = unpack('s>', substr($data, $pos, 2));
			if ($val == -1) {
				push @free, $pos;
			} elsif ($val < 1000) {
				++$existing;
				push @free, $pos if $clear;
			}
		}

		# Limit to the allowed number of escorts
		my $room = $clear ? $maxEscorts : max(0, $maxEscorts - $existing);
		if ($room < scalar(@add)) {
			printf "Only more room for %d escorts!\n", $room;
			return $data;
		}

		printf "Removing all %d escorts\n", $existing if $clear;
		for my $pos (@free) {
			my $ship = shift @add;
			printf "Adding an %s escort\n", resName($ship) if $ship;
			my $sid = $ship ? $ship->{ID} - 128 : -1;
			substr($data, $pos, 2) = pack('s>', $sid);
		}

		return $data;
	});
}

sub swapGender {
	my ($file) = @_;

	my $vers = pilotVers($file);
	my %limits = pilotLimits($vers);
	die "Bad version" unless $limits{gender};

	pilotEdit($file, 129, sub {
		my ($data) = @_;

		my $gender = unpack('s>', substr($data, 4, 2));
		substr($data, 4, 2) = pack('s>', !$gender);
		return $data;
	});
}

1;
