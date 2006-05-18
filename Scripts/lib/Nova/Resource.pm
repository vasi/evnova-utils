# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource;
use strict;
use warnings;

use base 'Nova::Base';
__PACKAGE__->fields(qw(collection readOnly));

use Nova::Util qw(deaccent commaNum);

use Storable;
use Carp;

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

# my $resource = Nova::Resource->new(%params);
#
# fieldNames is an array ref of field names
# fields points to the cache entry
# collection is the Resources object, for referral to other resources
# readOnly is true if we should be read-only
sub init {
	my ($self, %params) = @_;
	$self->{fieldNames} = $params{fieldNames};
	$self->collection($params{collection});
	$self->{fields} = $params{fields};
	$self->readOnly($params{readOnly});
	
	# Rebless, if necessary
	my $t = deaccent($self->type);
	if (exists $REGISTERED{$t}) {
		bless $self, $REGISTERED{$t};
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
sub dump {
	my ($self, @fields) = @_;
	@fields = $self->fieldNames unless @fields;
	
	my $dump = '';
	for my $field (@fields) {
		$dump .= sprintf "%s: %s\n", $field, $self->_raw_field($field)->dump;
	}
	return $dump;
}

# Pretty human-readable representation of this resource
sub show {
	my ($self, $verb) = @_;
	$self->dump();
}

# Get/set the raw Resource::Value of a field
sub _raw_field {
	my ($self, $field, $val) = @_;
	my $lc = lc $field;
	
	# Gotta be careful, with the damn hash pointer
	die "No such field '$field'\n" unless exists ${$self->{fields}}->{$lc};
	if (defined $val) {
		die "Read-only!\n" if $self->readOnly;
		
		my $valobj = ${$self->{fields}}->{$lc};
		$valobj = $valobj->new($val);	# keep the same type
		
		# update so that MLDBM notices
		my %fields = %${$self->{fields}};
		$fields{$lc} = $valobj;
		${$self->{fields}} = { %fields };
	}
	return ${$self->{fields}}->{$lc};
}

# Do we have the given field?
sub hasField {
	my ($self, $field) = @_;
	return exists ${$self->{fields}}->{lc $field};
}

# Eliminate warning on DESTROY
sub DESTROY { }

# $self->_caseInsensitiveMethod($subname);
#
# Find a method in the inheritance tree which equals the given name when
# case is ignored.
sub _caseInsensitiveMethod {
	my ($pkg, $sub) = @_;
	$pkg = ref($pkg) || $pkg;
	
	# Save the methods for each package we look at
	no strict 'refs';
	my $subs = \${"${pkg}::_SUBS"};
	unless (defined $$subs) {
		my %methods = $pkg->methods;
		$$subs->{lc $_} = $methods{$_} for keys %methods;
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
	confess "AUTOLOAD has no object!\n" unless ref($self);
	
	my $fullsub = our $AUTOLOAD;
	my ($pkg, $sub) = ($fullsub =~ /(.*)::(.*)/);
	
	# If we have a function with the same name (case-insensitive), use it!
	my $code = $self->_caseInsensitiveMethod($sub);
	unless (defined $code) {
		# Otherwise, create a new sub to get the field with the given name
		$code = sub {
			my ($self, @args) = @_;
			return $self->_raw_field($sub, @args)->value;
		};
	}
	
	# Insert the new method
	no strict 'refs';
	*$fullsub = $code;
	goto &$fullsub;
}

# Get/set a field
sub field {
	my ($self, $field, $val) = @_;
	return defined $val ? $self->$field($val) : $self->$field;
}

# Get the field names
sub fieldNames {
	my ($self) = @_;
	return @{$self->{fieldNames}};
}

# Get a hash of field names to values. Used for dumping.
sub fieldHash {
	my ($self) = @_;
	return %${$self->{fields}};
}

# Get a full name, suitable for printing
sub fullName {
	my ($self) = @_;
	return $self->name;
}

# The source file for this resource and friends
sub source { $_[0]->collection->source }

# my @props = $r->multi($prefix);
#
# Get a list of properties with the same prefix
sub multi {
	my ($self, $prefix) = @_;
	my @k = grep /^$prefix/i, $self->fieldNames;
	return grep { $_ != -1 && $_ != -2 } map { $self->$_ } @k;
}

# my @objs = $r->multiObjs($primary, @secondaries);
#
# Get a list of object-like hashes
sub multiObjs {
	my ($self, $primary, @secondaries) = @_;
	my @k = grep /^$primary/i, $self->fieldNames;
	@k = grep { my $v = $self->$_; $v != -1 && $v != 0 } @k;
	
	my @ret;
	for my $k (@k) {
		my %h;
		for my $v ($primary, @secondaries) {
			(my $kv = $k) =~ s/^$primary/$v/;
			$h{$v} = $self->$kv;
		}
		push @ret, \%h;
	}
	return @ret;
}

# Pretty print a field for output
sub format {
	my ($self, $field) = @_;
	my $meth = "format$field";
	my $code = $self->_caseInsensitiveMethod($meth);
	
	if (defined $code) {
		return $code->($self);
	} else {
		return $self->field($field);
	}
}

sub formatCost {
	my ($self) = @_;
	return commaNum($self->cost);
}

# Get info that is appropriate to display when ranking this object on the
# given field.
sub rankInfo {
	my ($self, $rankField) = @_;
	return '' unless $self->hasField('cost');
	return '' if lc $rankField eq 'cost';
	return $self->formatCost;
}

# Pre-calculated value
sub precalc {
	my ($self, $name, $code) = @_;
	return $self->collection->store($name) if $self->collection->store($name);
	
	my $file = Nova::Cache->storableCache($self->source, $name);
	my $cache = eval { retrieve $file };
	unless (defined $cache) {
		$cache = { };
		$code->($self, $cache);
		store $cache, $file;
	}
	return $self->collection->store($name => $cache);
}

sub govtObj {
	my ($self) = @_;
	require Nova::Resource::Type::Govt;
	return Nova::Resource::Type::Govt->fromCollection($self->collection,
		$self->govt);
}

# Load the subpackages
package Nova::Resource::Type;
use base qw(Nova::Base);
__PACKAGE__->subPackages;

1;
