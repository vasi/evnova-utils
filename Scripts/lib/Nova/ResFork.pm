# Copyright (c) 2006 Dave Vasilevsky
package Nova::ResFork;
use strict;
use warnings;

use base qw(Nova::Resources);
__PACKAGE__->fields(qw(rfd reaccentHash));

use Nova::Util qw(deaccent);
use Mac::Memory;
use Mac::Files;
use Mac::Resources;
use Encode;

=head1 NAME

Nova::ResFork - A collection of resources from a resource fork

=cut

# my $rs = Nova::ResFork->new($file);
#
# Create a new ResFork collecting the resource fork of $rs.
sub init {
	my ($self, $file) = @_;
	$self->SUPER::init($file);
	$self->rfd(FSpOpenResFile($file, 0));
	
	$self->reaccentHash({ map { deaccent($_) => $_ } $self->types });
}

sub DESTROY {
	my ($self) = @_;
	CloseResFile($self->rfd) if defined $self->rfd;
}

sub types {
	my ($self) = @_;
	return () unless defined $self->rfd;
	
	UseResFile($self->rfd);
	return sort map { decode('MacRoman', Get1IndType($_)) } (1..Count1Types);
}

# $type = $self->_check($type);
#
# Check that our resource fork is present, and re-accent the type
sub _check {
	my ($self, $type) = @_;
	die "No resource fork\n" unless defined $self->rfd;
	UseResFile($self->rfd);
	
	$type = $self->reaccent($type);
	$type = encode('MacRoman', $type);
	return $type;
}

sub nextUnused {	# Prefer the system call
	my ($self, $type) = @_;
	return Unique1ID($self->_check($type));
}

# FIXME: implement

# my $resource = $rs->newResource($type => $id);
# my $resource = $rs->newResource($type);
#sub newResource { }

# my $resource = $rs->addResource($fieldHash);
# my $resource = $rs->addResource($resource);
#sub addResource { }

# $rs->deleteResource($type, $id);
#sub deleteResource { }

# Get a single resource by type and ID
#sub get { }

# Does a resource exist?
sub exists {
	my ($self, $type, $id) = @_;
	$type = $self->_check($type);
	my $h = Get1Resource($type, $id);
	return defined $h;
}

# Get all ids of a type
sub ids {
	my ($self, $type) = @_;
	$type = $self->_check($type);
	
	SetResLoad(0); # Don't read handles
	my $count = Count1Resources($type);
	my @handles = map { Get1IndResource($type, $_) } (1..$count);
	
	my @ids;
	for my $h (@handles) {
		my ($id) = GetResInfo($h);
		push @ids, $id;
	}
	SetResLoad(1);
	
	return @ids;
}

# Faster implementation
sub reaccent {
	my ($self, $type) = @_;
	return $self->reaccentHash->{deaccent($type)};
}

# Dump a list of resources in this ResFork
sub dump {
	my ($self) = @_;
	return sprintf "%s: no resource fork\n", $self->source
		unless defined $self->rfd;
	
	my @types = $self->types;
	return sprintf "%s: empty resource fork\n", $self->source unless @types;
	
	my $str = $self->source . ":\n";
	for my $t (@types) {
		my @ids = $self->ids($t);
		$str .= sprintf "  %4s: %5d\n", $t, scalar(@ids);
	}
	return $str;
}

# TODO:
#	- creation, deletion of entire fork?
#	- individual resources
#	- test cross-compatibility with ConText
#	- writing

1;
