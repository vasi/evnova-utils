use warnings;
use strict;
use utf8;

sub pilotVers {
	my ($file) = @_;
	my $type = fileType($file) or return undef;

	my %vers = (
		'MpïL'	=> { game => 'classic',		key => 0xABCD1234 },
		'OpïL'	=> { game => 'override',	key => 0xABCD1234 },
		'NpïL'	=> { game => 'nova',		key => 0xB36A210F },
	);
	$vers{$type}{type} = $type;
	return $vers{$type};
}

sub simpleCrypt {
	my ($key, $data) = @_;
	my $size = length($data);

	my @longs = unpack 'L>*', $data;
	my $li = 0;
	for (my $i = int($size/4); $i > 0; $i--) {
		$longs[$li++] ^= $key;
		if ($key >= 0x21524110) { # no overflow
			$key -= 0x21524111;
		} else {
			$key += 0xDEADBEEF;
		}
		$key ^= 0xDEADBEEF;
	}
	my $ret = pack 'L>*', @longs;
	if ($size % 4) {
		my $end = substr $data, $size - $size % 4;
		my $lend = $end . chr(0) x 4;
		$key ^= unpack 'L>', $lend;
		my @bytes = unpack 'C*', $end;
		my $bi = 0;
		for (my $i = $size % 4; $i > 0; $i--) {
			$bytes[$bi++] = $key >> 24;
			$key &= 0xFFFFFF; # no overflow
			$key <<= 8;
		}
		$ret .= pack 'C*', @bytes;
	}
	return $ret;
}

sub pilotLimits {
	my ($pilot) = @_; # pilot or vers object

	my %l;
	if ($pilot->{game} eq 'nova') {
		%l = (
			cargo		=> 6,
			syst		=> 2048,
			outf		=> 512,
			weap		=> 256,
			misn		=> 16,
			bits		=> 10000,
			escort		=> 74,
			fighter 	=> 54,
			posBits		=> 0xb81e,
			spob		=> 2048,
			skipBeforeDef => 'true',
			pers		=> 1024,
			posCron     => 0x3590,
			cron        => 512,
		);
	} else {
		%l = (
			cargo		=> 6,
			syst		=> 1000,
			outf		=> 128,
			weap		=> 64,
			misn		=> 8,
			escort		=> 36,
			fighter 	=> 36,
			posBits		=> 0x1e7e,
			spob		=> 1500,
			pers		=> 512,
		);
		$l{bits} = $pilot->{game} eq 'override' ? 512 : 256;
	}
	$l{posExplore} = 2 * (7 + $l{cargo});
	$l{posOutf} = $l{posExplore} + 2 * $l{syst};
	$l{posLegal} = $l{posOutf} + 2 * $l{outf};
	$l{posWeap} = $l{posLegal} + 2 * $l{syst};
	$l{posCash} = $l{posWeap} + 2 * 2 * $l{weap};
	$l{posEscort} = $l{posBits} + $l{bits} + $l{spob};
	$l{posPers} = 4 + 2*$l{spob} + ($l{skipBeforeDef} ? 2 : 0);

	return %l;
}

sub pilotParsePlayer {
	my ($p, $r) = @_;
	my %limits = pilotLimits($p);
	$p->{limits} = \%limits;

	$p->{lastSpob} = readShort($r);
	$p->{ship} = readShort($r);
	$p->{cargo} = readSeq($r, \&readShort, $limits{cargo});
	readShort($r); # unused? val = 300
	$p->{fuel} = readShort($r);
	$p->{month} = readShort($r);
	$p->{day} = readShort($r);
	$p->{year} = readShort($r);
	$p->{date} = ParseDate(sprintf "%d-%d-%d", @$p{qw(year month day)});
	$p->{explore} = readSeq($r, \&readShort, $limits{syst});
	$p->{outf} = readSeq($r, \&readShort, $limits{outf});
	$p->{legal} = readSeq($r, \&readShort, $limits{syst});
	$p->{weap} = readSeq($r, \&readShort, $limits{weap});
	$p->{ammo} = readSeq($r, \&readShort, $limits{weap});
	$p->{cash} = readLong($r);

	my %misns;
	for my $i (0..$limits{misn}-1) {
		my %m;
		$m{active} = readChar($r);
		$m{travelDone} = readChar($r);
		$m{shipDone} = readChar($r);
		$m{failed} = readChar($r);
		$m{flags} = readShort($r) if $p->{game} eq 'nova';
		$m{limit} = readDate($r);
		$misns{$i} = \%m if $m{active};
	}
	for my $i (0..$limits{misn}-1) {
		my %m = parseMisnData($p, $r);
		@{$misns{$i}}{keys %m} = values %m if $misns{$i};
	}
	$p->{missions} = [ values %misns ];

	skipTo($r, $limits{posBits}); # unknown

	$p->{bit} = readSeq($r, \&readChar, $limits{bits});
	$p->{dominated} = readSeq($r, \&readChar, $limits{spob});

	for my $i (0..$limits{escort}-1) {
		my $v = readShort($r);
		next if $v == -1;
		if ($v >= 1000) {
			push @{$p->{hired}}, $v - 1000;
		} else {
			push @{$p->{captured}}, $v;
		}
	}
	for my $i (0..$limits{fighter}-1) {
		my $v = readShort($r);
		next if $v == -1;
		push @{$p->{fighter}}, $v;
	}

	skipTo($r, resourceLength($r) - 4);
	$p->{rating} = readLong($r);
}

sub parseMisnData {
	my ($p, $r) = @_;
	my %m;
	my $nova = ($p->{game} eq 'nova');

	$m{travelSpob} = readShort($r);
	readShort($r); # unused
	my @keys = (qw(returnSpob shipCount shipDude shipGoal shipBehavior),
		$nova ? qw(shipStart) : (),
		qw(shipSyst cargoType cargoQty pickupMode dropoffMode));
	for my $k (@keys) { $m{$k} = readShort($r); }
	if ($nova) {
		$m{scanMask} = readShort($r);
	} else {
		$m{scanGovt} = readShort($r);
		$m{compBits} = readSeq($r, \&readShort, 4);
	}
	for my $k (qw(compGovt compReward)) { $m{$k} = readShort($r); }
	if ($nova) {
		$m{datePostInc} = readShort($r);
		readShort($r); # unused
	} else {
		$m{failBits} = readSeq($r, \&readShort, 2);
	}
	$m{pay} = readLong($r);
	@keys = qw(Killed Boarded Disabled JumpedIn JumpedOut);
	for my $k (@keys) { $m{"ships$k"} = readShort($r); }
	$m{initialShips} = readShort($r);
	$m{failIfScanned} = readChar($r) unless $nova;
	$m{canAbort} = readChar($r);
	$m{cargoLoaded} = readChar($r);
	$nova ? readShort($r) : readChar($r); # padding
	@keys = qw(brief quickBrief loadCargo dropOffCargo comp fail refuse);
	push @keys, qw(shipDone) if $nova;
	for my $k (@keys) { $m{"${k}Text"} = readShort($r); }
	$m{timeLeft} = readShort($r);
	$m{shipNameRes} = readShort($r);
	$m{shipNameIdx} = readShort($r);
	readShort($r); # unused
	if ($nova) {
		$m{id} = readShort($r);
		$m{shipSubtitleRes} = readShort($r);
		$m{shipSubtitleIdx} = readShort($r);
		readShort($r); # unused
	} else {
		$m{shipDelay} = readShort($r);
		$m{id} = readShort($r);
	}
	$m{flags} = readShort($r);
	if ($nova) {
		$m{flags2} = readShort($r);
		readShort($r) for (1..4);
	}
	@keys = qw(Count Dude Syst JumpedIn Delay Left);
	for my $k (@keys) { $m{"aux$k"} = readShort($r); }
	$m{shipName} = readPString($r, $nova ? 63 : 31);
	if ($nova) {
		$m{shipSubtitle} = readPString($r, 63);
		skip($r, 255);
		@keys = qw(Accept Refuse Success Failure Abort ShipDone);
		for my $k (@keys) { $m{"on$k"} = readString($r,255); }
		$m{name} = readPString($r, 127);
		skip($r, 131);
	} else {
		$m{name} = readPString($r, 255);
	}
	return %m;
}

sub pilotParseGlobals {
	my ($p, $r) = @_;
	my %limits = pilotLimits($p);

	$p->{version} = readShort($r);
	$p->{strict} = readShort($r);
	readShort($r) if $limits{skipBeforeDef}; # unused?

	$p->{defense} = readSeq($r, \&readShort, $limits{spob});
	$p->{persAlive} = readSeq($r, \&readShort, $limits{pers});
	$p->{persGrudge} = readSeq($r, \&readShort, $limits{pers});

	if (exists $limits{posCron}) {
    	skipTo($r, $limits{posCron});
    	$p->{cronDurations} = readSeq($r, \&readShort, $limits{cron});
    	$p->{cronHoldoffs} = readSeq($r, \&readShort, $limits{cron});
	}
}

sub pilotParse {
	my ($file) = @_;
	my $vers = pilotVers($file);
	my ($player, $globals) = readResources($file,
		map { { type => $vers->{type}, id => $_ } } (128, 129));
	map { $_->{data} = simpleCrypt($vers->{key}, $_->{data}) }
		($player, $globals);

	my %pilot = (
		name		=> basename($file),
		shipName	=> $globals->{name},
		game		=> $vers->{game},
	);
	pilotParsePlayer(\%pilot, $player);
	pilotParseGlobals(\%pilot, $globals);
	return \%pilot;
}

1;
