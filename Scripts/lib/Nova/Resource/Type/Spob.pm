# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Spob;
use strict;
use warnings;

use base qw(Nova::Base);
use Nova::Resource;
Nova::Resource->registerType('spob');

use Nova::Resource::Commodity;
use Nova::Columns;


sub _spobSystCache {
	$_[0]->precalc(spobSyst => sub {
		my ($self, $cache) = @_;
		for my $syst (reverse $self->collection->type('syst')) {
			for my $spob ($syst->spobs) {
				$cache->{$spob->ID} = $syst->ID;
			}
		}
	});
}

sub syst {
	my ($self) = @_;
	return $self->collection->get(syst => $self->_spobSystCache->{$self->ID});
}

sub importantBitFields { qw(OnDominate OnDestroy) }

sub commodities {
	my ($self) = @_;
	my @ret;
	
	# Standard commodities
	my %standardPrices = (1 => 'low', 2 => 'med', 4 => 'high');
	my $flags = $self->flags;
	for my $i (1..6) {
		my $shift = 4 * (8 - $i);
		my $val = ($flags >> $shift) & 0xF;
		next unless $val;
		
		push @ret, Nova::Resource::Commodity::Standard
			->new($self->collection, $i - 1)->priced($standardPrices{$val});
	}
	
	# Junks
	my %junkPrices = (bought => 'high', sold => 'low');
	for my $junk ($self->collection->type('junk')) {
		while (my ($field, $price) = each %junkPrices) {
			my @spobs = $junk->$field;
			if (grep { $_->ID == $self->ID } @spobs) {
				push @ret, $junk->priced($price);
			}
		}
	}
	return @ret;
}

sub displayCommodities {
	my ($self) = @_;
	print $self->header;
	columns('  %s: %d %s', [ $self->commodities ],
		sub { $_->fullName, $_->price, substr $_->priceLevel, 0, 1 });
}


package Nova::Resource::DefenseFleet;
use base qw(Nova::Base);
# FIXME

1;
