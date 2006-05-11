#!/usr/bin/perl
use warnings;
use strict;
use Data::Dumper;

use lib 'lib';

use Nova::Util qw(methods);

sub cmd_foo { print "foo\n" }
sub cmd_bar { print "bar\n" }

my @commands = grep /^cmd_/, methods(__PACKAGE__);
for my $c (@commands) {
	${main::}{$c}();
}
