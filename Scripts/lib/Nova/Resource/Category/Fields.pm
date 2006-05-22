# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource;
use strict;
use warnings;

# Methods for specific types of fields


# Get a full name, suitable for printing
sub fullName {
	my ($self) = @_;
	return $self->name;
}

# Get info that is appropriate to display when ranking this object on the
# given field.
sub rankInfo {
	my ($self, $rankField) = @_;
	return '' unless $self->hasField('cost');
	return '' if lc $rankField eq 'cost';
	return $self->formatCost;
}

# The object representing the govt (if applicable)
sub govtObj {
	my ($self) = @_;
	require Nova::Resource::Type::Govt;
	return Nova::Resource::Type::Govt->fromCollection($self->collection,
		$self->govt);
}

# Register some new flags
sub flagInfo {
	my $pkg = caller;
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


1;
