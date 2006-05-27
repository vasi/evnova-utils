# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Syst;
use strict;
use warnings;

use base qw(Nova::Base);
use Nova::Resource;

sub spobs {
	my ($self) = @_;
	return map { $self->collection->get(spob => $_) } $self->multi('nav');
}

sub importantBitFields { qw(Visibility) }

1;
