# Copyright (c) 2006 Dave Vasilevsky

package Nova::ConText::Type;
use strict;
use warnings;

use base 'Nova::Base';
__PACKAGE__->fields(qw(type resFields));

use Nova::Resource;
use Nova::Resource::Value;

use utf8;

=head1 NAME

Nova::ConText::Type - Deal with type-specific information about resources in
ConText format.

=head1 SYNOPSIS

  my $type = Nova::ConText::Type->new($type);

  my @resFields = $type->inFieldNames(@rawFields);
  my %fields = $type->inFields(@vals);

  my @rawFields = $type->outFieldNames(@resFields);
  my @vals = $type->outFields(%fields);

=cut

our %REGISTERED;

sub init {
	my ($self, $type) = @_;
	$self->type($type);
	
	if (exists $REGISTERED{$self->type}) {
		bless $self, $REGISTERED{$self->type}; # rebless
	}
}

# Get the field names which should be used, given the ones read from the ConText
sub inFieldNames {
	my ($self, @rawFields) = @_;
	return $self->resFields(\@rawFields);
}

# Get a hash of fields, given the values to be used for each field name
sub inFields {
	my ($self, @vals) = @_;
	return map { lc ($self->resFields->[$_]) => $vals[$_] } (0..$#vals);
}

# Get the field names to output to ConText, given the fields in a resource
sub outFieldNames {
	my ($self, @resFields) = @_;
	return $self->resFields(\@resFields);
}

# Get the field values to output, given a hash of fields
sub outFields {
	my ($self, %fields) = @_;
	return map { $fields{lc $_} } @{$self->resFields};
}

# $pkg->register($type);
#
# Register an alternative package to handle the given type.
sub register {
	my ($pkg, $type) = @_;
	$Nova::ConText::Type::REGISTERED{$type} = $pkg;
}


package Nova::ConText::Type::StringList;
use base 'Nova::ConText::Type';
__PACKAGE__->register('STR#');

sub inFields {
	my ($self, @vals) = @_;
	my @strings = splice @vals, $#{$self->resFields};
	@strings = map { $_->value } @strings;
	push @vals, Nova::Resource::Value::List->new(@strings);
	
	return $self->SUPER::inFields(@vals);
}

sub outFields {
	my ($self, %fields) = @_;
	my @vals = $self->SUPER::outFields(%fields);
	my $strs = pop @vals;
	my @strs = map { Nova::Resource::Value::String->new($_) } @{$strs->value};
	return (@vals, @strs);
}


package Nova::ConText::Type::Syst;
use base 'Nova::ConText::Type';
__PACKAGE__->register('sÿst');

# Mis-spelled field
sub inFieldNames {
	my ($self, @fields) = @_;
	@fields = map { s/Visiblility/Visibility/ } @fields;
	$self->SUPER::inFieldNames(@fields);
}


package Nova::ConText::Type::Outf;
use base 'Nova::ConText::Type';
__PACKAGE__->register('oütf');

# Some things need to be hex
sub inFields {
	my ($self, @vals) = @_;
	my %fields = $self->SUPER::inFields(@vals);
	
	my %forceHex = map { $_ => 1 } (17, 30, 43);
	
	for my $modtype (grep /^ModType/, keys %fields) {
		next unless $forceHex{$fields{$modtype}->value};
		(my $modval = $modtype) =~ s/ModType/ModVal/;
		my $val = $fields{$modval}->value;
		$fields{$modval} = Nova::Resource::Value::Hex->new($val, 4);
	}
	
	return %fields;
}


package Nova::ConText::Type::Rank;
use base 'Nova::ConText::Type';
__PACKAGE__->register('ränk');

# Missing some values in ConText!
sub inFields {
	my ($self, @vals) = @_;
	push @vals, ('') x 2;
	$self->SUPER::inFields(@vals);
}


1;
