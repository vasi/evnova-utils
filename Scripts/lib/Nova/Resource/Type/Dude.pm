# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Dude;
use strict;
use warnings;

use base qw(Nova::Base);
use Nova::Resource;
Nova::Resource->registerType('dude');
__PACKAGE__->fields(qw(probs));

use Nova::Columns qw(columnsStr);

sub _calcProbs {
	my ($self) = @_;
	if (defined(my $p = $self->probs)) {
		return $p;
	} else {
		my %ships;
		my @ships = $self->multiObjs('ShipTypes', 'Probs');
		for my $s (@ships) {
			$ships{$s->{ShipTypes}} += $s->{Probs};
		}
		
		return $self->probs(\%ships);
	}
}

sub ships {
	my ($self) = @_;
	return map { $self->collection->get(ship => $_) }
		sort keys %{$self->_calcProbs};
}

sub shipProb {
	my ($self, $ship) = @_;
	return $self->_calcProbs->{$ship->ID};
}

sub strength {
	my ($self) = @_;
	my $strength = 0;
	for my $ship ($self->ships) {
		$strength += $ship->strength * $self->shipProb($ship) / 100;
	}
	return $strength;
}

sub show {
	my ($self) = @_;
	my $ret = $self->NEXT::show;
	chomp $ret;
	$ret .= sprintf "  (strength: %.2f)\n", $self->strength;
	$ret .= columnsStr('  %3d%% - %-s', [ $self->ships ],
		sub { $self->shipProb($_), $_->fullName },
		rank => sub { $self->shipProb($_) },
	);
	return $ret;
}

1;
