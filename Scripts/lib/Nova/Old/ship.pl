use warnings;
use strict;

use utf8;

sub shipRank {
	my @fields = @_;
	my @names = map { $fields[2 * $_] } (0..$#fields/2);
	my %weights = @fields;
	my %ne1 = map { ($weights{$_} == 1) ? () : ($_, $weights{$_}) }
		keys %weights;

	# Calculate ranks
	my (%rank, %lengths);
	my $ships = resource('ship');
	while (my ($id, $ship) = each %$ships) {
		my $sum = 0;
		while (my ($k, $weight) = each %weights) {
			my $v = $ship->{$k};
			$sum += $weight * $v;
			push @{$lengths{$k}}, length $v;
		}

		$rank{$id} = $sum;
		push @{$lengths{Sum}}, length int($sum);
		push @{$lengths{Cost}}, length commaNum($ship->{Cost} / 1000);
		push @{$lengths{Name}}, length resName($ship);
	}

	# Generate format string for each row
	my %flen = map { $_ => max @{$lengths{$_}} } keys %lengths;
	my (@fmts, @hdrs);
	for my $k (@names) {
		push @fmts, "%$flen{$k}d";
	}
	my $vfmt = "%$flen{Sum}d:   " . join('   ', @fmts);
	my $fmt = $vfmt . "   %-$flen{Name}s %4d  %$flen{Cost}sK\n";

	# Print headers
	my @hpos;
	for my $i (0..$#names) {
		my $sent = 123456789012;
		my @vs = (0) x (1 + @names);
		$vs[1 + $i] = $sent;
		my $tmpl = sprintf $vfmt, @vs;
		push @hpos, index $tmpl, $sent;
	}
	my $hdrs = '';
	for my $i (0..$#names) {
		my $h = $hpos[$i];
		$hdrs = sprintf "%-*.*s", $h, $h, $hdrs;
		if ($i < $#names) {
			my $l = $hpos[$i + 1] - $h - 1;
			substr($hdrs, $h, $l) = sprintf "%-*.*s", $l, $l, $names[$i];
		} else {
			substr($hdrs, $h, 0) = $names[$i];
		}
	}
	printf "%s\n", $hdrs;

	# Print rows
	my $sort = sub { $rank{$b} <=> $rank{$a} || $a <=> $b };
	for my $id (sort { $sort->() } keys %$ships) {
		my $ship = $ships->{$id};
		my @vals = map { $ship->{$_} } @names;
		printf $fmt, $rank{$id}, @vals, resName($ship), $id,
			commaNum($ship->{Cost} / 1000);
	}
}

sub defense {
	my ($arm) = @_;
	shipRank(Shield => 1, Armor => $arm // 1);
}
sub agility {
	my ($acc, $man) = @_;
	shipRank(Speed => 1, Accel => $acc // 0.02, Maneuver => $man // 1);
}

sub whereShip {
	my ($find, $max) = @_;
	$max = 20 unless defined $max;
	my $ship = findRes(ship => $find);

	my %dudes;
	my $dudes = resource('dude');
	for my $dude (values %$dudes) {
		for my $kt (grep /^ShipTypes\d+/, keys %$dude) {
			(my $kp = $kt) =~ s/ShipTypes(\d+)/Probs$1/;
			my ($vt, $vp) = map { $dude->{$_} } ($kt, $kp);
			next if $vt != $ship->{ID};
			$dudes{$dude->{ID}} += $vp;
		}
	}

	my %systs;
	my $systs = resource('syst');
	for my $syst (values %$systs) {
		my $prob = 0;
		for my $kt (grep /^DudeTypes\d+/, keys %$syst) {
			(my $kp = $kt) =~ s/DudeTypes(\d+)/Probs$1/;
			my ($vt, $vp) = map { $syst->{$_} } ($kt, $kp);
			next unless $dudes{$vt};
			$prob += ($vp / 100) * $dudes{$vt};
		}
		$systs{$syst->{ID}} = 100 - 100*(1-($prob/100))**($syst->{AvgShips});
	}

	my $count = 0;
	printf "Systems with %s (%d):\n", resName($ship), $ship->{ID};
	for my $sid (sort { $systs{$b} <=> $systs{$a} } keys %systs) {
		last if $systs{$sid} == 0;

		my $syst = $systs->{$sid};
		my ($govt) = findRes(govt => $syst->{Govt});
		printf "%6.2f %% - %4d: %-20s %2d  %s\n", $systs{$sid}, $sid,
			$syst->{Name}, $syst->{AvgShips}, govtName($govt);
		last if $count++ >= $max;
	}
}

sub shieldRegen {
	my ($rezFile, $remod, $smod, @fields) = @_;
	$remod ||= 0;
	$smod ||= 0;

	my $ships = resource('ship');

	# Read resource files
	my @rezSpecs = map { { type => 'shïp', id => $_ } } keys %$ships;
	my @rez = readResources($rezFile, @rezSpecs);
	my $pos = 0x10; # Position of ShieldRe in resource

	# Find rechard data
	my (%shieldre, %rate);
	for my $rez (@rez) {
		my $id = $rez->{id};
		my $ship = $ships->{$id};

		$shieldre{$id} = unpack('S>', substr($rez->{data}, $pos, 2));

		# In hundredths of shield point per second
		my $re = $shieldre{$id} - $remod;
		$re = 1 if $re < 1;

		my $shield = $ship->{Shield} + $smod;
		$rate{$id} = int($shield * 30 / $re);
	}

    rankHeaders('ShieldRe', @fields);
	listBuildSub(type => 'ship',
		value => sub { $rate{$::r{ID}} },
		filter => sub { exists $rate{$::r{ID}} },
        print => sub { $shieldre{$::r{ID}}, @::r{@fields} },
	);
}

1;
