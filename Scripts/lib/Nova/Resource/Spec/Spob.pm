# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Spec::Spob;
use strict;
use warnings;

use base qw(Nova::Resource::Spec);

use Nova::Resource::Spec::Govt;

=head1 NAME

Nova::Resource::Spec::Spob - A specification for a spob

=cut

sub desc {
	my ($self) = @_;
	my $spec = $self->spec;
	if ($spec == -4) {
		return "same as AvailStel";
	} elsif ($spec == -3) {
		return "random uninhabied";
	} elsif ($spec == -2) {
		return "random inhabited";
	} elsif ($spec == -1) {
		if ($self->field eq 'AvailStel') {
			return "random stellar";
		} else {
			return "none";
		}
	} elsif ($spec >= 128 && $spec < 5000) {
		my $spob = $self->collection->get(spob => $spec);
		my $syst = $spob->syst;
		return sprintf "%s (%d) in %s (%d)", $spob->name, $spob->ID,
			$syst->name, $syst->ID;
	} elsif ($spec >= 5000 && $spec < 9999) {
		my $syst = $self->collection->get(syst => $spec - 5000 + 128);
		return sprintf "stellar in system adjacent to %s (%d)", $syst->Name,
			$syst->ID;
	} elsif ($spec >= 10000) {
		return Nova::Resource::Spec::Govt->new($self->resource, $self->field)
			->desc;
	} else {
		# Damn weirdos
		return "invalid value";
	}
}

1;
