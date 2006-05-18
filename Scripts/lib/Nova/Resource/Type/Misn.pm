# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Misn;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('misn');

use Nova::Resource::Spec::Spob;
use Nova::Resource::Spec::Syst;

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
	my $ret = '';
	
	$ret .= sprintf "%s (%d)\n", $self->fullName, $self->ID;
	$ret .= $self->showField($_, $verb) for qw(
		AvailStel AvailLoc AvailRecord AvailRating AvailRandom
		AvailShipType AvailBits OnSuccess
	);
	
	if ($verb) {
		$ret .= "\n";
		my $where = ''; 
		for my $field (qw(TravelStel ReturnStel ShipSyst)) {
			my $s = $self->showField($field, $verb);
			$where = "\n" if $s;
			$ret .= $s;
		}
		$ret .= $where;
			
		$ret .= $self->showField($_, $verb) for qw(
			InitialText RefuseText BriefText QuickBrief
			LoadCargText ShipDoneText DropCargText CompText FailText);
	}
		
	return $ret;
}

sub showField {
	my ($self, $field, $verb) = @_;
	my $meth = "show$field";
	return $self->$meth($field, $verb) if $self->can($meth);

	if ($field =~ /Stel$/) {
		return Nova::Resource::Spec::Spob->new($self, $field)
			->dump($verb > 2);
	} elsif ($field =~ /(Text|Brief)$/) {
		my $descid = $self->field($field);
		if ($descid < 128) {
			return $verb < 2 ? '' : "$field: $descid\n";
		}
		my $desc = $self->collection->get(desc => $descid);
		my $text = $desc->Description;
		return "$field: $text\n\n";
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

# Fake field
sub initialText { $_[0]->ID + 4000 - 128 }

sub showShipSyst {
	my ($self, $field, $verb) = @_;
	if ($self->shipCount == -1) {
		return $verb < 2 ? '' : "$field: none\n";
	}
	return Nova::Resource::Spec::Syst->new($self, $field)->dump($verb > 2);
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
