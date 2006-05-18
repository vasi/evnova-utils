# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Misn;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('misn');

use Nova::Resource::Spec::Spob;

sub fullName {
	my ($self) = @_;
	my $name = $self->SUPER::fullName;
	if ($name =~ /^(.*);\s*(.*)$/) {
		return "$2: $1";
	} else {
		return $name;
	}
}

sub show {
	my ($self, $verb) = @_;
	my $div = "\n" x ($verb + 1);
	my $ret = '';
	
	$ret .= sprintf "%s (%d)$div", $self->fullName, $self->ID;
	$ret .= $self->showField($_, $verb) for qw(
		AvailStel AvailLoc AvailRecord AvailRating AvailRandom
		AvailShipType AvailBits OnSuccess
	);
	
	return $ret;
}

sub showField {
	my ($self, $field, $verb) = @_;
	my $meth = "show$field";
	return $self->$meth($field, $verb) if $self->can($meth);

	if ($field =~ /Stel$/) {
		return Nova::Resource::Spec::Spob->new($self, $field)
			->dump($verb > 2);
	} else {
		my %defaults = (
			AvailRecord		=> 0,
			AvailRating		=> [0, -1],
			AvailRandom		=> 100,
			AvailShipType	=> [0, -1],
		);
		my $defaults = [ '' ];
		$defaults = $defaults{$field} if exists $defaults{$field};
		$defaults = [ $defaults ] unless ref $defaults;
		
		my $val = $self->field($field);
		return '' if $verb < 2 && grep { $_ eq $val } @$defaults;
		return "$field: $val\n";
	}
}

sub showAvailLoc {
	my ($self, $field, $verb) = @_;
	my $val = $self->field($field);
	return '' if $verb < 2 && $val == 1;
	
	my %locations = (		0 => 'mission computer',	1 => 'bar',
		2 => 'pers',		3 => 'main spaceport',		4 => 'commodities',
		5 => 'shipyard',	6 => 'outfitters');
	return "$field: $locations{$val}\n";
}

1;
