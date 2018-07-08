use warnings;
use strict;

use PQueue;

sub djikstra {
	my ($edgeSub, $start, %opts) = @_;

	my %seen;
	my $q = PQueue->new('min', [$start, undef], 0);

	while (my ($item, $cost) = $q->pop()) {
		last unless defined($item);

		my ($node, $prev) = @$item;
		next if $seen{$node};
		last if $opts{max} && $cost > $opts{max};

		$seen{$node} = { dist => $cost, prev => $prev };
		last if $opts{end} && $opts{end} eq $node;

		my %conns = $edgeSub->($node);
		while (my ($n, $c) = each %conns) {
			$q->push([$n, $node], $cost + $c);
		}
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

sub edgesSegment {
	my ($dist, $landingCost) = @_;
	my $systs = resource('syst');
	my $spobs = resource('spob');

	return sub {
		my $sid = shift;
		my %found = djikstra(edgesSyst(), $sid, max => $dist);

		my %inhabited;
		while (my ($k, $v) = each %found) {
			my $ok = 0;
			for my $nav (multiProps($systs->{$k}, 'nav')) {
				my $spob = $spobs->{$nav};
				if (~$spob->{Flags} & 0x20) {
					$ok = 1;
					last;
				}
			}

			$inhabited{$k} = $v->{dist} + $landingCost if $ok;
		}
		return %inhabited;
	};
}

1;
