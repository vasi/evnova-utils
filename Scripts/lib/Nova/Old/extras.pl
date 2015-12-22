use warnings;
use strict;

my @extrasHandlers = (
	\&extrasShipSpace,
);

sub extrasAddResource {
	my ($cache, $res) = @_;
	for my $handler (@extrasHandlers) {
		$handler->($cache, $res);
	}
}

sub extrasAdd {
	my $cache = {};
	for my $r (@_) {
		if (exists $r->{_priv}) {
			extrasAddResource($cache, $r);
		} else {
			extrasAdd(values %$r);
		}
	}
}

sub addResourceField {
	my ($res, $name, $type) = @_;
	$type ||= 'misc';
	my $order = $res->{_priv}{order};
	push @$order, $name;
	$res->{_priv}{types}[$#$order] = $type;
}

sub extrasShipSpace {
	my ($cache, $res) = @_;
	return unless deaccent($res->{Type}) eq 'ship';

	my %fields = (xTotSpace => 0, xRemSpace => 1);
	while (my ($field, $remov) = each %fields) {
		$res->{$field} = shipTotalMass($res, cache => $cache,
			removable => $remov);
		addResourceField($res, $field);
	}
}

1;
