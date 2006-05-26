# Copyright (c) 2006 Dave Vasilevsky
package Nova::Runner::Server;
use strict;
use warnings;

use base qw(Nova::Runner);
use Nova::Runner::Command;

use Nova::Client;

use IO::Socket::INET;
use URI::Escape;

command {
	my ($config, $port) = @_;
	$port = $Nova::Client::PORT unless defined $port;
	
	require Nova::Runner::Multi;
	my $multi = Nova::Runner::Multi->new($config);
	
	my $sr = IO::Socket::INET->new(
		Listen		=> 100,
		LocalAddr	=> 'localhost',
		LocalPort	=> $port,
		ReuseAddr	=> 1,
	) or die "Can't listen: $!\n";
	print "Serving...\n";
	
	while (1) {
		my $cn = $sr->accept() or next; # accept new connection or loop on error
		# no forking!
		
		open my $saveout, '>&', STDOUT or die "Can't save STDOUT\n";
		eval {
			my $request = <$cn>;
			my @args = split ' ', $request;
			@args = map { uri_unescape($_) } @args;
			
			print "Request: ", join(' ', @args), "\n";
			open STDOUT, '>&', $cn or die "Can't reopen STDOUT\n";
			binmode STDOUT, ':utf8';
			
			$multi->runCommandLine(@args);
		};
		print $@ if $@;
		
		close $cn;
		close STDOUT;
		open STDOUT, '>&', $saveout;
		close $saveout;	
	}
} serve => 'run as a server';

command {
	my ($config) = @_;
	exit 0;
} quit => 'quit the server';



1;
