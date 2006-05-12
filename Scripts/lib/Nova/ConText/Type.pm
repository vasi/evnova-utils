# Copyright (c) 2006 Dave Vasilevsky

package Nova::ConText::Type;
use strict;
use warnings;

use base 'Nova::Base';

use Nova::Resource;
use Nova::Resource::Value;
use Nova::Util qw(deaccent);
use Data::Dumper;

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

sub _init {
	my ($self, $type) = @_;
	$self->{realType} = $type;
	$self->{type} = deaccent($type);
	$self->{resources} = [ ];
	
	if (exists $REGISTERED{$self->type}) {
		bless $self, $REGISTERED{$self->type}; # rebless
	}
}

sub type 		{ $_[0]->{type}		}
sub realType	{ $_[0]->{realType} }

# my @fields = $class->_parseLine($line);
#
# Parse a line into values
sub _parseLine {
	my ($class, $line) = @_;
	my @items = split /\t/, $line;
	my @fields = map { Nova::Resource::Value->fromString($_) } @items;
	return @fields;
}

# $reader->readHeaders($line);
#
# Parse the headers of this type.
sub readHeaders {
	my ($self, $line) = @_;
	my @values = $self->_parseLine($line);
	pop @values while $values[-1]->value eq 'EOR';
	
	my @headers = map { $_->value } @values;	# stringify
	my %seen;
	@headers = grep { !$seen{$_}++ } @headers;	# uniquify
	
	$self->{headers} = \@headers;
}

# my $valuesHash = $reader->_mapping($headers, $valuesList);
#
# Map the values to headers
sub _mapping {
	my ($self, $headers, $values) = @_;
	unless (scalar(@$headers) == scalar(@$values)) {
		print Dumper($headers, $values);
		die "Different number of headers and fields\n";
	}
	return { map { $headers->[$_] => $values->[$_] } (0..$#$values) };
}

# my $resource = $reader->readResource($line);
#
# Parse a resource of this type, return as a hash of fields.
sub readResource {
	my ($self, $line) = @_;
	my @values = $self->_parseLine($line);
	
	# stop if no record
	return undef unless @values;
	$values[0] = Nova::Resource::Value->new(deaccent($values[0]->value));
	return undef unless $values[0]->value eq $self->{type};
	
	pop @values while $values[-1]->value eq '•'; # end-of-record
	
	my $valuesHash = $self->_mapping($self->{headers}, \@values);
	push @{$self->{resources}}, $valuesHash;
}

# Nova::ConText::Type->register($type, $package);
#
# Register an alternative package to handle the given type.
sub register {
	my ($class, $type, $package) = @_;
	$REGISTERED{$type} = $package;
}

# List of hashes representing resources
sub resourceHashes {
	my ($self) = @_;
	return @{$self->{resources}};
}

# Headers (columns) of this type
sub headers {
	my ($self) = @_;
	return @{$self->{headers}};
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
sub readHeaders {
	my ($self, @args) = @_;
	$self->SUPER::readHeaders(@args);
	map { s/Visiblility/Visibility/ } @{$self->{headers}};
}


package Nova::ConText::Type::Outf;
use base 'Nova::ConText::Type';
Nova::ConText::Type->register('outf', __PACKAGE__);

# Some things need to be hex
sub _mapping {
	my ($self, $headers, $values) = @_;
	my $hash = $self->SUPER::_mapping($headers, $values);
	
	my %forceHex = map { $_ => 1 } (17, 30, 43);
	
	for my $modtype (grep /^ModType/, keys %$hash) {
		next unless $forceHex{$hash->{$modtype}->value};
		(my $modval = $modtype) =~ s/ModType/ModVal/;
		my $val = $hash->{$modval}->value;
		$hash->{$modval} = Nova::Resource::Value::Hex->new($val, 4);
	}
	
	return $hash;
}


package Nova::ConText::Type::Rank;
use base 'Nova::ConText::Type';
Nova::ConText::Type->register('rank', __PACKAGE__);

# Missing some fields in ConText!
sub _mapping {
	my ($self, $headers, $values) = @_;
	push @$values, ('') x ($#$headers - $#$values);
	return $self->SUPER::_mapping($headers, $values);
}


1;
