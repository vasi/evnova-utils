# Copyright (c) 2006 Dave Vasilevsky

package Nova::ConText::Resources;
use strict;
use warnings;

use base 'Nova::Resources';
__PACKAGE__->fields(qw(cache fieldNameCache resCache));

use Nova::Cache;
use Nova::ConText::Resource;
use Nova::Util qw(deaccent);

use Cwd qw(realpath);
use List::Util qw(max);
use Scalar::Util qw(blessed weaken);

=head1 NAME

Nova::ConText::Resources - a collection of resources from a ConText file

=cut

# my $rs = Nova::ConText::Resources->new($source);
#
# Make an empty collection.
sub init {
	my ($self, $source) = @_;
	$source = realpath($source);
	$self->SUPER::init($source);
	
	$self->cache(Nova::Cache->cacheForFile($source));
	$self->cache->{types} = [] unless exists $self->cache->{types};
	
	$self->fieldNameCache({ });
	$self->resCache({ });
}

# my $bool = $rs->isFilled;
#
# Do we have a filled cache to play with? Or do we need to have resource data
# inserted?
sub isFilled {
	my ($self) = @_;
	return defined $self->cache->{filled};
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
	
	$self->fieldNameCache->{$deac} = \@fields;
}

# my $resource = $rs->newResource($type => $id);
# my $resource = $rs->newResource($type);
sub newResource {
	my ($self, $type, $id) = @_;
	$type = $self->reaccent($type);
	$id = $self->nextUnused($type) unless defined $id;
	
	my @fields = @{$self->_fieldNames(deaccent($type))};
	my $fieldHash = Nova::Resource->newFieldHash($type, $id, @fields);
	return $self->addResource($fieldHash);
}


# my $resource = $rs->addResource($fieldHash);
# my $resource = $rs->addResource($resource);
#
# Add a resource. Key names should be lower case!
sub addResource {	
	my ($self, $fieldHash) = @_;
	die "Read-only!\n" if $self->{readOnly};

	eval { $fieldHash = $fieldHash->typedFieldHash };
	eval { $fieldHash = $fieldHash->fieldHash } if $@;
	
	for my $k (keys %$fieldHash) {
		$fieldHash->{$k} = Nova::ConText::Value->fromScalar($fieldHash->{$k});
	}
	
	my $type = deaccent($fieldHash->{type}->value);
	my $id = $fieldHash->{id}->value;		
	
	my $c = $self->cache;
	$c->{'resource',$type,$id} = $fieldHash;
	$c->{'ids',$type} = [ $id, @{$c->{'ids',$type}} ];
	$c->{filled} = 1;
	$self->{idSort}{$type} = 0;
	
	return $self->get($type => $id);
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
	
	if (defined $self->resCache->{$type,$id}) {
		my $strong = $self->resCache->{$type,$id};
		return $strong;
	} else {
		my $c = $self->cache;
		return undef unless exists $c->{'resource',$type,$id};
		
		my $res = Nova::ConText::Resource->new(
			fieldNames	=> $self->_fieldNames($type),
			fields		=> \$c->{'resource',$type,$id},
			collection	=> $self,
			readOnly	=> $self->{readOnly},
		);
		$self->resCache->{$type,$id} = $res;
		weaken($self->resCache->{$type,$id});
		return $res;
	}
}

# Does a resource exist?
sub exists {
	my ($self, $type, $id) = @_;
	return exists $self->cache->{'resource',$type,$id};
}

# Get all ids of a type
sub ids {
	my ($self, $type) = @_;
	$type = deaccent($type);
	die "No such type '$type'\n" unless exists $self->cache->{'ids',$type};
	
	# Sort and uniquify only on-demand
	my @ids = @{$self->cache->{'ids',$type}};
	unless ($self->{idSort}{$type}) {
		my %ids = map { $_ => 1 } @ids;
		@ids = sort { $a <=> $b } keys %ids;
		$self->cache->{'ids',$type} = \@ids;
		$self->{idSort}{$type} = 1;
	}
	
	return @ids;
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

sub _fieldNames {
	my ($self, $deac) = @_;
	unless (exists $self->fieldNameCache->{$deac}) {
		$self->fieldNameCache->{$deac} = $self->cache->{'fields',$deac};
	}
	return $self->fieldNameCache->{$deac};
}

1;
