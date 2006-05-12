# Copyright (c) 2006 Dave Vasilevsky
package Nova::Command::ConText;
use strict;
use warnings;

use base 'Nova::Command';
use Nova::Command qw(command);

command {
	my ($self, $val) = @_;
	$self->config->conText($val) if defined $val;
	printf "%s\n", $self->config->conText;
} 'context' => 'get/set the ConText file';


package Nova::Command::ConText::Using;
use base 'Nova::Command::ConText';

use Nova::Resources;
use Nova::Command qw(command);

sub loadContext {
	my ($self) = @_;
	$self->{resources} = Nova::Resources->fromConText($self->config->conText);
}

sub setup {
	my ($self) = @_;
	$self->SUPER::setup;
	$self->loadContext;
}

sub resources { $_[0]->{resources} }

command {
	my ($self, $type, $id) = @_;
	print $self->resources->get($type => $id)->dump;
} 'dump' => 'dump a resource';

command {
	my ($self, @types) = @_;
	map { printf "%s %5d: %s\n", $_->type, $_->id, $_->name }
		$self->resources->type(@types);
} listAll => 'list all known resources of the given types';

command {
	my ($self) = @_;
	$self->resources->deleteCache;
	$self->loadContext;
} reload => 'reload the ConText';

1;
