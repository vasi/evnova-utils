# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resources;
use strict;
use warnings;

use base 'Nova::Base';
__PACKAGE__->fields(qw(source cache));

use Nova::Cache;
use Nova::Resource;
use Nova::Util qw(deaccent);

use Cwd qw(realpath);

=head1 NAME

Nova::Resources - a collection of resources

=head1 SYNOPSIS

  my $rs = Nova::Resources->new($source);

  $rs->addType($type, @fields);
  $rs->addResource($fieldHash);
  $rs->deleteResource($type, $id);

  my $r = $rs->get($type, $id);
  $r = $rs->find($type, $spec);

  my @types = $rs->types;
  my @resources = $rs->type(@types);

=cut

# my $rs = Nova::Resources->new($source);
#
# Source is the file from which this collection will be filled
sub init {
	my ($self, $source) = @_;
	$source = realpath($source);
	$self->source($source);
	$self->cache(Nova::Cache->cacheForFile($source));
	
	$self->cache->{types} = [] unless exists $self->cache->{types};
}

# my $bool = $rs->isFilled;
#
# Do we have a filled cache to play with? Or do we need to have resource data
# inserted?
sub isFilled {
	my ($self) = @_;
	return defined $self->cache->{filled};
}

# $rs->batch(sub {  });
#
# Perform a series of operations, without updating our cache each time.
# During a batch operation, any accesses to resources are not guaranteed to
# yield consistent data! So don't try :-)
sub batch {
	my ($self, $code) = @_;
	$self->{batch} = 1;
	$code->();
	delete $self->{batch};
	$self->_update;
}

# $rs->_update;
#
# Update the cache to reflect batch changes made since the last update.
sub _update {
	my ($self) = @_;
	return if exists $self->{batch}; # postpone
	
	# for now, nothing is batched
}

# $rs->addType($type, @fields);
#
# Add a type of resource, with the given fields
sub addType {
	my ($self, $type, @fields) = @_;
	die "Read-only!\n" if $self->{readOnly};
	my $deac = deaccent($type);
	
	my $c = $self->cache;
	$c->{types} = [ $self->types, $type ];
	$c->{'fields',$deac} = \@fields;
	$c->{'ids',$deac} = [ ];
	$c->{filled} = 1;
	$self->{typeSort} = 0;
}

# $rs->addResource($fieldHash);
#
# Add a resource.
sub addResource {	
	my ($self, $fieldHash) = @_;
	die "Read-only!\n" if $self->{readOnly};
	my $type = deaccent($fieldHash->{type}->value);
	my $id = $fieldHash->{id}->value;
	
	my $c = $self->cache;
	$c->{'resource',$type,$id} = $fieldHash;
	$c->{'ids',$type} = [ $id, @{$c->{'ids',$type}} ];
	$c->{filled} = 1;
	$self->{idSort}{$type} = 0;
}

# $rs->deleteResource($type, $id);
#
# Remove a resource.
sub deleteResource {	
	my ($self, $type, $id) = @_;
	die "Read-only!\n" if $self->{readOnly};
	$type = deaccent($type);
	
	my $c = $self->cache;
	delete $c->{'resource',$type,$id};
	$c->{'ids',$type} = [ grep { $_ != $id } @{$c->{'ids',$type}} ];
}

# Empty the cache for this collection. This object then ceases to be valid.
sub deleteCache {
	my ($self) = @_;
	Nova::Cache->deleteCache($self->source);
}

# Disconnect this collection from the DB (so it can be modified in-memory)
sub noCache {
	my ($self) = @_;
	$self->cache({ %{$self->cache} });
}

# Make this collection read-only
sub readOnly {
	my ($self) = @_;
	$self->{readOnly} = 1;
}

# Get a single resource by type and ID
sub get {
	my ($self, $type, $id) = @_;
	$type = deaccent($type);
	
	my $c = $self->cache;
	return undef unless exists $c->{'resource',$type,$id};
	
	return Nova::Resource->new(
		fieldNames	=> $c->{'fields',$type},
		fields		=> \$c->{'resource',$type,$id},
		collection	=> $self,
		readOnly	=> $self->{readOnly},
	);
}

# Does a resource exist?
sub exists {
	my ($self, $type, $id) = @_;
	return exists $self->cache->{'resource',$type,$id};
}

# Get all resources of some types
sub type {
	my ($self, @types) = @_;
	@types = $self->types unless @types; # default to all
	
	my @resources;
	for my $type (@types) {
		$type = deaccent($type);
		die "No such type $type\n" unless exists $self->cache->{'ids',$type};
		
		# Sort and uniquify only on-demand
		my @ids = @{$self->cache->{'ids',$type}};
		unless ($self->{idSort}{$type}) {
			my %ids = map { $_ => 1 } @ids;
			@ids = sort { $a <=> $b } keys %ids;
			$self->cache->{'ids',$type} = \@ids;
			$self->{idSort}{$type} = 1;
		}
		
		push @resources, map { $self->get($type, $_) } @ids;
	}
	return @resources;
}

# Get a list of all known types
sub types {
	my ($self) = @_;
	
	# Sort and uniquify only on-demand
	my @types = @{$self->cache->{types}};
	unless ($self->{typeSort}) {
		my %types = map { $_ => 1 } @types;
		@types = map { $_->[0] } sort { $a->[1] cmp $b->[1] }
			map { [ $_, deaccent($_) ] } keys %types; # schwartzian
		$self->cache->{types} = \@types;
		
		$self->{typeSort} = 1;
	}
	return @types;
}

# Find a resource from a specification
sub find {
	my ($self, $type, $spec) = @_;
	$type = deaccent($type);
	
	my @found;
	if ($spec =~ /^\d+$/) {
		@found = ($self->get($type, $spec));
	} else {
		@found = grep { $_->fullName =~ /$spec/i } $self->type($type);
	}
	return wantarray ? @found : $found[0];
}

1;
