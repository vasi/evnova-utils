# Copyright (c) 2006 Dave Vasilevsky
package Nova::Command::Test;
use strict;
use warnings;

use base 'Nova::Command';
use Nova::Command qw(command);

command {
	my ($self) = @_;
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


1;
