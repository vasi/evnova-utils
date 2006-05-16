# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Spob;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('spob');

sub syst {
	my ($self) = @_;
	for my $syst ($self->collection->type('syst')) {
		for my $spob ($syst->spobs) {
			return $syst if $spob->ID == $self->ID;
		}
	}
	die "No system found!\n";
}

1;
