#!/usr/bin/perl
use warnings;
use strict;

use lib 'lib';

use Nova::Client;
Nova::Client->commandLine(@ARGV);

