# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource;
use strict;
use warnings;

use Storable;


# Common methods that aren't extremely important to the interface


# Textual representation of the given fields of this resource (or all fields,
# if none are specified).
sub dump {
	my ($self, @fields) = @_;
	@fields = $self->fieldNames unless @fields;
	
	my $dump = '';
	for my $field (@fields) {
		$dump .= sprintf "%s: %s\n", $field, $self->dumpField($field);
	}
	return $dump;
}

# The source file for this resource and friends
sub source { $_[0]->collection->source }

# my @props = $r->multi($prefix);
#
# Get a list of properties with the same prefix
sub multi {
	my ($self, $prefix) = @_;
	my @k = sort grep /^$prefix/i, $self->fieldNames;
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

sub _calcDefaults {
	my ($self) = @_;
	
	my $defaults = $self->symref('_DEFAULT_FIELDS');
	unless (defined $$defaults) {
		my %hash = $self->fieldDefaults;
		while (my ($k, $v) = each %hash) {
			$k = lc $k;
			my @d = ref($v) ? @$v : ($v);
			$$defaults->{lc $k} = {
				list	=> \@d,
				hash	=> { map { $_ => 1 } @d },
			};
		}
	}
	return $$defaults;
}

# Get the default values for a field. Returned as a hash-ref, where keys
# exist for only the defaults values.
sub fieldDefault {
	my ($self, $field) = @_;	
	
	my $defaults = $self->_calcDefaults;
	return { '' => 1 } unless exists $defaults->{lc $field};
	return $defaults->{lc $field}{hash};
}

# Get the defaults for all relevant fields
sub fieldDefaults {
	my ($self) = @_;
	return ();
	# Override in subclasses
}

# Return the value of a field, or undef if it's the default value
sub fieldDefined {
	my ($self, $field) = @_;
	my $defaults = $self->fieldDefault($field);
	my $val = $self->$field;
	return undef if exists $defaults->{$val};
	return $val;
}

# Defined earlier
our %TYPES;

# Return a hash of fields for a brand new object
sub newFieldHash {
	my ($class, $type, $id, @fields) = @_;	
	$class = $TYPES{deaccent($type)};
	
	my %hash;
	for my $field (@fields) {
		my $defaults = $class->_calcDefaults;
		my $val = exists $defaults->{lc $field}
			? $defaults->{lc $field}{list}[0] : '';
		$hash{$field} = $val;
	}
	$hash{type} = $type;
	$hash{id} = $id;
	
	return \%hash;
}

1;
