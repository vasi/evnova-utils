# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Spec;
use strict;
use warnings;

use base qw(Nova::Base);
__PACKAGE__->fields(qw(resource field spec));

=head1 NAME

Nova::Resource::Spec - A specification for a type of resource

=cut

sub init {
	my ($self, $resource, $field) = @_;
	$self->resource($resource);
	$self->field($field);
	$self->spec($resource->$field);
}

sub collection { $_[0]->resource->collection }


# Is this spec the default?
sub default {
	my ($self) = @_;
	return $self->spec == -1;
}

sub dump {
	my ($self, $verb) = @_;
	return '' if !$verb && $self->default;
	return sprintf "%s: %s\n", $self->field, $self->desc;
}

1;
