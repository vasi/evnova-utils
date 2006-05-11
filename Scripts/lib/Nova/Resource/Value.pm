# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource::Value;
use strict;
use warnings;

use base 'Nova::Base';

=head1 NAME

Nova::Resource::Value - A typed value in a resource

=head1 SYNOPSIS

  my $value = Nova::Resource::Value->fromString($str);
  my $dump = $value->dump;
  my $value = $value->value;

=cut

# my $value = Nova::Resource::Value->fromString($str);
#
# Parse a string to create a Value.
sub fromString {
	my ($class, $str) = @_;
	
	my ($subclass, @data) = (undef, $str);
	if ($str =~ /^"(.*)"$/) {
		($subclass, @data) = (String => $1);
	} elsif ($str =~ /^#(.*)$/) {
		($subclass, @data) = (Color => hex($1));
	} elsif ($str =~ /^0x(.*)$/) {
		($subclass, @data) = (Hex => hex($1), length($1));
	}
	$subclass = defined $subclass ? "${class}::$subclass" : $class;
	return $subclass->new(@data);
}

sub _init {
	my ($self, $val) = @_;
	$self->{val} = $val;
}

# Return the value as a scalar
sub value {
	my ($self) = @_;
	return $self->{val};
}

# Return the value in printable format
sub dump {
	my ($self) = @_;
	return $self->{val};
}


package Nova::Resource::Value::String;
use base 'Nova::Resource::Value';

sub _init {
	my ($self, $val) = @_;
	$self->SUPER::_init($val);
	
	# Fix escaped values
	$self->{val} =~ s/\\q/\"/g;
	$self->{val} =~ s/\\r/\n/g;
}


package Nova::Resource::Value::Hex;
use base 'Nova::Resource::Value';

sub _init {
	my ($self, $val, $length) = @_;
	$self->SUPER::_init($val);
	$self->{'length'} = $length;
}

sub dump {
	my ($self) = @_;
	return sprintf "0x%0*x", $self->{'length'}, $self->{val};
}


package Nova::Resource::Value::Color;
use base 'Nova::Resource::Value';

sub dump {
	my ($self) = @_;
	return sprintf "#%06x", $self->{val};
}


package Nova::Resource::Value::List;
use base 'Nova::Resource::Value';

sub _init {
	my ($self, @vals) = @_;
	$self->SUPER::_init(\@vals);
}

sub dump {
	my ($self) = @_;
	return "\n" . join('',
		map { sprintf "  %3d: %s\n", $_, $self->{val}[$_] }
		(0..$#{$self->{val}})
	);
}


1;
