use warnings;
use strict;

use List::Util qw(sum);

sub misc {
	my %fighters;
	for my $ship (values %{resource('ship')}) {
		my @items = shipDefaultItems($ship);
		my $fighters = sum(
			map { $_->{count} }
			grep {
				$_->{type} eq 'ammo' && findRes(weap => $_->{id})->{Guidance} == 99
			}
			@items
		);
		$fighters{$ship->{ID}} = $fighters;
	}
	listBuildSub(
		type => 'ship',
		value => sub { $fighters{$::r{ID}} },
		filter => sub { $fighters{$::r{ID}} },
	);
}

1;
