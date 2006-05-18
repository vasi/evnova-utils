# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Spob;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('spob');

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

1;
