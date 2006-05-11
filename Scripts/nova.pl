#!/usr/bin/perl
use warnings;
use strict;

use lib 'lib';


use Nova::Resources;

my $file = '../ConText.txt';
my $resources = Nova::Resources->fromConText($file);
print "$_\n" for $resources->types;