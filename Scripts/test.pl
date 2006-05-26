#!/usr/bin/perl
use warnings;
use strict;
binmode STDOUT, ':utf8';
use Data::Dumper;

use lib 'lib';

use Nova::ConText;
Nova::ConText->findNonprintables(1, glob('../Context/*.txt'));
