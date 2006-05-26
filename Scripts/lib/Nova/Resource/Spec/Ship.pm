# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Spec::Ship;
use strict;
use warnings;

use base qw(Nova::Resource::Spec);
__PACKAGE__->fields(qw(type res neg));

=head1 NAME

Nova::Resource::Spec::Ship - A specification for a ship

=cut

sub init {
	my ($self, $resource, $field) = @_;
	$self->SUPER::init($resource, $field);
	
	my $spec = $self->spec;
	unless (grep { $spec == $_ } $self->default) {
		my $cat = int($spec / 1000);
		my $type = $cat <= 1 ? 'ship' : 'govt';
		
		my $id = $spec - $cat * 1000;
		my $res = $resource->collection->get($type => $id);
		my $neg = $cat % 2;
		
		$self->neg($neg);
		$self->res($res);
		$self->type($type);
	}
}

sub desc {
	my ($self) = @_;
	my $type = $self->type;
	return '' unless defined $type;
	
	my $desc = sprintf '%s (%d)', $self->res->fullName, $self->res->ID;
	my $not = $self->neg ? 'not ' : '';
	my $fmt = $type eq 'ship' ? '%sship %s' : 'ship %sof govt %s';
	return sprintf $fmt, $not, $desc;
}

sub ships {
	my ($self) = @_;
	my $type = $self->type;
	return $self->resource->collection->type('ship') unless defined $type;
	
	my $neg = $self->neg;
	return $self->res if $type eq 'ship' && !$neg; # shortcut
	
	my $field = $type eq 'ship' ? 'ID' : 'InherentGovt';
	my $id = $self->res->ID;
	return grep { ($_->field($field) == $id) ^ $neg }
		$self->resource->collection->type('ship');
}

sub default { return (-1, 0, 127) }

1;
