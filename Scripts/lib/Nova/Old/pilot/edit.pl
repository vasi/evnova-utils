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
	my ($file, @find) = @_;
	my @pers = map { findRes(pers => $_) } @find;
	my $vers = pilotVers($file);
	my %limits = pilotLimits($vers);
	my $posPers = $limits{posPers};

	pilotEdit($file, 129, sub {
		my ($data) = @_;
		print "Reviving:\n";
		for my $p (@pers) {
			printf "  %4d - %s\n", $p->{ID}, $p->{Name};
			my $pos = $posPers + 2 * ($p->{ID} - 128);
			substr($data, $pos, 2) = pack('s>', 1);
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
	my ($file, $spec, $count) = @_;
	$count ||= 1;
	my $ship = findRes('ship' => $spec);

	my $vers = pilotVers($file);
	my %limits = pilotLimits($vers);

	pilotEdit($file, 128, sub {
		my ($data) = @_;

		my $added = 0;
		for my $i (0..$limits{escort} - 1) {
			my $pos = $limits{posEscort} + 2 * $i;
			my $val = unpack('s>', substr($data, $pos, 2));
			if ($added < $count && $val == -1) {
				# Found room
				$val = $ship->{ID} - 128;
				++$added;
			}
			substr($data, $pos, 2) = pack('s>', $val);
		}
		printf "Added %d %s as escort\n", $added, resName($ship);
		return $data;
	});
}

1;
