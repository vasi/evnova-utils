# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Syst;
use strict;
use warnings;

use base qw(Nova::Base);
__PACKAGE__->fields(qw(adjacentCache));

use Nova::Resource;
use Nova::Cache;

sub spobs {
	my ($self) = @_;
	return map { $self->collection->get(spob => $_) } $self->multi('nav');
}

sub importantBitFields { qw(Visibility) }

sub showDist {
	my ($self, $other, $verb) = @_;
	
	return sprintf "Distance: %d\n", $self->dist($other);
	
	# FIXME: show path
}

sub _distCache {
	my ($self, $name) = @_;
	my $cache = $self->collection->store($name);
	unless (defined $cache) {
		$cache = Nova::Cache->cacheForFile($self->source, $name);
		$self->collection->store($name => $cache);
	}
	return $cache;
}

sub dist {
	my ($self, $other) = @_;
	my $cache = $self->_distCache('systDist');
	
	my ($i1, $i2) = map { $_->ID } ($self, $other);
	
	my @order;
	if (exists $cache->{'calc',$i1}) {
		@order = ($i1, $i2);
	} elsif (exists $cache->{'calc',$i2}) {
		@order = ($i2, $i1);
	} else {
		$self->_calcDistances($cache);
		@order = ($i1, $i2);
	}
	
	my $key = join($;, 'dist', @order);
	die "No path from syst ID $i1 to syst ID $i2\n"
		unless exists $cache->{$key};
	return $cache->{$key};
}

# NB: Does not include hypergates
sub adjacent {
	my ($self) = @_;
	unless (defined $self->adjacentCache) {
		$self->adjacentCache([ $self->multi('con') ]);
	}
	return map { $self->collection->get(syst => $_) } @{$self->adjacentCache};
}

sub _calcDistances {
	my ($self, $cache) = @_;
	my $id = $self->ID;
	
	# Path to self
	$cache->{'dist',$id,$id} = 0;
	$cache->{'path',$id,$id} = [ ];
	
	my %seen = ($id => []);
	my @edge = ($self);
	while (defined (my $syst = pop @edge)) {
		my $sid = $syst->ID;
		my @path = @{$seen{$sid}};
		my $dist = scalar(@path) + 1;
		for my $adj ($syst->adjacent) {
			my $aid = $adj->ID;
			next if $seen{$aid};
			
			my $np = [ @path, $aid ];
			$cache->{'dist',$id,$aid} = $dist;
			$cache->{'path',$id,$aid} = $np;
			$seen{$aid} = $np;
			unshift @edge, $adj;
		}
	}
	
	$cache->{'calc',$id} = 1;
}

1;
