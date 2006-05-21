# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Cron;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('cron');

__PACKAGE__->flagInfo('Flags',
	iterativeEntry	=> 'iterative entry',
	iterativeExit	=> 'iterative exit',
);

use Nova::Resource::Type::Govt;


our @TIME_FIELDS = qw(FirstDay FirstMonth FirstYear LastDay LastMonth LastYear);

sub fieldDefaults {
	return (
		(map { $_ => [ 0, -1 ] } @TIME_FIELDS),
		(map { $_ => 0 } qw(Duration PreHoldoff PostHoldoff)),
		Random => 100,
	);
}

sub show {
	my ($self, $verb) = @_;
	my $ret = $self->SUPER::show($verb);
	
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
	if ($self->IndNewsStr != -1 && $self->IndNewsStr != 0) {
		push @objs, { NewsGovt => -1, GovtNewsStr => $self->IndNewsStr };
	}
	
	my @news;
	for my $n (@objs) {
		my $govt = Nova::Resource::Type::Govt->fromCollection(
			$self->collection, $n->{NewsGovt});
		my $strn = $self->collection->get('STR#' => $n->{GovtNewsStr});
$DB::single = 1 if !defined $strn;
		push @news, { govt => $govt, strn => $strn };
	}
	return @news;
}

1;
	