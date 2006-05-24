# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource;
use strict;
use warnings;

use base qw(Nova::Base Exporter);
__PACKAGE__->fields(qw(collection readOnly));

our @EXPORT = qw(flagInfo);

use Nova::Util qw(deaccent);
use Scalar::Util qw(blessed);
use NEXT;

=head1 NAME

Nova::Resource - a resource from a Nova data file

=head1 SYNOPSIS

  # Get a resource from a Nova::Resources object
  my $res = $collection->get($type => $id);
  my $res2 = $res->duplicate($newID);


  # Properties
  my $collection = $res->collection;
  my $isReadOnly = $res->readOnly;
  
  # Get fields by string or by method. Set as well.
  my $value = $res->field("Flags");
  my $value = $res->flags;
  $res->flags(0xBEEF);
  
  # Get info about the fields
  my $bool = $res->hasField($field);
  my $hashref = $res->fieldHash;
  my @fields = $res->fieldNames;


  # For specific types
  __PACKAGE__->register($type);


  # Subclasses should implement at least:
  - Constructor
  - _rawField
  - fieldNames

=cut

our %TYPES;
	
# Should call at *end* of subclass init.
sub init {
	my ($self) = @_;
	
	# Rebless, if necessary
	my $t = deaccent($self->type);
	if (exists $TYPES{$t}) {
		$self->mixin($TYPES{$t});
	}
	return $self;
}


# Register a package to handle some type
sub registerType {
	my ($class, $type) = @_;
	my $pkg = caller;
	$TYPES{deaccent($type)} = $pkg;
}

#### Interface
#
# Get/set the value of a field (without doing the AUTOLOAD messiness)
# sub _rawField { }
#
# Get the field names
# sub fieldNames { }

# Do we have the given field?
sub hasField {
	my ($self, $field) = @_;
	
	# Inefficient default
	return grep { lc $_ eq lc $field } $self->fieldNames;
}

# Get a hash of field names to values. Keys should be in lower-case.
sub fieldHash {
	my ($self) = @_;
	
	# Inefficient default
	my %hash;
	for my $field ($self->fieldNames) {
		$hash{lc $field} = $self->$field;
	}
	return %hash;
}

# Dump a given field's value
sub dumpField {
	my ($self, $field) = @_;
	
	# Imperfect default
	return $self->$field;
}


# $self->_caseInsensitiveMethod($subname);
#
# Find a method in the inheritance tree which equals the given name when
# case is ignored.
sub _caseInsensitiveMethod {
	my ($pkg, $sub) = @_;
	$pkg = ref($pkg) || $pkg;
	
	# Save the methods for each package we look at
	my $subs;
	{	no strict 'refs'; # ->symref is too expensive
		$subs = \${"${pkg}::_CASE_INSENSITIVE_SUBS}"}; 
	}
	unless (defined $$subs) {
		$$subs = { };
		my %methods = $pkg->methods;
		$$subs->{lc $_} = $methods{$_} for keys %methods;
	}
	if (exists $$subs->{lc $sub}) {
		return $$subs->{lc $sub};
	}
	
	# Try going up in the inheritance tree
	for my $base (@{$pkg->symref('ISA')}) {
		my $code;
		eval { $code = _caseInsensitiveMethod($base, $sub) };
		return ($$subs->{lc $sub} = $code) if defined $code; # cache
	}
	
	return ($$subs->{lc $sub} = undef);
}

sub can {
	my ($self, $meth) = @_;
	my $code = $self->_caseInsensitiveMethod($meth);
	return $code if defined $code;
	
	# Can't test for field presence without a blessed object!
	return undef unless blessed $self;
	return undef unless $self->hasField($meth);
	return sub {
		my ($self, @args) = @_;
		$self->_rawField($meth, @args);
	};
}

sub AUTOLOAD {
	my ($self, @args) = @_;
	my $fullsub = our $AUTOLOAD;
	my ($pkg, $sub) = ($fullsub =~ /(.*)::(.*)/);
	return if $sub eq 'DESTROY';
	
	my $code = $self->can($sub);
	die "No such method '$sub'\n" unless defined $code;
	goto &$code;
	
	# We can't use the insert-and-goto trick, since it interferes with
	# overriding methods.
}

# Get/set a field
sub field {
	my ($self, $field, $val) = @_;
	return defined $val ? $self->$field($val) : $self->$field;
}

# Create a clone of this resource, at a different ID
sub duplicate {
	my ($self, $id) = @_;
	$id = $self->collection->nextUnused($self->type) unless defined $id;
	
	my %fields = $self->fieldHash;
	$fields{id} = $id;
	return $self->collection->addResource(\%fields);
}


# Load the categories and types
__PACKAGE__->subPackages('Nova::Resource::Category');
__PACKAGE__->subPackages('Nova::Resource::Type');

1;
