# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Pers;
use strict;
use warnings;

use base qw(Nova::Base);
use Nova::Resource;
Nova::Resource->registerType('pers');

use Nova::Resource::Spec::Syst;

sub importantBitFields { qw(ActivateOn) }

flagInfo('Flags',
	holdsGrudge		=> 'holds a grudge',
	escapePod		=> 'has an escape pod and afterburner',
	quoteGrudge		=> 'only hails when has a grudge',
	quoteLike		=> 'only hails when likes player',
	quoteAttack		=> 'only hails when attacking player',
	quoteDisabled	=> 'only hails when disabled',
	linkSpecialShip	=> 'becomes the special ship in the linked mission',
	hailOnce		=> 'only hails once',
	linkDeactivate	=> 'deactive after link mission',
	linkBoard		=> 'board for link mission',
	linkQuote		=> 'only hails when link mission available',
	linkLeave		=> 'leave after link mission accepted',
	linkNoWimpy		=> 'unavailable if in wimpy freighter',
	linkNoBeefy		=> 'unavailable if in beefy freighter',
	linkNoWarship	=> 'unavailable if in warship',
	hailDisaster	=> 'show disaster info when hailing',
);


sub show {
	my ($self, $verb, @fields) = @_;
	my $ret = $self->NEXT::show($verb, @fields);
	return $ret if @fields;
	
	$ret .= $self->showField($_, $verb) for (qw(ShipType LinkSyst Govt
		StartDisabled LinkBoard LinkNoWimpy LinkNoBeefy LinkNoWarship
		HailQuote));
	return $ret;
}

sub formatLinkSyst {
	my ($self, $field, $verb) = @_;
	return $verb < 2 ? '' : 'none' if $self->$field == -1;
	return Nova::Resource::Spec::Syst->new($self, $field)->desc;
}

sub startDisabled {
	return $_[0]->govtObj->startDisabled;
}

sub showStartDisabled {
	my ($self, $field, $verb) = @_;
	return "Disabled\n" if $self->startDisabled;
}

sub formatHailQuote {
	my ($self, $field, $verb) = @_;
	my $hq = $self->$field;
	return $verb < 2 ? '' : 'none' if $hq == -1;
	return $self->collection->get('STR#' => 7101)->strings->[$hq - 1];
}

#sub formatShipType {

1;
