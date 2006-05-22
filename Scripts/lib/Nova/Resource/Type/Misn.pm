# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Misn;
use strict;
use warnings;

use base qw(Nova::Base);
use Nova::Resource;
Nova::Resource->registerType('misn');

use Nova::Resource::Spec::Spob;
use Nova::Resource::Spec::Syst;

sub fullName {
	my ($self) = @_;
	my $name = $self->NEXT::fullName;
	if ($name =~ /^(.*);\s*(.*)$/) {
		return "$2: $1";
	} else {
		return $name;
	}
}

sub show {
	my ($self, $verb) = @_;
	my $ret = $self->NEXT::show($verb);
	
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

sub formatByName {
	my ($self, $field, $verb) = @_;
	if ($field =~ /(Text|Brief)$/) {
		return $self->formatText($field, $verb);
	} elsif ($field =~ /Stel$/) {
		return $self->formatStelSpec($field, $verb);
	} else {
		return $self->NEXT::formatByName($field, $verb);
	}
}

sub showByName {
	my ($self, $field, $verb) = @_;
	if ($field =~ /(Text|Brief)$/) {
		return $self->showText($field, $verb);
	} else {
		return $self->NEXT::showByName($field, $verb);
	}
}

sub fieldDefaults {
	return (
		AvailRecord		=> 0,
		AvailRating		=> [ -1, 0 ],
		AvailRandom		=> 100,
		AvailShipType	=> [ -1, 0 ],
		ShipCount		=> [ -1, 0 ],
		AvailLoc		=> 1,
	);
}

sub formatStelSpec {
	return Nova::Resource::Spec::Spob->new(@_[0,1])->desc;
}

sub showText {
	my ($self, $field, $verb) = @_;
	my $descid = $self->field($field);
	if ($descid < 128) {
		return $verb < 2 ? '' : "$field: $descid\n";
	}
	my $desc = $self->collection->get(desc => $descid);
	my $text = $desc->Description;
	return "$field: $text\n\n";
}

# Fake field
sub initialText { $_[0]->ID + 4000 - 128 }

sub formatShipSyst {
	my ($self, $field, $verb) = @_;
	unless (defined ($self->fieldDefined('shipCount'))) {
		return $verb < 2 ? '' : 'none';
	}
	return Nova::Resource::Spec::Syst->new($self, $field)->desc;;
}

sub formatAvailLoc {
	my ($self, $field, $verb) = @_;
	my $val = $self->field($field);
	return '' if $verb < 2 && !defined($self->fieldDefined($field));
	
	my %locations = (		0 => 'mission computer',	1 => 'bar',
		2 => 'pers',		3 => 'main spaceport',		4 => 'commodities',
		5 => 'shipyard',	6 => 'outfitters');
	return $locations{$val};
}

1;
