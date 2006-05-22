# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Syst;
use strict;
use warnings;

use base qw(Nova::Base);
use Nova::Resource;
Nova::Resource->registerType('syst');

sub spobs {
	my ($self) = @_;
	return map { $self->collection->get(spob => $_) } $self->multi('nav');
}

1;
