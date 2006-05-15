# Copyright (c) 2006 Dave Vasilevsky
package Nova::Command::ConText;
use strict;
use warnings;

use base 'Nova::Command';
use Nova::Command qw(command);

=head1 NAME

Nova::Command::ConText - commands related to ConText files

=cut

command {
	my ($self, $val) = @_;
	$self->config->conText($val) if defined $val;
	printf "%s\n", $self->config->conText;
} 'context' => 'get/set the ConText file';

=head1 NAME

Nova::Command::ConText::Using - commands that use the contents of the
default ConText file

=cut

package Nova::Command::ConText::Using;
use base 'Nova::Command::ConText';
__PACKAGE__->fields(qw(resources));

use Nova::ConText;
use Nova::Command qw(command);

# Load the current context file
sub _loadContext {
	my ($self) = @_;
	my $ct = Nova::ConText->new($self->config->conText);
	$self->resources($ct->read);
#	$self->resources->readOnly;
}

sub setup {
	my ($self) = @_;
	$self->SUPER::setup;
	$self->_loadContext;
}

command {
	my ($self) = @_;
	$self->resources->deleteCache;
	$self->_loadContext;
} reload => 'reload the ConText';

command {
	my ($self, $type, $id, @fields) = @_;
	print $self->resources->get($type => $id)->show(@fields);
} show => 'show a resource';

command {
	my ($self, @types) = @_;
	map { printf "%s %5d: %s\n", $_->type, $_->id, $_->fullName }
		$self->resources->type(@types);
} listAll => 'list all known resources of the given types';

command {
	my ($self, $type, $find) = @_;
	map { printf "%s %5d: %s\n", $_->type, $_->id, $_->fullName }
		$self->resources->find($type => $find);
} list => 'list resources matching a specification';

command {
	my ($self, $find) = @_;
	my $ship = $self->resources->find(ship => $find);
	$ship->mass(1);
} mass => 'show the total mass available on a ship';

1;
