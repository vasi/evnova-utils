# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Cron;
use strict;
use warnings;

use base qw(Nova::Base);

use Nova::Resource;
Nova::Resource->registerType('cron');

flagInfo('Flags',
	iterativeEntry	=> 'iterative entry',
	iterativeExit	=> 'iterative exit',
);

use Nova::Resource::Type::Govt;


our @TIME_FIELDS = qw(FirstDay FirstMonth FirstYear LastDay LastMonth LastYear);

sub fieldDefaults {
	return (
		(map { $_ => [ 0, -1 ] } @TIME_FIELDS, 'IndNewsStr'),
		(map { $_ => 0 } qw(Duration PreHoldoff PostHoldoff)),
		Random => 100,
	);
}

sub show {
	my ($self, $verb) = @_;
	my $ret = $self->NEXT::show($verb);
	
	$ret .= $self->showField($_, $verb) for (
		@TIME_FIELDS, qw(Random Duration PreHoldoff PostHoldoff EnableOn
		OnStart OnEnd Flags News)
	);
	
	return $ret;
}

sub showNews {
	my ($self, $verb) = @_;
	my $ret = '';
	
	for my $n ($self->news) {
		$ret .= sprintf "News for %s (%d):\n%s\n", $n->{govt}->fullName,
			$n->{govt}->ID, $n->{strn}->showList;
	}
	return $ret;
}


# Return hashes representing the news
sub news {
	my ($self) = @_;
	my @objs = $self->multiObjs('NewsGovt', 'GovtNewsStr');
	if (defined(my $indie = $self->fieldDefined('IndNewsStr'))) {
		push @objs, { NewsGovt => -1, GovtNewsStr => $indie };
	}
	
	my @news;
	for my $n (@objs) {
		my $govt = Nova::Resource::Type::Govt->fromCollection(
			$self->collection, $n->{NewsGovt});
		my $strn = $self->collection->get('STR#' => $n->{GovtNewsStr});
		push @news, { govt => $govt, strn => $strn };
	}
	return @news;
}

1;
	