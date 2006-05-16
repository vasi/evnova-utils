# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Spec::Spob;
use strict;
use warnings;

use base qw(Nova::Resource::Spec);
__PACKAGE__->fields(qw(spobs desc));

=head1 NAME

Nova::Resource::Spec::Spob - A specification for a spob

=cut

our %REGISTERED;
sub register {
	my ($class, $type) = @_;
	$REGISTERED{$type} = $class;
}
__PACKAGE__->register(0);


sub init {
	my ($self, @args) = @_;
	$self->SUPER::init(@args);
	
	my $spec = $self->spec;
	
}


1;
