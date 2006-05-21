# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Spec::Syst;
use strict;
use warnings;

use base qw(Nova::Resource::Spec);

use Nova::Resource::Spec::Govt;

=head1 NAME

Nova::Resource::Spec::Syst - A specification for a system

=cut

sub desc {
	my ($self) = @_;
	my $spec = $self->spec;
	if ($spec == -6) {
		return "follow the player";
	} elsif ($spec == -5) {
		return "adjacent to AvailStel";
	} elsif ($spec == -4) {
		return "system of ReturnStel";
	} elsif ($spec == -3) {
		return "system of TravelStel";
	} elsif ($spec == -2) {
		return "random system";
	} elsif ($spec == -1) {
		return "system of AvailStel";
	} elsif ($spec == 0) {
		return '';
	} elsif ($spec >= 128 && $spec < 5000) {
		my $syst = $self->collection->get(syst => $spec);
		return sprintf "%s (%d)", $syst->name, $syst->ID;
	} elsif ($spec >= 10000) {
		return Nova::Resource::Spec::Govt->new($self->resource, $self->field)
			->desc;
	} else {
		return 'invalid value';
	}
}

sub default { return 0 }

1;
