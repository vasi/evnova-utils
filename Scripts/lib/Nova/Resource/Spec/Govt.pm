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

our %TYPES = (
	0	=> [ 'govt %s',						'self'			],
	15	=> [ 'ally of govt %s',				'allies'		],
	20	=> [ 'any govt but %s',				'others'		],
	25	=> [ 'enemy of govt %s',			'enemies'		],
	30	=> [ 'class-mate of govt %s',		'classMates'	],
	31	=> [ 'non-class-mate of govt %s',	'nonClassMates' ],
);

sub init {
	my ($self, @args) = @_;
	$self->SUPER::init(@args);
	
	my $spec = $self->spec;
	my $type = int(($spec + 1) / 1000);
	my $id = $spec - ($type * 1000);
	$id += 128 if $type;
	
	# Special cases
	$id = -1 if $id == 127;
	$type = 0 if $type == 10;

	$self->spec(-1) if $id == -1;
	$self->type($type);
	$self->govt(Nova::Resource::Type::Govt->fromCollection(
		$self->collection, $id));
}

sub descFormat { $TYPES{$_[0]->type}[0] };

sub desc {
	my ($self) = @_;
	my $g = sprintf "%s (%d)", $self->govt->name, $self->govt->ID;
	return sprintf $self->descFormat, $g;
}

sub govts {
	my ($self) = @_;
	my $meth = $TYPES{$self->type}[1];
	return $self->govt->$meth;
}

