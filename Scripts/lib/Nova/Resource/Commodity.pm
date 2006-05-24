# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Commodity;
use strict;
use warnings;

use base qw(Nova::Base);

=head1 NAME

Nova::Resource::Commodity - A commodity that can be traded

=cut

#### Interface
# sub fullName	{ }
# sub shortName	{ }
# sub basePrice	{ }


# Create a priced version
sub priced {
	my ($self, $level) = @_;
	return Nova::Resource::Commodity::Priced->new($self, $level);
}


# Standard commodity, like equipment
package Nova::Resource::Commodity::Standard;
use base qw(Nova::Resource::Commodity);
__PACKAGE__->fields(qw(collection idx));

our %STRNS = (
	fullName	=> 4000,
	shortName	=> 4002,
	basePrice	=> 4004,
);

sub init {
	my ($self, $collection, $idx) = @_;
	$self->collection($collection);
	$self->idx($idx);
}

{
	while (my ($name, $res) = each %STRNS) {
		__PACKAGE__->makeSub($name => sub {
			return $_[0]->collection->get('STR#' => $STRNS{$name})
				->strings->[$_[0]->idx];
		});
	}
}


# A commodity with a price
package Nova::Resource::Commodity::Priced;
use base qw(Nova::Resource::Commodity);
__PACKAGE__->fields(qw(priceLevel commodity));

our %PRICES = (
	'Low'	=> 4/5,
	'Med'	=> 1,
	'High'	=> 5/4,
);

sub init {
	my ($self, $commodity, $level) = @_;
	$level = ucfirst lc $level;
	die "No such price level '$level'\n" unless exists $PRICES{$level};
	
	$self->commodity($commodity);
	$self->priceLevel($level);
}

{
	for my $sub (qw(fullName shortName basePrice)) {
		__PACKAGE__->makeSub($sub => sub {
			my ($self, @args) = @_;
			return $self->commodity->$sub(@args);
		});
	}
}

sub price {
	my ($self) = @_;
	return $self->basePrice * $PRICES{$self->priceLevel};
}

1;
