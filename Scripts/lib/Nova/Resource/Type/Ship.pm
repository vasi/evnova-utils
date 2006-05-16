# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Ship;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('ship');

use Nova::Util qw(columns);
use List::Util qw(sum);

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

# Subs for massing
sub _massAddItem {
	my ($self, $data, $count, $mass, $type, $item) = @_;
	my $add = $count * $mass;
	push @{$data->{parts}},
		[ $add, '=', $count, 'x', $mass, $type, $item->ID, ':', $item->name ];
	$data->{mass} += $add;
}

sub _massPush {
	my ($self, $data, $mass, $name) = @_;
	push @{$data->{parts}},	[ $mass, ('') x 4, $name, ('') x 10 ]; # High enough
}

sub _massInit {
	my ($self) = @_;
	my $mass = $self->freeMass;
	my $data = { mass => $mass, parts => [ ] };
	# parts are: totMass, '=', count, 'x', massPer, type, ID, ':', name
	
	$self->_massPush($data, $mass, 'free');
	return $data;
}

sub _massFinish {
	my ($self, $data, $print) = @_;
	my $total = sum map { $_->[0] } @{$data->{parts}};
	$self->_massPush($data, $total, 'TOTAL');
	columns("%d %s  %s %s  %s - %-s %s%s %-s", $data->{parts}, sub { @$_ },
		total => 1) if $print;
	return $total;
}

# Get the total mass of a ship
sub mass {
	my ($self, $verb) = @_;
	$verb = 0 unless defined $verb;
	
	printf "Massing ship %4d: %s\n", $self->ID, $self->fullName if $verb >= 2;
	my $mass = $self->_massInit;
	
	for my $w ($self->weapons) {
		$self->_massAddItem($mass, $w->{count}, $w->{weap}->mass($verb >= 2),
			weapon => $w->{weap});
		next unless $w->{ammo};
		$self->_massAddItem($mass, $w->{ammo}, $w->{weap}->ammoMass($verb >= 2),
			ammo => $w->{weap});
	}	
	for my $o ($self->outfits) {
		$self->_massAddItem($mass, $o->{count}, $o->{outf}->mass,
			outfit => $o->{outf});
	}
	
	return $self->_massFinish($mass, $verb);
}

1;
