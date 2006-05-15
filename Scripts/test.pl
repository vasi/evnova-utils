#!/usr/bin/perl
use warnings;
use strict;
use Data::Dumper;

use lib 'lib';


use MLDBM qw(DB_File Storable);

unlink '/tmp/foo';
{
	my %h;
	tie %h, MLDBM => '/tmp/foo';
	$h{foo} = { first => 5 };
	
	my $obj;
	$obj->{fields} = \$h{foo};
	
	printf "%s\n", exists ${$obj->{fields}}->{first};
	${$obj->{fields}}->{bar} = {iggy => 'blah'};
	${$obj->{fields}} = { %${$obj->{fields}} };
	print Dumper(${$obj->{fields}});
}
{
	my %h;
	tie %h, MLDBM => '/tmp/foo';
	print Dumper(\%h);
}
