# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Weap;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('weap');

use Storable;

use Nova::Resource::Outf;
use Nova::Cache;

# Weapons to outfits cache
sub _w2o {
	my ($self) = @_;
	return $self->collection->{_w2o} if exists $self->collection->{_w2o};
	
	my $file = Nova::Cache->storableCache($self->source, 'w2o');
	my $cache = eval { retrieve $file };
	unless (defined $cache) {
		for my $outf (reverse $self->collection->type('outf')) {
			my $mass = $outf->mass;
			for my $mod ($outf->mods) {
				my $mv = $mod->{ModVal};
				if ($mod->{ModType} == MT_WEAPON) {
					$cache->{$mv}->{weapon} = $mass;
				} elsif ($mod->{ModType} == MT_AMMO) {
					$cache->{$mv}->{ammo} = $mass;
				}
			}
		}
		store $cache, $file;
	}
	return ($self->collection->{_w2o} = $cache);
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
	unless (exists $w2o->{$self->ID}->{weapon}) {
		warn sprintf "No outfit found for weapon ID %d\n", $self->ID if $verb;
		return 0;
	}
	return $w2o->{$self->ID}->{weapon};
}

# How much mass per ammo?
sub ammoMass {
	my ($self, $verb) = @_;
	$verb = 0 unless defined $verb;
	
	my $source = $self->ammoSource;
	return 0 unless defined $source;
	
	my $w2o = $self->_w2o;
	unless (exists $w2o->{$source->ID}->{ammo}) {
		warn sprintf "No outfit found for ammo ID %d\n", $self->ID if $verb;
		return 0;
	}
	return $w2o->{$source->ID}->{ammo};
}


1;
