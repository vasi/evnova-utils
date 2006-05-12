# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource;
use strict;
use warnings;

use base 'Nova::Base';
use Nova::Util qw(deaccent methods);

=head1 NAME

Nova::Resource - a resource from a Nova data file

=head1 SYNOPSIS

  my $resource = Nova::Resource->new(@fields);
  print $resource->dump;
  
  my $value = $resource->field("Flags");
  my $value = $resource->flags;

  # For subclasses
  Nova::Resource->register($package, @types);

=cut

our %SUBS;
our %REGISTERED;

sub _init {
	my $self = shift;
	@$self{qw(fields headers collection)} = @_;
	$self->{type} = $self->{fields}{type}->value;
	
	# Rebless, if necessary
	if (exists $REGISTERED{$self->type}) {
		bless $self, $REGISTERED{$self->type};
	}
	return $self;
}

# Register a package to handle some types
sub register {
	my ($package, @types) = @_;
	$REGISTERED{$_} = $package for @types;
}

# Textual representation of the given fields of this resource (or all fields,
# if none are specified).
sub dump {
	my ($self, @fields) = @_;
	@fields = $self->headers unless @fields;
	
	my $dump = '';
	for my $field (@fields) {
		die "No such field $field\n" unless exists $self->{fields}{lc $field};
		$dump .= sprintf "%s: %s\n", $field, $self->{fields}{lc $field}->dump;
	}
	return $dump;
}

# The un-accented type of this resource
sub type {
	my ($self) = @_;
	return $self->{type};
}

# Get the raw value of a field
sub _raw {
	my ($self, $field) = @_;
	$field = lc $field;
	die "No such field $field\n" unless exists $self->{fields}{$field};
	return $self->{fields}{$field}->value;
}

# Get the collection
sub collection {
	my ($self) = @_;
	return $self->{collection};
}

# Eliminate warning on DESTROY
sub DESTROY { }

# Trickery to allow case-insensitive methods
{
	no strict 'refs';
	$SUBS{lc $_} = \&{__PACKAGE__ . "::$_"} for methods(__PACKAGE__);
}

sub AUTOLOAD {
	my ($self, @args) = @_;
	my $sub = our $AUTOLOAD;
	$sub =~ s/.*:://;
	$sub = lc $sub;
	
	if (exists $SUBS{$sub}) {
		# Try to call an existing sub with the same name (case-insensitive)
		$SUBS{$sub}($self, @args);
	} else {
		# Otherwise, get the field with that name
		return $self->_raw($sub);
	}
}

# Get the headers (field names)
sub headers {
	my ($self) = @_;
	return @{$self->{headers}};
}

# Get a single field
sub field {
	my ($self, $field) = @_;
	$self->$field();
}



package Nova::Resource::Ship;
use base 'Nova::Resource';
Nova::Resource->register(__PACKAGE__, 'ship');

sub fullName {
	my ($self) = @_;
	my $name = $self->name;
	my $sub = $self->subTitle;
	return $name unless $sub;
	return "$name, $sub";
}


1;
