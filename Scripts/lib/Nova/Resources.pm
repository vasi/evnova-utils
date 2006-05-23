# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resources;
use strict;
use warnings;

use base 'Nova::Base';
__PACKAGE__->fields(qw(source cache));

use Nova::Cache;
use Nova::Resource;
use Nova::Util qw(deaccent);

use List::Util qw(max);

=head1 NAME

Nova::Resources - a collection of resources

=head1 SYNOPSIS

  # Create a collection
  my $rs = Nova::Resources->new($source);

  
  # Get resources
  my $r = $rs->get($type => $id);
  my @r = $rs->find($type => $spec);

  my @types = $rs->types;
  my @r = $rs->type(@types);

  my $bool = $rs->exists($type => $id);
  my @ids = $rs->ids($type);
  my $id = $rs->nextUnused($type);


  # Change things
  $rs->addResource($fieldHash);
  $rs->addResource($resource);

  $rs->newResource($type => $id);
  $rs->newResource($type);

  $rs->deleteResource($type, $id);


  # Misc
  $rs->store;			# Get/set arbitrary params
  $rs->store($val);

  $rs->source;			# What file are we based on?

=cut

# my $rs = Nova::Resources->new($source);
#
# Source is the file from which this collection will be filled
sub init {
	my ($self, $source) = @_;
	$self->source($source);
}


# my $resource = $rs->newResource($type => $id);
# my $resource = $rs->newResource($type);
sub newResource { }

# my $resource = $rs->addResource($fieldHash);
# my $resource = $rs->addResource($resource);
sub addResource { }

# $rs->deleteResource($type, $id);
sub deleteResource { }

# Get a single resource by type and ID
sub get { }

# Does a resource exist?
sub exists { }

# Get all ids of a type
sub ids { }

# Get a list of all known types
sub types { }


# Get the next unfilled resource of a type
sub nextUnused {
	my ($self, $type) = @_;
	my @ids = $self->ids($type);
	my $max = max @ids;
	return defined $max ? $max + 1 : 128;
}

# Get all resources of some types
sub type {
	my ($self, @types) = @_;
	@types = $self->types unless @types; # default to all
	
	my @resources;
	for my $type (@types) {
		push @resources, map { $self->get($type, $_) } $self->ids($type);
	}
	return @resources;
}


# Return IDs for one spec
sub _findOne {
	my ($self, $type, $spec) = @_;
	
	if ($spec =~ /^[\d,-]+$/) {
		my @specs = split /,/, $spec;
		return map { /^(\d+)-(\d+)$/ ? ($1..$2) : $_ } @specs;
	} else {
		return map { $_->ID }
			grep { $_->fullName =~ /$spec/i } $self->type($type);
	}
}

# Find a resource from a specification
sub find {
	my ($self, $type, @specs) = @_;
	$type = deaccent($type);
	
	my @found;
	if (@specs) {
		my %ids = map { $_ => 1 } map { $self->_findOne($type, $_) } @specs;
		@found = map { $self->get($type => $_) } sort { $a <=> $b } keys %ids;
	} else {
		@found = $self->type($type);
	}
	return wantarray ? @found : $found[0];
}

# Store an arbitrary value to a key
sub store {
	my ($self, $key, $val) = @_;
	$self->{store}{$key} = $val if defined $val;
	return $self->{store}{$key};
}

# Restore the accents of a type
sub reaccent {
	my ($self, $type) = @_;
	$type = deaccent($type);
	my ($ret) = grep { deaccent($_) eq $type } $self->types;
	return $ret;
}

# Like &type, but returns an iterator to improve responsiveness
sub iter {
	my ($self, @types) = @_;
	@types = $self->types unless @types;
	return Nova::Resources::Iterator->new($self, @types);
}


package Nova::Resources::Iterator;
use base qw(Nova::Base);
__PACKAGE__->fields(qw(collection types type ids));

sub init {
	my ($self, $collection, @types) = @_;
	$self->collection($collection);
	$self->types(\@types);
	$self->ids([]);
}

sub next {
	my ($self) = @_;
	
	my $id = shift @{$self->ids};
	until (defined $id) {
		defined( $self->type(shift @{$self->types}) ) or return undef;
		$self->ids([ $self->collection->ids($self->type) ]);
		$id = shift @{$self->ids};
	}
	
	return $self->collection->get($self->type => $id);
}

1;
