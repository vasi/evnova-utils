# Copyright (c) 2006 Dave Vasilevsky

package Nova::ConText::Type;
use strict;
use warnings;

use base 'Nova::Base';

use Nova::Resource;
use Nova::Resource::Field;
use Nova::Resource::Value;

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
# Parse a line into fields
sub _parseLine {
	my ($class, $line) = @_;
	my @items = split /\t/, $line;
	my @fields = map { Nova::Resource::Value->fromString($_) } @items;
	return @fields;
}

# my @headers = $reader->headers($line);
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
}

# my @fields = $reader->_mapping($headers, $fields);
#
# Get the mapping from headers to values
sub _mapping {
	my ($self, $headers, $values) = @_;
	use Data::Dumper; print Dumper($headers, $values)
		unless scalar(@$headers) == scalar(@$values);
	die "Different number of headers and fields\n"
		unless scalar(@$headers) == scalar(@$values);
	return map {
		Nova::Resource::Field->new($headers->[$_], $values->[$_])
	} (0..$#$values);
}

# my @resources = $reader->resource($line);
#
# Parse a resource of this type.
sub resource {
	my ($self, $line) = @_;
	my @values = $self->_parseLine($line);
	
	# stop if no record
	return undef unless @values && $values[0]->value eq $self->{type};
	
	pop @values while $values[-1]->value eq '•'; # end-of-record
	
	my @fields = $self->_mapping($self->{headers}, \@values);
	return Nova::Resource->new(@fields);
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
Nova::ConText::Type->register('STR#', __PACKAGE__);

sub _mapping {
	my ($self, $headers, $values) = @_;
	my ($stridx) = grep { $headers->[$_] eq 'Strings' } (0..$#$headers);
	my @strings = splice @$values, $stridx;
	@strings = map { $_->value } @strings;
	push @$values, Nova::Resource::Value::List->new(@strings);
	
	return $self->SUPER::_mapping($headers, $values);
}


package Nova::ConText::Type::Syst;
use base 'Nova::ConText::Type';
Nova::ConText::Type->register('sÿst', __PACKAGE__);

# Mis-spelled field
sub headers {
	my ($self, @args) = @_;
	$self->SUPER::headers(@args);
	$self->{headers} = [ map {
		$_ eq 'Visiblility' ? 'Visibility' : $_
	} @{$self->{headers}} ];
}


package Nova::ConText::Type::Outf;
use base 'Nova::ConText::Type';
Nova::ConText::Type->register('öutf', __PACKAGE__);

# Some things need to be hex
sub _mapping {
	my ($self, $headers, $values) = @_;
	my @fields = $self->SUPER::_mapping($headers, $values);
	my %byName = map { $_->key => $_ } @fields;
	
	my %forceHex = map { $_ => 1 } (17, 30, 43);
	my %switch;
	
	for my $modtype (grep /^ModType/, keys %byName) {
		next unless $forceHex{$byName{$modtype}->value};
		(my $modval = $modtype) =~ s/ModType/ModVal/;
		my $val = $byName{$modval}->value;
		$switch{$modval} = Nova::Resource::Field->new(
			$modval,
			Nova::Resource::Value::Hex->new($val, 4)
		);
	}
	
	@fields = map { $switch{$_->key} || $_ } @fields;
	return @fields
}


1;
