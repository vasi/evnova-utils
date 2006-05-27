#!/usr/bin/perl
use warnings;
use strict;
binmode STDOUT, ':utf8';
use Data::Dumper;


package T;
use Scalar::Util qw(weaken);

sub new {
	my ($class, $name) = @_;
	$class = ref($class) || $class;
	return bless { name => $name }, $class;
}

sub child {
	my ($self, $name) = @_;
	my $c = $self->new($name);
	$c->{parent} = $self;
	$self->{cache}->{$name} = $c;
	weaken($self->{cache}->{$name});
	return $c;
}

sub DESTROY {
	my ($self) = @_;
	print "Destroy: $self->{name}\n";
}


package main;

{
	my $x = T->new('x');
	my $y = $x->child('y');
	print "Done block\n";
}
print "Done code\n";
