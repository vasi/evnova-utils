use warnings;
use strict;

sub descOne {
	my ($res, $type, $trailing) = @_;

	my %dbase = (spob => 128, outf => 3000, misn => 4000, ship => 13000,
		hire => 14000, bar => 10000);
	my $base = $dbase{$type};

	my $descID = $base + $res->{ID} - 128;
	my $desc = findRes(desc => $descID);
	return 0 unless $desc->{Description};

	printf "\n" if $trailing;
	printf "%4d: %-20s -> %4s %5d\n", $res->{ID}, resName($res),
		$type, $descID;
	print_breaking($desc->{Description}, 1, '    ', '    ');
	return 1;
}

sub desc {
	my ($types, @finds) = @_;
	my @types = split ',', $types;

	my $t0 = $types[0];
	my %typemap = (hire => 'ship', bar => 'spob');
	my $rtype = $typemap{$t0} || $t0;

	my $trailing = 0;
	for my $res (findRes($rtype => \@finds)) {
		my $next = 0;
		for my $t (@types) {
			$next |= descOne($res, $t, $trailing);
			$trailing = 0 if $next;
		}
		$trailing = 1;
	}
}

sub descName {
	my ($d) = @_;
	my $id = $d->{ID};
	my ($type, $res);

	if ($id >= 128 && $id <= 2175) {
		($type, $res) = ('spob', 'spob');
	} elsif ($id >= 3000 && $id <= 3511) {
		($type, $res, $id) = ('outf', 'outf', $id - 3000 + 128);
	} elsif ($id >= 4000 && $id <= 4999) {
		($type, $res, $id) = ('misn', 'misn', $id - 4000 + 128);
	} elsif ($id >= 13000 && $id <= 13767) {
		($type, $res, $id) = ('ship buy', 'ship', $id - 13000 + 128);
	} elsif ($id >= 14000 && $id <= 14767) {
		($type, $res, $id) = ('ship hire', 'ship', $id - 14000 + 128);
	}

	if (defined $type) {
		my $r = findRes($res => $id);
		return sprintf "%d: %s %d - %s", $d->{ID}, $type, $id, resName($r);
	} else {
		return sprintf "%d: %s", $d->{ID}, resName($d);
	}
}

sub grepDescs {
	my ($re) = @_;
	$re = qr/$re/i;

	my $descs = resource('desc');
	for my $id (sort keys %$descs) {
		my $d = $descs->{$id};
		my $str = sprintf "%s\n%s\n", descName($d), $d->{Description};
		if ($str =~ /$re/) {
			print "$str\n";
		}
	}
}

1;
