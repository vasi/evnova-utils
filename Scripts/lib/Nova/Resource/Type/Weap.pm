# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Weap;
use strict;
use warnings;

use base qw(Nova::Base);
use Nova::Resource;

use Nova::Resource::Type::Outf;
use Nova::Cache;

# Weapons to outfits cache
sub _w2o {
	$_[0]->precalc(w2o => sub {
		my ($self, $cache) = @_;
		for my $outf (reverse $self->collection->type('outf')) {
			my $mass = $outf->mass;
			for my $mod ($outf->mods) {
				my $mv = $mod->{ModVal};
				if ($mod->{ModType} == MT_WEAPON) {
					$cache->{'weapon',$mv} = $mass;
				} elsif ($mod->{ModType} == MT_AMMO) {
					$cache->{'ammo',$mv} = $mass;
				}
			}
		}
	});
}

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
	
	my $w2o = $self->_w2o;
	unless (exists $w2o->{'weapon',$self->ID}) {
		warn sprintf "No outfit found for weapon ID %d\n", $self->ID if $verb;
		return 0;
	}
	return $w2o->{'weapon',$self->ID};
}

# How much mass per ammo?
sub ammoMass {
	my ($self, $verb) = @_;
	$verb = 0 unless defined $verb;
	
	my $source = $self->ammoSource;
	return 0 unless defined $source;
	
	my $w2o = $self->_w2o;
	unless (exists $w2o->{'ammo',$source->ID}) {
		warn sprintf "No outfit found for ammo ID %d\n", $self->ID if $verb;
		return 0;
	}
	return $w2o->{'ammo',$source->ID};
}


1;
