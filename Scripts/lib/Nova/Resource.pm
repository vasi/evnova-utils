# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource;
use strict;
use warnings;

use base 'Nova::Base';
use Nova::Util qw(deaccent);

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
	my ($self, @fields) = @_;
	$self->{ordered} = \@fields;
	$self->{byname} = { map { lc($_->key) => $_ } @fields };
	$self->{type} = $self->_raw('type');
	
	# Rebless, if necessary
	if (exists $REGISTERED{$self->type}) {
		bless $self, $REGISTERED{$self->type};
		print $self->{type}, "\n";
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
	@fields = $self->allFields unless @fields;
	
	my $dump = '';
	for my $field (@fields) {
		$field = lc $field;
		die "No such field $field\n" unless exists $self->{byname}{$field};
		$dump .= $self->{byname}{$field}->dump . "\n";
	}
	return $dump;
}

# The un-accented type of this resource
sub type {
	my ($self) = @_;
	return $self->{type};
}

# List all fields of this resource
sub allFields {
	my ($self) = @_;
	return map { $_->key } @{$self->{ordered}};
}

# Get the raw value of a field
sub _raw {
	my ($self, $field) = @_;
	$field = lc $field;
	die "No such field $field\n" unless exists $self->{byname}{$field};
	return $self->{byname}{$field}->value;
}

# Get a single field
sub field {
	my ($self, $field) = @_;
	$self->$field();
}

# Eliminate warning on DESTROY
sub DESTROY { }

# Trickery to allow case-insensitive methods
{
	no strict 'refs';
	while (my ($k, $v) = each %{__PACKAGE__ . '::'}) {
		next if $k =~ /::/ or $k eq '_temp'; # sub-modules
		*_temp = $v;
		next unless defined &_temp;
		$SUBS{lc $k} = *_temp{CODE};
	}
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


package Nova::Resource::Ship;
use base 'Nova::Resource';
Nova::Resource->register(__PACKAGE__, 'ship');

sub name {
	my ($self) = @_;
	my $name = $self->SUPER::name;
	my $sub = $self->subTitle;
	return $name unless $sub;
	return "$name, $sub";
}


1;
