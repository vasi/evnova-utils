# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Cron;
use strict;
use warnings;

use base qw(Nova::Base);

use Nova::Resource;

use Nova::Resource::Type::Govt;

flagInfo('Flags',
	iterativeEntry	=> 'iterative entry',
	iterativeExit	=> 'iterative exit',
);


our @TIME_FIELDS = qw(FirstDay FirstMonth FirstYear LastDay LastMonth LastYear);

sub fieldDefaults {
	return (
		(map { $_ => [ -1, 0 ] } @TIME_FIELDS, 'IndNewsStr'),
		(map { $_ => 0 } qw(Duration PreHoldoff PostHoldoff)),
		Random => 100,
	);
}

sub show {
	my ($self, $verb, @fields) = @_;
	my $ret = $self->NEXT::show($verb, @fields);
	return $ret if @fields;
	
	$ret .= $self->showField($_, $verb) for (
		@TIME_FIELDS, qw(Random Duration PreHoldoff PostHoldoff EnableOn
		OnStart OnEnd Contribute Require Flags News)
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

sub importantBitFields { $_[0]->bitFields }

1;
