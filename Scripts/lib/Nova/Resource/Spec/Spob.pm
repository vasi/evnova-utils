# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Spec::Spob;
use strict;
use warnings;

use base qw(Nova::Resource::Spec);
__PACKAGE__->fields(qw(spobs desc));

=head1 NAME

Nova::Resource::Spec::Spob - A specification for a spob

=cut

sub init {
	my ($self, @args) = @_;
	$self->SUPER::init(@args);
	
	my $spob = $self->collection->get(spob => $self->spec);
	my $syst = $spob->syst;
	$self->desc(sprintf "%s (%d) in %s (%d)", $spob->name, $spob->ID,
		$syst->name, $syst->ID);
}

1;
