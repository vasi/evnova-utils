# Copyright (c) 2006 Dave Vasilevsky

package Nova::ConText::Type;
use strict;
use warnings;

use base 'Nova::Base';

use Nova::Resource;
use Nova::Resource::Value;
use Nova::Util qw(deaccent);

use utf8;

=head1 NAME

Nova::ConText::Type - parse resources of a given type from a ConText file

=head1 SYNOPSIS

  my $reader = Nova::ConText::Type->new($type);
  my @resources = $reader->headers($line);
  my @resources = $reader->resource($line);
  
  Nova::ConText::Type->register($type, $package);

=cut

our %REGISTERED;

sub new {
	my ($class, $type) = @_;
	if ($class eq __PACKAGE__ && exists $REGISTERED{$type}) {
		return $REGISTERED{$type}->new($type);
	} else {
		return $class->SUPER::new($type);
	}
}

sub _init {
	my ($self, $type) = @_;
	$self->{type} = $type;
}

# my @fields = $class->_parseLine($line);
#
# Parse a line into values
sub _parseLine {
	my ($class, $line) = @_;
	my @items = split /\t/, $line;
	my @fields = map { Nova::Resource::Value->fromString($_) } @items;
	return @fields;
}

# my $headers = $reader->headers($line);
#
# Parse the headers of this type.
sub headers {
	my ($self, $line) = @_;
	my @values = $self->_parseLine($line);
	pop @values while $values[-1]->value eq 'EOR';
	
	my @headers = map { $_->value } @values;	# stringify
	my %seen;
	@headers = grep { !$seen{$_}++ } @headers;	# uniquify
	
	$self->{headers} = \@headers;
	return $self->{headers};
}

# my $valuesHash = $reader->_mapping($headers, $valuesList);
#
# Map the values to headers
sub _mapping {
	my ($self, $headers, $values) = @_;
	die "Different number of headers and fields\n"
		unless scalar(@$headers) == scalar(@$values);
	return { map { lc $headers->[$_] => $values->[$_] } (0..$#$values) };
}

# my $resource = $reader->resource($line);
#
# Parse a resource of this type, return as a hash of fields.
sub resource {
	my ($self, $line) = @_;
	my @values = $self->_parseLine($line);
	
	# stop if no record
	return undef unless @values;
	$values[0] = Nova::Resource::Value->new(deaccent($values[0]->value));
	return undef unless $values[0]->value eq $self->{type};
	
	pop @values while $values[-1]->value eq '•'; # end-of-record
	
	my $valuesHash = $self->_mapping($self->{headers}, \@values);
	return $valuesHash;
}

# Nova::ConText::Type->register($type, $package);
#
# Register an alternative package to handle the given type.
sub register {
	my ($class, $type, $package) = @_;
	$REGISTERED{$type} = $package;
}


package Nova::ConText::Type::StringList;
use base 'Nova::ConText::Type';
Nova::ConText::Type->register('str#', __PACKAGE__);

sub _mapping {
	my ($self, $headers, $values) = @_;
	my @strings = splice @$values, $#$headers;
	@strings = map { $_->value } @strings;
	push @$values, Nova::Resource::Value::List->new(@strings);
	
	return $self->SUPER::_mapping($headers, $values);
}


package Nova::ConText::Type::Syst;
use base 'Nova::ConText::Type';
Nova::ConText::Type->register('syst', __PACKAGE__);

# Mis-spelled field
sub _headers {
	my ($self, @args) = @_;
	$self->SUPER::headers(@args);
	map { s/visiblility/visibility/ } @{$self->{headers}};
	return $self->{headers};
}


package Nova::ConText::Type::Outf;
use base 'Nova::ConText::Type';
Nova::ConText::Type->register('outf', __PACKAGE__);

# Some things need to be hex
sub _mapping {
	my ($self, $headers, $values) = @_;
	my $hash = $self->SUPER::_mapping($headers, $values);
	
	my %forceHex = map { $_ => 1 } (17, 30, 43);
	
	for my $modtype (grep /^modtype/, keys %$hash) {
		next unless $forceHex{$hash->{$modtype}->value};
		(my $modval = $modtype) =~ s/modtype/modval/;
		my $val = $hash->{$modval}->value;
		$hash->{$modval} = Nova::Resource::Value::Hex->new($val, 4);
	}
	
	return $hash;
}


1;
