# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resources;
use strict;
use warnings;

use base 'Nova::Base';
__PACKAGE__->fields(qw(source cache));

use Nova::Cache;
use Nova::Iterator;
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

=private interface

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

=end interface

=cut

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
	return $self->typeIter(@types)->collect;
}

# Like &type, but returns an iterator to improve responsiveness
sub typeIter {
	my ($self, @types) = @_;
	@types = $self->types unless @types;
	
	my @items;
	for my $t (@types) {
		push @items, map { [ $t => $_ ] } $self->ids($t);
	}
	
	return Nova::Iterator->new(sub {
		my $i = shift @items;
		return $i unless defined $i;
		return $self->get(@$i);
	});
}


# Find a resource from a specification
sub find {
	my ($self, @args) = @_;
	my $iter = $self->findIter(@args);
	return wantarray ? $iter->collect : $iter->next;
}

sub _findIDs {
	my ($self, $type, $specs) = @_;
	
	my (@num, @name);
	for my $spec (@$specs) {
		if ($spec =~ /^[\d,-]+$/) {
			push @num, $spec;
		} else {
			push @name, $spec;
		}
	}
	@$specs = @name;
	
	@num = split /,/, join ',', @num;
	return grep { $self->exists($type => $_) }
		map { /^(\d+)-(\d+)$/ ? ($1..$2) : $_ } @num;
}

sub _findNextName {
	my ($self, $type, $ids, @specs) = @_;
	return undef unless @specs;
	
	while (defined (my $id = shift @$ids)) {
		my $r = $self->get($type => $id);
		my $name = $r->fullName;
		for my $spec (@specs) {
			return ($id, $r) if $name =~ /$spec/i;
		}
	}
	return undef;
}

sub findIter {
	my ($self, $type, @specs) = @_;
	return $self->typeIter($type) unless @specs;
	
	my @byNum = $self->_findIDs($type, \@specs);
	@specs = map { qr/$_/i } @specs;
	
	my @ids = $self->ids($type);
	my ($nameID, $nameRes);
	
	return Nova::Iterator->new(sub {
		($nameID, $nameRes) = $self->_findNextName($type, \@ids, @specs)
			unless defined $nameID;
		if (@byNum && (!defined $nameID || $nameID >= $byNum[0])) {
			my $id = shift @byNum;
			undef $nameID if defined $id && defined $nameID && $id == $nameID;
			return undef unless defined $id;
			return $self->get($type => $id);
		} else {
			undef $nameID;
			return $nameRes;
		}
	});
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


1;
