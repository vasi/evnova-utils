# Copyright (c) 2006 Dave Vasilevsky
package Nova::Runner;
use strict;
use warnings;

use base qw(Nova::Base);


our %COMMANDS;		# Known commands
our %CATEGORIES;	# Known categories of commands (for help)

__PACKAGE__->subPackages;

sub commandLine {
	my ($class, @args) = @_;
	
	require Nova::Runner::Multi;
	Nova::Runner::Multi->new->runCommandLine(@args);
}

sub register {
	my ($class, $cmd) = @_;
	$COMMANDS{lc $cmd->name} = $cmd;
	push @{$CATEGORIES{$cmd->category}}, $cmd;
}

sub getCommand {
	my ($class, $name) = @_;
	die "No such command '$name'\n" unless exists $COMMANDS{lc $name};
	return $COMMANDS{lc $name};
}

sub getCategories {
	my ($class, $name) = @_;
	return \%CATEGORIES;
}

sub run {
	my ($self, $cmd, $config, @args) = @_;
	$cmd->run($config, @args);
}


1;
