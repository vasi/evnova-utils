# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource;
use strict;
use warnings;

use Nova::Util qw(commaNum);

# Formatting methods for resources



# Show this object
sub show {
	my ($self, $verb, @fields) = @_;
	my $ret = sprintf "%d: %s\n", $self->ID, $self->fullName;
	
	# Override in subclasses
	$ret .= $self->showField($self, $_, $verb) for @fields;
	return $ret;
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

# Try to format a field by name. Return undef if cant.
sub formatByName {
	my ($self, $field, $verb) = @_;
	
	if ($field =~ /^Flags/) {
		return $self->formatFlagsField($field, $verb);
	} elsif ($field =~ /^(Contribute|Require)$/) {
		return $self->formatContribRequireField($field, $verb);
	} else {
		return undef;
	}
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

# Show a contrib/require field
sub formatContribRequireField {
	my ($self, $field, $verb) = @_;
	my $val = $self->$field;
	return '' if $verb < 2 && $val == 0;
	
	# Divide into four parts
	my @parts;
	for my $i (1..4) {
		($val, my $rem) = $val->bdiv(1 << 16);
		push @parts, $rem;
	}
	
	@parts = map { sprintf '%04x', $_ } reverse @parts;
	return '0x' . join(' ', @parts);
}

1;
