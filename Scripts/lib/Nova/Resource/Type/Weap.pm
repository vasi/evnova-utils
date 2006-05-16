# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Weap;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('weap');

use Nova::Resource::Type::Outf;

# What weapon does the ammo come from?
sub ammoSource {
	my ($self) = @_;
	my $ammo = $self->ammoType;
	my $source = $ammo + 128;
	
	# Some fighter bays seem to just pick this number at random, it 
	# appears meaningless. So only set the source if it seems meaningful.
	if ($ammo >= 0 && $ammo <= 255
			&& $self->collection->exists(weap => $source)) {
		return $self->collection->get(weap => $source);
	} else {
		return undef;
	}
}

# How much mass per weapon?
sub mass {
	my ($self, $verb) = @_;
	$verb = 0 unless defined $verb;
	
	for my $outf (reverse $self->collection->type('outf')) {
		for my $mod ($outf->mods) {
			next unless $mod->{ModType} == MT_WEAPON;
			return $outf->mass if $mod->{ModVal} == $self->ID;
		}
	}

	warn sprintf "No outfit found for weapon ID %d\n", $self->ID if $verb;
	return 0;
}

# How much mass per ammo?
sub ammoMass {
	my ($self, $verb) = @_;
	$verb = 0 unless defined $verb;
	
	my $source = $self->ammoSource;
	return 0 unless defined $source;
	
	for my $outf (reverse $self->collection->type('outf')) {
		for my $mod ($outf->mods) {
			next unless $mod->{ModType} == MT_AMMO;
			return $outf->mass if $mod->{ModVal} == $source->ID;
		}
	}

	warn sprintf "No outfit found for ammo ID %d\n", $self->ID if $verb;
	return 0;
}


1;
