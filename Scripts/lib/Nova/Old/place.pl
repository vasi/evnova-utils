use warnings;
use strict;

{
	my $cache;

	sub spobSyst {
		my ($spobid) = @_;

		unless (defined $cache) {
			my $cacheFile = File::Spec->catfile(
				contextCache(), '.spobSyst');
			my $inited = -f $cacheFile;

			$cache = tieHash($cacheFile);

			unless ($inited) {
				my $systs = resource('syst');

				for my $systid (sort keys %$systs) {
					my $syst = $systs->{$systid};
					for my $knav (grep /^nav/, keys %$syst) {
						my $nav = $syst->{$knav};
						next if $nav == -1;
						$cache->{$nav} = $syst->{ID};
					}
				}
			}
		}

		my $systid = $cache->{$spobid};
		return findRes(syst => $systid) if defined $systid;
		die "Can't find syst for spob $spobid\n";
	}
}

sub refSpobSyst {
	my ($ref, $spob) = @_;
	return $ref->{spobSyst}{$spob} if exists $ref->{spobSyst}{$spob};
	return spobSyst($spob, sub {
		$ref->{spobSyst}{$_[1]} = $_[0]->{ID}
			unless defined $ref->{spobSyst}{$_[1]}
	})->{ID};
}


sub spobsMatching {
	my ($p) = @_;

	if ($p == -1 || $p == -2) {
		return map { $_->{ID} }	grep { !($_->{Flags} & 0x20) }
			values %{resource('spob')};
	} else {
		return itemsMatching(spob => $p);
	}
}

sub systsMatching {
	my ($p) = @_;

	if ($p == -1 || $p == -32000) {
		return keys %{resource('syst')};
	} else {
		return itemsMatching(syst => $p);
	}
}

sub systsSelect {
	my ($ref, $p) = @_;
	my ($type) = keys %$p;
	my $id = $p->{$type};

	unless (exists $ref->{systsSelect}{$type}{$id}) {
		if ($type eq 'spob') {
			if ($id >= 5000 && $id <= 7047) {
				return systsSelect($ref, {adjacent => $id - 5000 + 128})
			}
			my @spobs = spobsMatching($id);
			$ref->{systsSelect}{$type}{$id} = [
                map { eval { refSpobSyst($ref, $_) } } @spobs ];
		} elsif ($type eq 'syst') {
			$ref->{systsSelect}{$type}{$id} = [ $id ];
		} elsif ($type eq 'adjacent') {
			$ref->{syst} ||= resource('syst');
			my @systs = systsSelect($ref, { syst => $id });
			my %matches;
			for my $systid (@systs) {
				my $syst = $ref->{syst}{$systid};
				my @kcon = grep /^con/, keys %$syst;
				my @con = map { $syst->{$_} } @kcon;
				@con = grep { $_ != -1 } @con;
				$matches{$_} = 1 for @con;
			}
			my @matches = keys %matches;
			$ref->{systsSelect}{$type}{$id} = [ @matches ];
		} else {
			die "Don't know what to do for type $type\n";
		}
	}
	return @{$ref->{systsSelect}{$type}{$id}}
}

sub placeSpec {
    my $spec = shift;
    my $type = shift @$spec;

    my ($ptype, $stype, $add, $val) = ('syst', undef, 0, undef);
    if ($type eq 'govt') {
        ($ptype, $stype, $add) = ('spob', 'govt', 10000 - 128);
    } elsif ($type eq 'ally') {
        ($ptype, $stype, $add) = ('spob', 'govt', 15000 - 128);
    } elsif ($type eq 'ngovt') {
        ($ptype, $stype, $add) = ('spob', 'govt', 20000 - 128);
    } elsif ($type eq 'enemy') {
        ($ptype, $stype, $add) = ('spob', 'govt', 25000 - 128);
    } elsif ($type eq 'adjacent') {
        ($ptype, $stype) = ('adjacent', 'syst');
    } elsif ($type eq 'spob') {
        ($ptype, $stype) = ('spob', 'spob');
    } elsif ($type eq 'syst') {
        ($stype) = ('syst');
    } else {
        ($stype, $val) = ('syst', $type);
    }

    $val //= shift @$spec;
    my $res = $stype ? findRes($stype => $val)->{ID} : $val;
    return { $ptype => $res + $add };
}


sub govtsMatching {
	my ($spec) = @_;
	memoize_complex($spec, sub {
		die "Not a govt spec\n" if $spec < 9999 || $spec >= 31000;
		my $cat = int(($spec + 1) / 1000);
		my $id = $spec - 1000 * $cat + 128;
		$id = -1 if $id == 127;

		my @govts;
		if ($cat == 10) {
			@govts = ($id);
		} elsif ($cat == 20) {
			@govts = grep { $_ != $id } (keys %{resource('govt')});
		} elsif ($cat == 15 || $cat == 25) {
			my $govt = findRes(govt => $id);
			my $str = $cat == 15 ? "Allies" : "Enemies";
			my @kt = grep /^$str\d/, keys %$govt;
			my @vt = map { $govt->{$_} } @kt;
			@govts = map { $_ + 128 } grep { $_ != -1 } @vt;
		} else {
			die "Don't know what to do about govt spec $spec\n";
		}
		my %govts = map { $_ => 1 } @govts;
		return \%govts;
	});
}

sub itemsMatching {
	my ($type, $spec) = @_;
	memoize_complex($type, $spec, sub {
		if ($spec >= 128 && $spec <= 2175) {
			return ($spec);
		} elsif ($spec >= 9999 && $spec < 31000)  {
			my $res = resource($type);
			my $govts = govtsMatching($spec);
			my @items = grep { $govts->{$_->{Govt}} } values %$res;
			my @ids = map { $_->{ID} } @items;
			return @ids;
		} else {
			die "Don't know what to do with spec $spec\n";
		}
	});
}

sub printSpobSyst {
	my ($find) = @_;
	my $spob = findRes(spob => $find);
	my $syst = spobSyst($spob->{ID});
	printf "%d: %s\n", $syst->{ID}, $syst->{Name};
}

sub systCanLand {
    my ($syst) = @_;
    for my $spobid (multiProps($syst, 'nav')) {
        my $spob = findRes(spob => $spobid);
        return 1 if $spob->{Flags} & 0x1    # can land here
            && !($spob->{Flags2} & 0x3000); # not a wormhole or hypergate
    }
    return 0;
}

sub hiddenSpobs {
	for my $syst (values %{resource('syst')}) {
		my %spobs;
		my @spobids = multiProps($syst, 'nav');
		for my $spobid (@spobids) {
			my $spob = findRes(spob => $spobid);
			my ($x, $y) = @$spob{'xPos', 'yPos'};
			push @{$spobs{$x,$y}}, $spob;
		}
		for my $loc (keys %spobs) {
			my @spobs = @{$spobs{$loc}};
			next unless scalar(@spobs) > 1;
			printf "%4d: %s\n", $syst->{ID}, $syst->{Name};
			printf "      %4d: %s\n", $_->{ID}, $_->{Name} for @spobs;
		}
	}
}

1;
