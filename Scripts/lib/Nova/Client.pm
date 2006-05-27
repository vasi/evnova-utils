# Copyright (c) 2006 Dave Vasilevsky
package Nova::Client;
use strict;
use warnings;

use Getopt::Long qw(:config bundling pass_through);
use Nova::Util qw(termWidth);

our $PORT = 5794;

sub commandLine {
	my ($class, @args) = @_;
	
	my $port;
	{
		local @ARGV = @args;
		GetOptions('p|port:i' => \$port);
		@args = @ARGV;
	}
	
	if (defined $port) {
		$port = $PORT unless $port;
		$class->askServer($port, @args);
	} else {
		require Nova::Runner;
		Nova::Runner->commandLine(@args);
	}
}

sub askServer {
	my ($class, $port, @args) = @_;
	require IO::Socket::INET;
	require URI::Escape;
	
	my $cn = IO::Socket::INET->new(
		PeerAddr => 'localhost',
		PeerPort => $port,
	) or die "Cannot connect to server!\n";
	
	@args = ('--width', termWidth(), @args);
	@args = map { URI::Escape::uri_escape_utf8($_) } @args;
	my $request = join ' ', @args;
	print $cn "$request\n";
	
	while (<$cn>) {
		print;
	}
	close $cn;
}

1;
