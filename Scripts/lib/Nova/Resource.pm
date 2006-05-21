# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource;
use strict;
use warnings;

use base 'Nova::Base';
__PACKAGE__->fields(qw(collection readOnly));

use Nova::Util qw(deaccent commaNum);

use Scalar::Util qw(blessed);
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

# Register a package to handle some type
sub register {
	my ($pkg, $type) = @_;
	$REGISTERED{deaccent($type)} = $pkg;
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

# Check if we have a field
sub _has_field {
	my ($self, $field) = @_;
	return exists ${$self->{fields}}->{lc $field};
}

# Get/set the raw Resource::Value of a field
sub _raw_field {
	my ($self, $field, $val) = @_;
	my $lc = lc $field;
	
	# Gotta be careful, with the damn hash pointer
	die "No such field '$field'\n" unless $self->_has_field($field);
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
	
	# Save the methods for each package we look at
	my $subs = $pkg->symref('_CASE_INSENSITIVE_SUBS');
	unless (defined $$subs) {
		my %methods = $pkg->methods;
		$$subs->{lc $_} = $methods{$_} for keys %methods;
	}
	if (exists $$subs->{lc $sub}) {
		return $$subs->{lc $sub};
	}
	
	# Try going up in the inheritance tree
	for my $base (@{$pkg->symref('ISA')}) {
		if ($base->can('_caseInsensitiveMethod')) {
			return $base->_caseInsensitiveMethod($sub);
		}
	}
	return undef;
}

sub can {
	my ($self, $meth) = @_;
	my $code = $self->_caseInsensitiveMethod($meth);
	return $code if defined $code;
	
	# Can't test for field presence without a blessed object!
	return undef unless blessed $self;
	return undef unless $self->_has_field($meth);
	return sub {
		my ($self, @args) = @_;
		$self->_raw_field($meth, @args)->value;
	};
}

sub AUTOLOAD {
	my ($self, @args) = @_;
	my $fullsub = our $AUTOLOAD;
	my ($pkg, $sub) = ($fullsub =~ /(.*)::(.*)/);
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

# Get info that is appropriate to display when ranking this object on the
# given field.
sub rankInfo {
	my ($self, $rankField) = @_;
	return '' unless $self->hasField('cost');
	return '' if lc $rankField eq 'cost';
	return $self->formatCost;
}

# Wrapper for methods using precalculation optimization
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

# The object representing the govt (if applicable)
sub govtObj {
	my ($self) = @_;
	require Nova::Resource::Type::Govt;
	return Nova::Resource::Type::Govt->fromCollection($self->collection,
		$self->govt);
}

# Show this object
sub show {
	my ($self, $verb) = @_;
	return sprintf "%d: %s\n", $self->ID, $self->fullName;
	# Override in subclasses
}

# Format the contents of field
sub format {
	my ($self, $field, $verb) = @_;
	
	# Try by special function
	my $meth = "format$field";
	return $self->$meth($field, $verb) if $self->can($meth);
	
	# Try by name
	my $ret = $self->formatByName($field, $verb);
	return $ret if defined $ret;
	
	# Default display
	my $val = $self->fieldDefined($field);
	return defined $val ? $val : '';
}

sub formatCost {
	my ($self) = @_;
	return commaNum($self->cost);
}


# Format the name and contents of a field
sub showField {
	my ($self, $field, $verb) = @_;
	
	# Try by special function
	my $meth = "show$field";
	return $self->$meth($field, $verb) if $self->can($meth);
	
	# Try by name
	my $ret = $self->showByName($field, $verb);
	return $ret if defined $ret;
	
	# Use format instead
	my $val = $self->format($field, $verb);
	if ($val eq '' && $verb < 2) {
		return '';
	} else {
		return "$field: $val\n";
	}
}

sub showByName { return undef }

# Try to format a field by name. Return undef if cant.
sub formatByName {
	my ($self, $field, $verb) = @_;
	
	if ($field =~ /^Flags/) {
		return $self->formatFlagsField($field, $verb);
	} else {
		return undef;
	}
	# Override in subclasses
}

# Get the default values for a field. Returned as a hash-ref, where keys
# exist for only the defaults values.
sub fieldDefault {
	my ($self, $field) = @_;	
	
	my $defaults = $self->symref('_DEFAULT_FIELDS');
	unless (defined $$defaults) {
		my %hash = $self->fieldDefaults;
		while (my ($k, $v) = each %hash) {
			my @d = ref($v) ? @$v : ($v);
			$$defaults->{lc $k}{$_} = $1 for @d;
		}
	}
	
	return { '' => 1 } unless exists $$defaults->{lc $field};
	return $$defaults->{lc $field}
}

# Get the defaults for all relevant fields
sub fieldDefaults {
	my ($self) = @_;
	return ();
	# Override in subclasses
}

# Show a flags field
sub formatFlagsField {
	my ($self, $field, $verb) = @_;
	my @on = $self->flagsOn($field);
	
	if ($verb > 2) {
		return 'none' unless @on;
		return join '', map { "\n  $_" } @on;
	} elsif (@on) {
		return join(', ', @on);
	} else {
		return '';
	}
}

# Register some new flags
sub flagInfo {
	my $pkg = shift;
	my $field = shift;
	my @flags = @_;
	my $bit = 0;
	
	my @texts;
	while (@flags) {
		(my ($funcName, $text), @flags) = @flags;
		push @texts, $text;
		
		my $mask = 1 << $bit++;
		$pkg->makeSub($funcName => sub { $_[0]->$field & $mask });
	}
	$pkg->symref('FLAG_FIELDS')->{lc $field} = \@texts;
}

# Get the names of the flags that are on
sub flagsOn {
	my ($self, $field) = @_;
	my $val = $self->$field;
	
	my $pkg = ref($self) || $self;
	my $flagFields = $pkg->symref('FLAG_FIELDS');
	die "No such field '$field'\n" unless exists $flagFields->{lc $field};
	my $flags = $flagFields->{lc $field};
	
	my @on;
	for my $i (0..$#$flags) {
		my $mask = 1 << $i;
		next unless $val & $mask;
		push @on, $flags->[$i];
	}
	return @on;
}

# Return the value of a field, or undef if it's the default value
sub fieldDefined {
	my ($self, $field) = @_;
	my $defaults = $self->fieldDefault($field);
	my $val = $self->$field;
	return undef if exists $defaults->{$val};
	return $val;
}

# Load the subpackages
package Nova::Resource::Type;
use base qw(Nova::Base);
__PACKAGE__->subPackages;

1;
