# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource::Field;
use strict;
use warnings;

use base 'Nova::Base';

=head1 NAME

Nova::Resource::Value - A field with key and value

=head1 SYNOPSIS

  # $value is a Nova::Resource::Value
  my $field = Nova::Field::Value->new($key, $value);
  my $dump = $value->dump;
  my $key = $value->key;
  my $scalar = $value->value;

=cut

sub _init {
	my ($self, $key, $value) = @_;
	$self->{key} = $key;
	$self->{value} = $value;
}

# Return the value as a scalar
sub value {
	my ($self) = @_;
	return $self->{value}->value;
}

# Return the key-
sub key {
	my ($self) = @_;
	return $self->{key};
}

# Return a printable representation
sub dump {
	my ($self) = @_;
	return sprintf "%s: %s", $self->{key}, $self->{value}->dump;
}

1;
