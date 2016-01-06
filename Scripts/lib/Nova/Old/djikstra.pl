use warnings;
use strict;

sub djikstra {
	my ($edgeSub, $start, %opts) = @_;

	my %seen;
	my @prios = ([[$start, undef]]);

	my $dist = 0;
	OUTER:
	while (@prios) {
		last if $opts{max} && $dist > $opts{max};

		my $items = $prios[$dist];
		if ($items) {
			for my $item (@$items) {
				my ($node, $prev) = @$item;
				next if $seen{$node};

				$seen{$node} = { dist => $dist, prev => $prev };
				last OUTER if $opts{end} && $opts{end} eq $node;

				my %conns = $edgeSub->($node);
				while (my ($n, $d) = each %conns) {
					push @{$prios[$dist + $d]}, [$n, $node];
				}
			}
			$prios[$dist] = undef;
		}
		$dist += 1;
	}

	return %seen;
}

sub djikstraDist {
	my ($edgeSub, $start, $end) = @_;
	my %seen = djikstra($edgeSub, $start, end => $end);
	return undef unless $seen{$end};
	return $seen{$end}{dist};
}

sub djikstraPath {
	my ($edgeSub, $start, $end) = @_;
	my %seen = djikstra($edgeSub, $start, end => $end);
	return undef unless $seen{$end};

	my @path = ($end);
	while ($path[-1] ne $start) {
		push @path, $seen{$path[-1]}{prev};
	}
	return reverse @path;
}

sub edgesSyst {
	my $systs = resource('syst');
	return sub {
		my $sid = shift;
		my $syst = $systs->{$sid};
		my @conns = multiProps($syst, 'con');
		return map { $_ => 1 } @conns;
	};
}

1;
