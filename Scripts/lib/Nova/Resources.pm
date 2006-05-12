# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resources;
use strict;
use warnings;

use base 'Nova::Base';

use Nova::Cache;
use Nova::ConText;
use Nova::Resource;
use Nova::Util qw(deaccent);

use Cwd qw(realpath);

=head1 NAME

Nova::Resource - a collection of resources

=head1 SYNOPSIS

  my $resources = Nova::Resources->fromConText($file);
  
  my $res = $resources->get($type, $id);
  my @res = $resources->type($type);
  my @res = $resources->find($type => $spec);
  my @types = $resources->types;
  
  my $source = $resources->source;

=cut

sub _init {
	my ($self, $source, $cache) = @_;
	$self->{source} = $source;
	$self->{cache} = $cache;
}

sub fromConText {
	my ($class, $file) = @_;
	my $source = realpath($file);
	my $cache = Nova::Cache->cache($source);
	
	unless ($cache->{done}) {
		my ($headers, $resources) = Nova::ConText->new($file)->read;
		my %types;
		
		while (my ($k, $v) = each %$headers) {
			$cache->{'header',$k} = $v;
		}
		for my $r (@$resources) {
			my $type = $r->{type}->value;
			my $id = $r->{id}->value;
			push @{$types{$type}}, $id;
			$cache->{'resource',$type,$id} = $r;
		}
		$cache->{'type',$_} = $types{$_} for keys %types;
		$cache->{types} = [ sort keys %types ];
		$cache->{done} = 1;
	}
	return $class->new($source, $cache);
}

sub deleteCache {
	my ($self) = @_;
	Nova::Cache->deleteCache($self->source);
}

# Get a single resource by type and ID
sub get {
	my ($self, $type, $id) = @_;
	$type = deaccent($type);
	
	my $c = $self->{cache};
	die "No such resource $id of type $type\n"
		unless exists $c->{'resource',$type,$id};
	
	return Nova::Resource->new(
		$c->{'resource',$type,$id},	# fields
		$c->{'header',$type},		# headers
		$self,						# collection
	);
}

# Get all resources some types
sub type {
	my ($self, @types) = @_;
	@types = map { deaccent(@_) } @types;
	@types = $self->types unless @types; # default to all
	
	my @resources;
	for my $type (@types) {
		die "No such type $type\n" unless exists $self->{cache}{'type',$type};
		push @resources,
			map { $self->get($type, $_) } @{$self->{cache}{'type',$type}};
	}
	return @resources;
}

# Get a list of all known types
sub types {
	my ($self) = @_;
	return @{$self->{cache}{types}};
}

# Get an identifier for the place this collection came from
sub source {
	my ($self) = @_;
	return $self->{source};
}

# Find a resource from a specification
sub find {
	my ($self, $type, $spec) = @_;
	$type = deaccent($type);
	
	my @found;
	if ($spec =~ /^\d+$/) {
		@found = ($self->get($type, $spec));
	} else {
		@found = grep { $_->name =~ /$spec/i } $self->type($type);
	}
	return wantarray ? @found : $found[0];
}

1;
