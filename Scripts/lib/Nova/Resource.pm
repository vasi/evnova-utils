# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource;
use strict;
use warnings;

use base 'Nova::Base';
use Nova::Util qw(deaccent methods);
use utf8;

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

our %REGISTERED;

sub _init {
	my ($self, $fields, $headers, $collection, $realType) = @_;
	$self->{headers} = $headers;
	$self->{collection} = $collection;
	$self->{fields} = {
		map { lc $headers->[$_] => $fields->[$_] } (0..$#$fields)
	};
	$self->{type} = $self->{fields}{type}->value;
	$self->{realType} = $realType;
	
	# Rebless, if necessary
	if (exists $REGISTERED{$self->type}) {
		bless $self, $REGISTERED{$self->type};
	}
	return $self;
}

# Register a package to handle some types
sub register {
	my ($class, $package, @types) = @_;
	$REGISTERED{$_} = $package for @types;
}

# Textual representation of the given fields of this resource (or all fields,
# if none are specified).
sub show {
	my ($self, @fields) = @_;
	@fields = $self->headers unless @fields;
	
	my $dump = '';
	for my $field (@fields) {
		die "No such field $field\n" unless exists $self->{fields}{lc $field};
		$dump .= sprintf "%s: %s\n", $field, $self->{fields}{lc $field}->show;
	}
	return $dump;
}

# Dump a line in ConText format
sub dump {
	my ($self) = @_;
	
	my @fields;
	for my $field ($self->headers) {
		my $field = lc $field;
		if ($field eq 'type') {
			push @fields, $self->{realType};
		} else {
			push @fields, $self->{fields}{$field}->dump;
		}
	}
	push @fields, '"•"';
	return join(' ', @fields);
}

# The un-accented type of this resource
sub type { $_[0]->{type} }

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

sub _caseInsensitiveMethod {
	my ($pkg, $sub) = @_;
	$pkg = ref $pkg || $pkg;
	
	no strict 'refs';
	my $subs = \${"${pkg}::_SUBS"};
	unless (defined $$subs) {
		$$subs->{lc $_} = \&{"${pkg}::$_"} for methods($pkg);
	}
	if (exists $$subs->{lc $sub}) {
		return $$subs->{lc $sub};
	}
	
	for my $base (@{"${pkg}::ISA"}) {
		if ($base->can('_caseInsensitiveMethod')) {
			return $base->_caseInsensitiveMethod($sub);
		}
	}
	return undef;
}

sub AUTOLOAD {
	my ($self, @args) = @_;
	my $fullsub = our $AUTOLOAD;
	my ($pkg, $sub) = ($fullsub =~ /(.*)::(.*)/);
	
	my $code = $self->_caseInsensitiveMethod($sub);
	if (defined $code) {
		# Try to call an existing sub with the same name (case-insensitive)
		$code->($self, @args);
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

sub fullName {
	my ($self) = @_;
	return $self->name;
}


package Nova::Resource::Ship;
use base 'Nova::Resource';
Nova::Resource->register(__PACKAGE__, 'ship');

sub fullName {
	my ($self) = @_;
	my $name = $self->SUPER::fullName;
	my $sub = $self->subTitle;
	return $name unless $sub;
	return "$name, $sub";
}


1;
