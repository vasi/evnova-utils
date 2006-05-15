# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Ship;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('ship');

# Add the subtitle to the full name, if it seems like a good idea
sub fullName {
	my ($self) = @_;
	my $name = $self->SUPER::fullName;
	my $sub = $self->subTitle;
	return $name unless $sub;
	return "$name, $sub";
}

# Get the weapons on the ship
sub weapons {
	my ($self) = @_;
	my @objs = $self->multiObjs('WType', 'WCount', 'Ammo');
	
	my @ret;
	for my $o (@objs) {
		push @ret, {
			weap	=> $self->collection->get(weap => $o->{WType}),
			count	=> $o->{WCount},
			ammo	=> $o->{Ammo},
		};
	}
	return @ret;
}

# Get the outfits on the ship
sub outfits {
	my ($self) = @_;
	my @objs = $self->multiObjs('DefaultItems', 'ItemCount');
	
	my @ret;
	for my $o (@objs) {
		push @ret, {
			outf	=> $self->collection->get(outf => $o->{DefaultItems}),
			count	=> $o->{ItemCount},
		};
	}
	return @ret;
}

# Get the total mass of a ship
sub mass {
	my ($self, $verb) = @_;
	$verb = 0 unless defined $verb;
	
	printf "Massing ship %4d: %s\n", $self->ID, $self->fullName if $verb >= 2;
	
	my $mass = $self->freeMass;
	printf "  %3d              - free\n", $mass if $verb;
	
	for my $w ($self->weapons) {
		my $weap = $w->{weap};
		my $wMass = $weap->mass($verb >= 2);
		my $add = $w->{count} * $wMass;
		$mass += $add;
		printf "  %3d = %4d x %3d - weapon %s\n", $add, $w->{count},
			$wMass, $weap->uniqName if $verb;
		
		next unless $w->{ammo};
		my $aMass = $weap->ammoMass($verb >= 2);
		$add = $w->{ammo} * $aMass;
		printf "  %3d = %4d x %3d - ammo   %s\n", $add, $w->{ammo},
			$aMass, $weap->uniqName if $verb;
	}
	
	for my $o ($self->outfits) {
		my $outf = $o->{outf};
		my $add = $o->{count} * $outf->mass;
		printf "  %3d = %4d x %3d - outfit %s\n", $add, $o->{count},
			$outf->mass, $outf->uniqName if $verb;
	}
	
	if ($verb) {
		print "  ", "-" x 50, "\n";
		printf "  %3d              - TOTAL\n", $mass;
	}
	return $mass;
}

1;
