# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Govt;
use strict;
use warnings;

use base qw(Nova::Base);
use Nova::Resource;

flagInfo('Flags',
	xenophobic		=> 'xenophobic',
	nosy			=> "attacks player in non-allied system if he's a criminal",
	hatesPlayer		=> 'always attacks player',
	invincible		=> "invincible to player's shots",
	retreats		=> 'retreats when shields below 25%',
	nosyIgnore		=> 'nosy ships of other govts ignore when this govt is'
						. ' under attack',
	untouchable		=> "can't hurt or be hurt by player",
	freightersJam	=> 'freighters have jamming',
	noPersEscapePods	=> 'pers ships have no escape pods, but act like they'
							. ' do',
	bribeWarships	=> 'warships take bribes',
	cantHail		=> "can't be hailed",
	startDisabled	=> 'ships start disabled',
	plunder			=> 'warships will plunder ships before destroying them',
	bribeFreighters	=> 'freighters take bribes',
	bribePlanets	=> 'planets take bribes',
	bribeBig		=> 'demand higher bribes',
);

sub fromCollection {
	my ($class, $collection, $id) = @_;
	return Nova::Resource::Type::Govt::None->new($collection) if $id == -1;
	return $collection->get(govt => $id);
}

sub allGovts {
	my ($class, $collection) = @_;
	return ($class->fromCollection($collection, -1), $collection->type('govt'));
}

sub classIDs {
	my ($self) = @_;
	return $self->multi('Classes', defaults => [-1]);
}

sub classes {
	my ($self) = @_;
	return map { $self->class($_) } $self->classIDs;
}

sub _class {
	my ($self, $id) = @_;
	Nova::Resource::GovtClass->new($self->collection, $id);
}

sub _inverse {
	my ($self, @govts) = @_;
	my %govts = map { $_->ID => 1 } @govts;
	my @all = $self->allGovts($self->collection);
	return grep { !$govts{$_->ID} } @all;
}

sub _relation {
	my ($self, $key, $inverse) = @_;
	
	my @classIDs = $self->multi($key, defaults => [-1]);
	my @classes = map { $self->_class($_) } @classIDs;
	my @govts = map { $_->govts } @classes;
	
	if ($inverse) {
		return $self->_inverse(@govts);
	} else {
		my %govts = map { $_->ID => $_ } @govts;
		return map { $govts{$_} } sort { $a <=> $b } keys %govts;
	}
}

sub classMates		{ $_[0]->_relation('Classes', 0)	}
sub nonClassMates	{ $_[0]->_relation('Classes', 1)	}
sub allies			{ $_[0]->_relation('Allies', 0)		}
sub enemies			{ $_[0]->_relation('Enemies', 0)	}

sub others	{ $_[0]->_inverse($_[0])	}
sub self	{ $_[0]						}



package Nova::Resource::Type::Govt::None;
use base qw(Nova::Resource::Type::Govt Nova::Resource);

sub init {
	my ($self, $collection) = @_;
	$self->collection($collection);
}

sub name { 'independent' }

sub id { -1 }



package Nova::Resource::GovtClass;
use base 'Nova::Base';
__PACKAGE__->fields(qw(collection id));

sub init {
	my ($self, $collection, $id) = @_;
	$self->collection($collection);
	$self->id($id);
	
	my @govts;
	for my $govt ($collection->type('govt')) {
		for my $class ($govt->classIDs) {
			next unless $class == $id;
			push @govts, $govt;
		}
	}
	$self->{govts} = \@govts;
}

sub govts { @{$_[0]->{govts}} }

1;
	