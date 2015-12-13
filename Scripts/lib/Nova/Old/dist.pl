use warnings;
use strict;

sub placeDist {
	my ($ref, $p1, $p2) = @_;
	return placeDist($ref, $p2, $p1) if $p1 > $p2;

	my $key = freeze [ $p1, $p2 ];
	unless (exists $ref->{placeDist}{$key}) {
		my @s1 = systsSelect($ref, $p1);
		my @s2 = systsSelect($ref, $p2);

		my $max = 0;
		my $min = 1e6;
		for my $s1 (@s1) {
			for my $s2 (@s2) {
				my $dist = refSystDist($ref, $s1, $s2);
				$max = $dist if $dist > $max;
				$min = $dist if $dist < $min;
			}
		}

		my $ret;
		if ($min == $max) {
			$ret = $min;
		} elsif ($max < 2) {
			$ret = $max;
		} elsif ($min <= 2) {
			$ret = 2;
		} else {
			$ret = $min;
		}
		$ref->{placeDist}{$key} = $ret;
	}
	return $ref->{placeDist}{$key};
}

# FIXME: Pretends that each pair of places is independent, when of course
# each intermediate place must remain the same in the next pair.
sub placeListDist {
	my ($ref, @places) = @_;

	my $jump = 0;
	for (my $i = 0; $i < $#places; ++$i) {
		my $src = $places[$i];
		my $dst = $places[$i+1];
		$jump += placeDist($ref, $src, $dst);
	}
	return $jump;
}

sub misnDist {
	my ($ref, $misn) = @_;
	die "Can't do pers-missions yet\n" if $misn->{AvailLoc} == 2;
	my $land = 0;

	my $avail = $misn->{AvailStel};
	my $travel = $misn->{TravelStel};
	my $return = $misn->{ReturnStel};
	$return = $avail if $return == -4;

	my @places = ({ spob => $avail });

	my $shipsyst = $misn->{ShipSyst};
	my $shipgoal = $misn->{ShipGoal};
	if (grep { $shipgoal == $_ } (0, 1, 2, 4, 5, 6)) {
		my %misnSysts = (-1 => $avail, -3 => $travel, -4 => $return);
		if (exists $misnSysts{$shipsyst}) {
			push @places, { spob => $misnSysts{$shipsyst} };
		} elsif ($shipsyst == -5) {
			push @places, { adjacent => $avail };
		} else {
			push @places, { syst => $shipsyst };
		}
	}

	if ($travel != -1) {
		push @places, { spob => $travel };
		$land++;
	}
	if ($return != -1) {
		push @places, { spob => $return };
		$land++;
	}

	return ($land, placeListDist($ref, @places));
}

sub djikstra {
	my ($systs, $s1, $s2, %opts) = @_;
	my $cachefun = $opts{cache};
	my $debug = $opts{debug};
	my $type = $opts{type} || 'path';	# 'dist' or 'path'
										# 'dist' assumes total coverage

	if ($s1 == $s2) {
		return $type eq 'path' ? ($s1, $s2) : 0;
	}

	my %seen = ( $s1 => undef );
	my %new = %seen;
	my $dist = 0;
	my $found;
    my $path = sub {
        my $cur = shift;
        my @path;
        while (defined($cur)) {
            unshift @path, $cur;
            $cur = $seen{$cur};
        }
        return @path;
    };

	while (1) {
		$dist++;

		my @edge = keys %new;
		%new = ();
		for my $systid (@edge) {
			my $syst = $systs->{$systid};
			print "Looking at $syst->{ID}: $syst->{Name}\n" if $debug;
			for my $kcon (grep /^con/, keys %$syst) {
				my $con = $syst->{$kcon};
				next if $con == -1;

				unless (exists $seen{$con}) {
					print "Adding $con\n" if $debug;
					$seen{$con} = $systid;
					$cachefun->($s1, $con, $dist) if $cachefun;
					$new{$con} = 1;

                    my @path;
                    if ($type eq 'path' && ($cachefun || $con == $s2)) {
                        @path = $path->($con);
                    }
                    $cachefun->($s1, $con, \@path) if $cachefun && @path;

					if ($con == $s2) {
						$found = $dist;
						return @path if $type eq 'path';
					}
				}
			}
		}

		last unless %new;
	}

	die "Can't find connection between $s1 and $s2\n" unless defined $found;
	return $found;
}

sub systDist {
	return memoize(@_, sub {
		my ($memo, $s1, $s2) = @_;
		return djikstra(resource('syst'), $s1, $s2, type => 'dist',
			cache => sub { $memo->(@_); $memo->(@_[1,0,2]) });
	});
}

sub systPath {
	return memoize_complex(@_, sub {
		my ($memo, $s1, $s2) = @_;
		return djikstra(resource('syst'), $s1, $s2, type => 'path',
			cache => sub { $memo->(@_); $memo->(@_[1,0,2]) });
	});
}

sub spobDist {
	return memoize(@_, sub {
		my ($memo, $s1, $s2) = @_;
		return systDist(spobSyst($s1)->{ID}, spobSyst($s2)->{ID});
	});
}

sub refSystDist {
	my ($ref, $s1, $s2) = @_;
	return 0 if $s1 == $s2;
	return $ref->{systDist}{$s1}{$s2} if exists $ref->{systDist}{$s1}{$s2};

	# Djikstra
	djikstra($ref->{syst}, $s1, $s2, type => 'dist',
		cache => sub {
			$ref->{systDist}{$_[0]}{$_[1]} = $ref->{systDist}{$_[1]}{$_[0]}
				= $_[2];
		}
	);

	return $ref->{systDist}{$s1}{$s2};
}

sub showPlaceDist {
    my $ref = { syst => resource('syst') };
	my @s1 = systsSelect($ref, placeSpec(\@_));
	my @s2 = systsSelect($ref, placeSpec(\@_));
    my @best = ();

    for my $s1 (@s1) {
        for my $s2 (@s2) {
            my @path = systPath($s1, $s2);
            @best = @path if !@best || scalar(@path) < scalar(@best);
        }
    }
    printPath(@best);
}

sub printPath {
    my @path = @_;
    my $systs = resource('syst');

	printf "Distance: %d\n", scalar(@path) - 1;
	for (my $i = 0; $i <= $#path; ++$i) {
		printf "%2d: %s\n", $i, $systs->{$path[$i]}{Name};
	}
}

sub showDist {
	my @searches = @_;
	my $systs = resource('syst');

	my ($p1, $p2) = map { findRes(syst => $_)->{ID} } @searches;
	my @path = djikstra($systs, $p1, $p2, type => 'path');
	printPath(@path);
}

sub limitMisns {
	my $misns = resource('misn');

	my $ref;
	my $cache = File::Spec->catfile(contextCache(), 'dist');
	if (-f $cache) {	# FIXME: Check out-of-date?
		$ref = retrieve($cache);
	} else {
		$ref = { map { $_ => resource($_) } qw(spob syst govt) };
	}

	my @limited;
	for my $misnid (sort keys %$misns) {
		my $misn = $misns->{$misnid};
		my $limit = $misn->{TimeLimit};
		next if $limit == -1 || $limit == 0;

		my ($land, $jump);
		eval { ($land, $jump) = misnDist($ref, $misn) };
		if ($@) {
			print "WARNING: $misnid: $@";
		} else {
			my $jumpdays = 100;
			$jumpdays = ($limit - $land) / $jump unless $jump == 0;
			push @limited, {
				limit	=> $limit,
				land	=> $land,
				jump	=> $jump,
				jumpdays => $jumpdays,
				misn	=> $misn
			};
		}
	}

	for my $h (sort { $b->{jumpdays} <=> $a->{jumpdays} } @limited) {
		my $m = $h->{misn};
		printf "Days: %6.2f  Time: %3d  Land: %d  Jump: %2d   %4d: %s\n",
			@$h{qw(jumpdays limit land jump)}, @$m{qw(ID Name)};
	}
	nstore $ref, $cache;
}

1;
