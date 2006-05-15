# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource;
use strict;
use warnings;

use base 'Nova::Base';
__PACKAGE__->fields(qw(collection));

use Nova::Util qw(deaccent);
use utf8;

=head1 NAME

Nova::Resource - a resource from a Nova data file

=head1 SYNOPSIS

  my $resource = Nova::Resource->new($fieldNames, \$fieldsHash, $collection);
  print $resource->dump;
  
  my $value = $resource->field("Flags");
  my $value = $resource->flags;

  # For subclasses
  Nova::Resource->register($package, @types);

=cut

our %REGISTERED;

# my $resource = Nova::Resource->new($fieldNames, $\fieldsHash, $collection);
#
# $fieldsHash points to the cache entry
# $collection is the Resources object, for referral to other resources
sub init {
	my ($self, $fieldNames, $fields, $collection) = @_;
	$self->{fieldNames} = $fieldNames;
	$self->collection($collection);
	$self->{fields} = $fields;
	
	# Rebless, if necessary
	if (exists $REGISTERED{$self->type}) {
		bless $self, $REGISTERED{$self->type};
	}
	return $self;
}

# Register a package to handle some types
sub register {
	my ($pkg, @types) = @_;
	$REGISTERED{$_} = $pkg for @types;
}

# Textual representation of the given fields of this resource (or all fields,
# if none are specified).
sub show {
	my ($self, @fields) = @_;
	@fields = $self->fieldNames unless @fields;
	
	my $dump = '';
	for my $field (@fields) {
		$dump .= sprintf "%s: %s\n", $field, $self->_raw_field($field)->show;
	}
	return $dump;
}

# Get/set the raw Resource::Value of a field
sub _raw_field {
	my ($self, $field, $val) = @_;
	my $lc = lc $field;
	
	# Gotta be careful, with the damn hash pointer
	die "No such field '$field'\n" unless exists ${$self->{fields}}->{$lc};
	if (defined $val) {
		my $valobj = {$self->{fields}}->{$lc};
		$valobj = $valobj->new($val);	# keep the same type
		
		# update so that MLDBM notices
		my %fields = %${$self->{fields}};
		$fields{$lc} = $valobj;
		${$self->{fields}} = { %fields };
	}
	return ${$self->{fields}}->{$lc};
}

# Eliminate warning on DESTROY
sub DESTROY { }

# $self->_caseInsensitiveMethod($subname);
#
# Find a method in the inheritance tree which equals the given name when
# case is ignored.
sub _caseInsensitiveMethod {
	my ($pkg, $sub) = @_;
	$pkg = ref $pkg || $pkg;
	
	# Save the methods for each package we look at
	no strict 'refs';
	my $subs = \${"${pkg}::_SUBS"};
	unless (defined $$subs) {
		$$subs->{lc $_} = \&{"${pkg}::$_"} for $pkg->methods;
	}
	if (exists $$subs->{lc $sub}) {
		return $$subs->{lc $sub};
	}
	
	# Try going up in the inheritance tree
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
		return $self->_raw_field($sub, @args)->value;
	}
}

# Get the field names
sub fieldNames {
	my ($self) = @_;
	return @{$self->{fieldNames}};
}

# Get a full name, suitable for printing
sub fullName {
	my ($self) = @_;
	return $self->name;
}


package Nova::Resource::Ship;
use base 'Nova::Resource';
__PACKAGE__->register('shïp');

# Add the subtitle to the full name, if it seems like a good idea
sub fullName {
	my ($self) = @_;
	my $name = $self->SUPER::fullName;
	my $sub = $self->subTitle;
	return $name unless $sub;
	return "$name, $sub";
}


1;
