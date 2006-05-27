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

sub showDist {
	my ($self, $other, $verb) = @_;
	
	printf "Distance: %d\n", $self->dist($other);
	
	# FIXME: show path
}

sub dist {
	my ($self, $other) = @_;
	

}

1;
