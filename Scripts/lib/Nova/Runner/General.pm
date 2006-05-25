# Copyright (c) 2006 Dave Vasilevsky
package Nova::Runner::General;
use strict;
use warnings;

use base qw(Nova::Runner);
use Nova::Runner::Command;

use Nova::ResFork;

# Print help for this command
sub printHelp {
	my ($cmd) = @_;
	printf "  %-15s - %s\n", $cmd->name, $cmd->help;
}

# Print an entire category of commands
sub printCategory {
	my ($cat, $name) = @_;
	print "\n$name:\n";
	printHelp($_) for @$cat;
}

command {
	my ($config, $name) = @_;
	if (defined $name) {
		my $cmd = Nova::Runner->getCommand($name);
		printHelp($cmd);
	} else {			# Print all help
		printf "%s - EV Nova command line tool\n", $0;
		
		my $cats = Nova::Runner->getCategories;
		printCategory($cats->{$_}, $_) for sort keys %$cats;
	}
} help => 'get help on available commands';

command {
	my ($config, @files) = @_;
	
	for my $i (0..$#files) {
		my $rs = Nova::ResFork->new($files[$i]);
		print $rs->dump;
		print "\n" unless $i == $#files;
	}
} rsrc => 'count the resources in files';


1;
