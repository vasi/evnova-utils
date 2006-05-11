# Copyright (c) 2006 Dave Vasilevsky

package Nova::Base;
use strict;
use warnings;

=head1 NAME

Nova::Base - base class for EV Nova packages

=head1 SYNOPSIS

  package SubClass;
  use base 'Nova::Base';

  my $obj = SubClass->new(@params);

=head1 DESCRIPTION

Nova::Base provides basic object construction.

=cut

BEGIN {
	binmode STDOUT, ':utf8';
}

=head1 METHODS

=over 4

=item new

  my $obj = SubClass->new(@params);

Construct a new object.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $self = {};
	bless($self, $class);

	$self->_init(@_);

	return $self;
}

=item _init

  $obj->_init(@params);

Protected method.

Called by the constructor to initialize the object.

=cut

sub _init {
	# Intentionally left blank
}

=back

=cut

1;
