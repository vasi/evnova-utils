# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Misn;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('misn');

use Nova::Resource::Spec::Spob;

sub fullName {
	my ($self) = @_;
	my $name = $self->SUPER::fullName;
	if ($name =~ /^(.*);\s*(.*)$/) {
		return "$2: $1";
	} else {
		return $name;
	}
}

sub show {
	my ($self, $verb) = @_;
	my $div = "\n" x ($verb + 1);
	my $ret = '';
	
	$ret .= sprintf "%s (%d)$div", $self->fullName, $self->ID;
	$ret .= $self->availStelSpec->dump;
	# FIXME
	
	return $ret;
}

sub availStelSpec {
	my ($self) = @_;
	return Nova::Resource::Spec::Spob->new($self, 'AvailStel');
}

1;
