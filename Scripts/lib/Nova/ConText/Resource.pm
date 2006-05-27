# Copyright (c) 2006 Dave Vasilevsky

package Nova::ConText::Resource;
use strict;
use warnings;

use base 'Nova::Resource';

=head1 NAME

Nova::ConText::Resource - a resource from a ConText file

=cut

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
	$self->{cache} = $params{fields};
	$self->{fields} = ${$params{fields}};
	$self->readOnly($params{readOnly});
	
	$self->SUPER::init;
}

sub dumpField {
	# Prettier alternative to default method
	my ($self, $field) = @_;
	my $ret = eval { $self->{fields}{lc $field}->dump };
	return $@ ? $self->SUPER::dumpField($field) : $ret;
}

# Get/set the raw value of a field
sub _rawField {
	my ($self, $field, @etc) = @_;
	my $lc = lc $field;
	
	# Gotta be careful, with the damn hash pointer
	die "No such field '$field'\n" unless $self->hasField($field);
	if (@etc) {
		die "Read-only!\n" if $self->readOnly;
		my ($val) = @etc;
		unless (eval { $val->isa('Nova::ConText::Value') }) {
			$val = $self->{fields}{$lc}->new($val);	# keep the same type
		}
		$self->{fields}{$lc} = $val;
		$self->{modified} = 1;
	}
	return $self->{fields}{$lc}->value;
}

sub DESTROY {
	my ($self) = @_;
	if ($self->{modified}) {
		${$self->{cache}} = $self->{fields};
	}
}

# Do we have the given field?
sub hasField {
	my ($self, $field) = @_;
	return exists $self->{fields}{lc $field};
}

# Get the field names
sub fieldNames {
	my ($self) = @_;
	return @{$self->{fieldNames}};
}

# Hash with Nova::ConText::Value values.
sub typedFieldHash {
	my ($self) = @_;
	return %{$self->{fields}};
}


1;
