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
	my ($self, $verb, @fields) = @_;
	my $ret = $self->NEXT::show($verb, @fields);
	return $ret if @fields;
	
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
		AvailShipType	=> [ -1, 0, 127 ],
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
	return Nova::Resource::Spec::Syst->new($self, $field)->desc;
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

sub importantBitFields { $_[0]->bitFields }

sub _spobSystCache {
	$_[0]->precalc(spobSyst => sub {
		my ($self, $cache) = @_;
		for my $syst (reverse $self->collection->type('syst')) {
			for my $spob ($syst->spobs) {
				$cache->{$spob->ID} = $syst->ID;
			}
		}
	});
}

sub persons {
	my ($self) = @_;
	
	my $id = $self->ID;
	my $c = $self->precalc(misnPers => sub {
		my ($self, $cache) = @_;
		for my $pers ($self->collection->type('pers')) {
			if (defined(my $mid = $pers->fieldDefined('LinkMission'))) {
				push @{$cache->{$mid}}, $pers->ID;
			}
		}
	});
	return exists $c->{$id}
		? map { $self->collection->get(pers => $_) } @{$c->{$id}}
		: ();
}

sub shipType {
	my ($self) = @_;
	return Nova::Resource::Type::Misn::ShipType->new($self);
}

sub formatAvailShipType {
	my ($self, $field, $verb) = @_;
	return $self->shipType->format($verb);
}

sub showPersons {
	my ($self, $verb) = @_;
	my @persons = $self->persons;
	return '' unless @persons;
	
	my $ret = $self->header;
	$ret .= $self->showField($_, $verb) for (qw(AvailRecord
		AvailRating AvailRandom AvailShipType AvailBits CargoQty));
	
	# FIXME: more!
	return $ret;
}


package Nova::Resource::Type::Misn::ShipType;
use base qw(Nova::Base);
__PACKAGE__->fields(qw(collection type res neg));

sub init {
	my ($self, $resource) = @_;
	$self->collection($resource->collection);
	$self->neg(0);
	
	my $val = $resource->fieldDefined('AvailShipType');
	if (defined $val) {
		my $cat = int($val / 1000);
		my $id = $val - $cat * 1000;
		my $type = $cat <= 1 ? 'ship' : 'govt';
		my $res = $self->collection->get($type => $id);
		my $neg = $cat % 2;
		
		$self->neg($neg);
		$self->res($res);
		$self->type($type);
	}
}

sub format {
	my ($self, $verb) = @_;
	my $type = $self->type;
	return $verb < 2 ? '' : 'any' unless defined $type;
	
	my $desc = sprintf '%s (%d)', $self->res->fullName, $self->res->ID;
	my $not = $self->neg ? 'not ' : '';
	my $fmt = $type eq 'ship' ? '%sship %s' : 'ship %sof govt %s';
	return sprintf $fmt, $not, $desc;
}

sub ships {
	my ($self) = @_;
	my $type = $self->type;
	return $self->collection->type('ship') unless defined $type;
	
	my $neg = $self->neg;
	return $self->res if $type eq 'ship' && !$neg; # shortcut
	
	my $field = $type eq 'ship' ? 'ID' : 'InherentGovt';
	my $id = $self->res->ID;
	return grep { ($_->field($field) == $id) ^ $neg }
		$self->collection->type('ship');
}

1;
