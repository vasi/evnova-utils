use warnings;
use strict;

sub pilotItems {
    my ($pilot) = @_;
    my $outfs = $pilot->{outf};

    my @items;
    for my $i (0..$#$outfs) {
        my $count = $outfs->[$i];
        next if $count == 0 || $count == -1;
        push @items, { type => 'outfit', id => $i + 128, count => $count };
    }
    return @items;
}

sub sellable {
    my ($file) = @_;
    my $pilot = pilotParse($file);
    my @items = pilotItems($pilot);
    my $outfs = resource('outf');

    my @sellable;
    for my $item (@items) {
        my $outf = $outfs->{$item->{id}};
        next if $outf->{Flags} & 0xC; # persistent or can't sell

        my $count = $item->{count};
        push @sellable, { outf => $outf, count => $count,
            cost => $outf->{Cost} * $count };
    }

    for my $s (sort { $b->{cost} <=> $a->{cost} } @sellable) {
        my $outf = $s->{outf};
        printf "%12s: %-20s * %3d (%3d)\n", commaNum($s->{cost}),
            resName($outf), $s->{count}, $outf->{ID};
    }
}

sub rating {
	my ($pilot) = @_;

	my %ratings = allRatings();
	my ($myRating, $myKills) = myRating($pilot);
	for my $kills (sort { $a <=> $b } keys %ratings) {
		my $k = commaNum($kills);
		my $r = $ratings{$kills};
		if ($kills == $myRating) {
			printf "%7s: %s    <== %s\n", $k, $r, ratingStr($myKills);
		} else {
			printf "%7s: %s\n", $k, $r;
		}
	}
}

sub allRatings {
	my $strs = resource('STR#');
	my @ratings = @{$strs->{138}{Strings}};
	my @kills = (0, 1, 100, 200, 400, 800, 1600, 3200, 6400, 12_800, 25_600);
	return map { $kills[$_] => $ratings[$_] } (0..$#ratings);
}

sub ratingStr {
	my ($rating) = @_;
	my %ratings = allRatings();
	my ($cat) = grep { $_ <= $rating } sort { $b <=> $a } keys %ratings;
	my $str = ($rating == $cat) ? $ratings{$cat}
		: sprintf "%s + %s", $ratings{$cat}, commaNum($rating - $cat);
	return sprintf "%s (%s)", commaNum($rating), $str;
}

sub myRating {
	my ($pilot) = @_;

	my $mine;
	if (defined $pilot) {
		$mine = pilotParse($pilot)->{rating};
	} else {
		$mine = readPilotLog()->{Kills};
	}
	my %ratings = allRatings;
	my ($r) = grep { $_ <= $mine } sort { $b <=> $a } keys %ratings;
	return wantarray ? ($r, $mine) : $ratings{$r};
}

sub pilotHex {
	my ($file) = @_;
	my $vers = pilotVers($file);

	my ($player, $globals) = readResources($file,
		map { { type => $vers->{type}, id => $_ } } (128, 129));

	print $globals->{name}, "\n";
	print "\nPLAYER:\n";
	hexdump(simpleCrypt($vers->{key}, $player->{data}));
	print "\nGLOBALS:\n";
	hexdump(simpleCrypt($vers->{key}, $globals->{data}));
}

sub pilotDump {
	my ($in, $rid, $out) = @_;

	# pilot -> data
	my $vers = pilotVers($in);
	if ($vers) {
    	my ($res) = readResources($in, { type => $vers->{type}, id => $rid });
    	my $data = simpleCrypt($vers->{key}, $res->{data});
    	open my $fh, '>', $out;
    	print $fh $data;
    	close $fh;
    	return;
	}

    # data -> pilot
	$vers = pilotVers($out);
	die "No valid pilot file!\n" unless $vers;
	my $data;
	{
	    local $RS; # slurp
	    open my $fh, '<', $in;
	    $data = <$fh>;
	    close $fh;
	}
	$data = simpleCrypt($vers->{key}, $data);
	writeResources($out, { type => $vers->{type}, id => $rid, data => $data });
}

sub unexplored {
	my ($pilotFile, @govtSpecs) = @_;
	my $pilot = pilotParse($pilotFile);

	my %govtids = map { $_->{ID} => 1 } findRes(govt => \@govtSpecs);
	for my $spec (@govtSpecs) {
		$govtids{-1} = 1 if $spec eq '-1' || $spec eq '127' || lc($spec) eq 'independent';
	}

	my $systs = resource('syst');
	for my $id (sort keys %$systs) {
		my $syst = $systs->{$id};
		next unless $govtids{$syst->{Govt}};

		my $str = pilotPrintExplored($pilot, $syst, $pilot->{explore}[$id - 128]);
		print "$str\n" if $str;
	}
}

1;
