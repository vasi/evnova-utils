# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Spec::Govt;
use strict;
use warnings;

use base qw(Nova::Resource::Spec);
__PACKAGE__->fields(qw(type govt));

use Nova::Resource::Type::Govt;

=head1 NAME

Nova::Resource::Spec::Govt - A specification for a govt

=cut


sub init {
	my ($self, @args) = @_;
	$self->SUPER::init(@args);
	
	my $spec = $self->spec;
	my $type = int(($spec + 1) / 1000);
	my $id = $spec - ($type * 1000);
	$id -= 128 if $type;
	
	# Special cases
	$id = -1 if $id == 127;
	$type = 0 if $type == 10;
	
	$self->spec(-1) if $id == -1;
	$self->type($type);
	$self->govt(Nova::Resource::Type::Govt->fromCollection(
		$self->collection, $id));
	
	die "No govt type $type\n" unless exists $REGISTERED{$self->type};
	bless $self, $REGISTERED{$self->type};
}

sub descFormat { "govt %s" }

sub desc {
	my ($self) = @_;
	my $g = sprintf "%s (%d)", $self->govt->name, $self->govt->ID;
	return sprintf $self->descFormat, $g;
}


package Nova::Resource::Spec::Govt::Ally;
use base qw(Nova::Resource::Spec::Govt);
__PACKAGE__->register(15);
sub descFormat { "ally of govt %s" }

package Nova::Resource::Spec::Govt::Not;
use base qw(Nova::Resource::Spec::Govt);
__PACKAGE__->register(20);
sub descFormat { "any govt but %s" }

package Nova::Resource::Spec::Govt::Enemy;
use base qw(Nova::Resource::Spec::Govt);
__PACKAGE__->register(25);
sub descFormat { "enemy of govt %s" }

package Nova::Resource::Spec::Govt::Class;
use base qw(Nova::Resource::Spec::Govt);
__PACKAGE__->register(30);
sub descFormat { "class-mate of govt %s" }

package Nova::Resource::Spec::Govt::NotClass;
use base qw(Nova::Resource::Spec::Govt);
__PACKAGE__->register(31);
sub descFormat { "non-class-mate of govt %s" }



1;
