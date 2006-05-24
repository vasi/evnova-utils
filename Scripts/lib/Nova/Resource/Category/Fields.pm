# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource;
use strict;
use warnings;

# Methods for specific types of fields
use Math::BigInt;

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
		next unless defined $text;
		push @texts, $text;
		
		my $mask = 1 << $bit++;
		$pkg->makeSub($funcName => sub { $_[0]->$field & $mask });
	}
	$pkg->symref('FLAG_FIELDS')->{lc $field} = \@texts;
}

sub _flagFields {
	my ($self, $field) = @_;
	my $pkg = ref($self) || $self;
	$field = lc $field;
	
	my $flagFields = $pkg->symref('_FLAG_FIELDS');
	if (exists $flagFields->{$field}) {	
		return @{$flagFields->{$field}};
	}
	
	for my $parent (@{$pkg->symref('ISA')}) {
		my @ret;
		eval { @ret = _flagFields($parent, $field) };
		return @ret if @ret;
	}
	return ();
}

# Get the names of the flags that are on
sub flagsOn {
	my ($self, $field) = @_;
	my $val = $self->$field;
	
	my @flags = $self->_flagFields($field);
	die "No flags for field '$field'\n" unless @flags;
	
	my @on;
	for my $i (0..$#flags) {
		my $mask = 1 << $i;
		next unless $val & $mask;
		push @on, $flags[$i];
	}
	return @on;
}

# Get a contribute/require field
sub contribRequire {
	my ($self, $prefix) = @_;
	my @vals = $self->multi($prefix);
	
	my $val = Math::BigInt->new(0);
	for my $v (@vals) {
		$val <<= 32;
		$val += $v;
	}
	
	return $val;
}

sub contribute	{ $_[0]->contribRequire('Contrib')	}
sub require		{ $_[0]->contribRequire('Require')	}

sub isBitSet {
	my ($self, $field) = @_;
	return $field =~ /^On[A-Z]/;
}

sub isBitTest {
	my ($self, $field) = @_;
	return $field =~ /On$/ || $field =~ /^Avail(Bits|ability)/
		|| $field eq 'Visibility';
}

{
	my $cache;

	sub bitFields {
		my ($self) = @_;
		my $type = $self->type;
		unless (exists $cache->{$type}) {
			$cache->{$type} = [
				grep { $self->isBitSet($_) || $self->isBitTest($_) }
					$self->fieldNames
			];
		}
		return @{$cache->{$type}};
	}
}

sub usesBit {
	my ($self, $field, $bitnum) = @_;
	die "Bit must be a number!\n" if $bitnum =~ /\D/;
	my $bit = "b$bitnum";
	return $self->$field =~ /$bit\b/;
}

sub importantBitFields { () }

sub showBitFields {
	my ($self, $bitnum, $verb) = @_;
	my @fields = $self->bitFields;
	my @uses = grep { $self->usesBit($_, $bitnum) } @fields;
	return '' unless @uses;
	
	if ($verb == 0) {
		@fields = @uses;
	} elsif ($verb == 1) {
		my %show = map { $_ => 1 } (@uses, $self->importantBitFields);
		@fields = grep { $show{$_} } @fields;
	}
	
	--$verb if $verb;
	return $self->show($verb, @fields);
}

1;
