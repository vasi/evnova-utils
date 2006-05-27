# Copyright (c) 2006 Dave Vasilevsky
package Nova::Runner::Test;
use strict;
use warnings;

use base qw(Nova::Runner);
use Nova::Runner::Command;

command {
	require Nova::ConText;
	my $in = Nova::ConText->new('../ConText/Test3.txt');
	my $rs = $in->read;
	$rs->noCache;
	
	$rs->get(dude => 128)->name('Test name');
	$rs->get(colr => 128)->buttonUp(0xAABBCC);
	my $r = $rs->newResource('cron');
	$r->name('Cron name');
	$r = $rs->get(char => 128)->duplicate(140);
	$r->startCash(10_000_000);
	
	my $out = Nova::ConText->new('Out.txt');
	$out->write($rs);
} 'test-write' => 'test writing a ConText file';

command {
	require Nova::ConText;
	
	my $file = '../ConText/Test3.txt';
	utime undef, undef, $file; # reload next time
	
	my $in = Nova::ConText->new($file);
	{
		my $rs = $in->read;
		my $r = $rs->get(boom => 128);
		printf "%s\n", $r->name;
		$r->name('changed');
		printf "%s\n", $r->name;
	}
	{
		my $rs = $in->read;
		my $r = $rs->get(boom => 128);
		printf "%s\n", $r->name;
	}
	
	utime undef, undef, $file; # reload next time
} 'test-modify' => 'test modifying a ConText cache';

1;
