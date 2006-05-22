#!/usr/bin/perl
use warnings;
use strict;
use Data::Dumper;

package Foo::Bar::Iggy::Blah;


package main;

print "foo\n" if exists $::{'Foo::'};
