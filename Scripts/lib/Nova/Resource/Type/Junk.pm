# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Junk;
use strict;
use warnings;

use base qw(Nova::Base Nova::Resource::Commodity);
use Nova::Resource;
Nova::Resource->registerType('junk');

sub shortName {
	my ($self, @args) = @_;
	return $self->abbrev(@args);
}

sub sold {
	my ($self) = @_;
	my @ids = $self->multi('SoldAt');
	return map { $self->collection->get(spob => $_) } @ids;
}

sub bought {
	my ($self) = @_;
	my @ids = $self->multi('BoughtAt');
	return map { $self->collection->get(spob => $_) } @ids;
}

1;
