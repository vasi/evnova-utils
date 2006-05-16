# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Syst;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('syst');

sub spobs {
	my ($self) = @_;
	return map { $self->collection->get(spob => $_) } $self->multi('nav');
}

1;
