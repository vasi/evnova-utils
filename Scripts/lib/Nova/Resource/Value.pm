# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Value;
use strict;
use warnings;

=head1 NAME

Nova::Resource::Value - A typed value in a resource

=head1 SYNOPSIS

  my $value = Nova::Resource::Value->fromConText($str);

  my $conText = $value->toConText;
  my $dump = $value->dump;
  my $value = $value->value;

=cut

use base qw(Nova::Base);
__PACKAGE__->fields(qw(value));

# my $value = Nova::Resource::Value->fromConText($str);
#
# Parse a ConText string to create a Value.
sub fromConText {
	my ($class, $str) = @_;
	
	my ($subclass, @data) = (undef, $str);
	if ($str =~ /^"(.*)"$/) {
		($subclass, @data) = (String => $1);
	} elsif ($str =~ /^#(.*)$/) {
		($subclass, @data) = (Color => hex($1));
	} elsif ($str =~ /^0x(.*)$/) {
		($subclass, @data) = (Hex => hex($1), length($1));
	}
	
	$subclass = defined $subclass ? "${class}::$subclass" : $class;
	my $obj = $subclass->new;
	$obj->initWithContext(@data);
	return $obj;
}

# Initialize
sub init { $_[0]->value($_[1]) }

# Initialize with data from ConText, may need parsing
sub initWithContext {
	my ($self, @args) = @_;
	$self->init(@args);
}

# Return the value in printable format
sub dump { $_[0]->value }

# Format for dumping to ConText
sub toConText { $_[0]->dump }

package Nova::Resource::Value::String;
use base 'Nova::Resource::Value';

sub initWithContext {
	my ($self, $val) = @_;
	
	# Fix escaped values
	$val =~ s/\\q/\"/g;
	$val =~ s/\\r/\n/g;
	$val =~ s/\\t/\t/g;
	
	$self->SUPER::initWithContext($val);
}

sub toConText {
	my ($self) = @_;
	my $val = $self->value;
	$val =~ s/"/\\q/g;
	$val =~ s/\n/\\r/g;
	$val =~ s/\t/\\t/g;
	return sprintf '"%s"', $val;
}


package Nova::Resource::Value::Hex;
use base 'Nova::Resource::Value';
__PACKAGE__->fields(qw(length));

sub init {
	my ($self, $val, $length) = @_;
	$self->SUPER::init($val);
	$self->length($length);
}

sub dump {
	my ($self) = @_;
	return sprintf "0x%0*x", $self->length, $self->value;
}


package Nova::Resource::Value::Color;
use base 'Nova::Resource::Value';

sub dump {
	my ($self) = @_;
	return sprintf "#%06x", $self->value;
}


package Nova::Resource::Value::List;
use base 'Nova::Resource::Value';

sub dump {
	my ($self) = @_;
	return join('',
		map { sprintf "\n  %3d: %s", $_, $self->value->[$_] }
			(0..$#{$self->value})
	);
}

sub toConText {
	my ($self) = @_;
	return join "\t", map { NRVS->new($_)->toConText } @{$self->value};
}

1;
