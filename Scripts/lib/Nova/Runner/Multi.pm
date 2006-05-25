# Copyright (c) 2006 Dave Vasilevsky
package Nova::Runner::Multi;
use strict;
use warnings;

use base qw(Nova::Base);
__PACKAGE__->fields(qw(runners config));

use Nova::Config;
use Nova::Runner;

sub init {
	my ($self) = @_;
	$self->config(Nova::Config->new);
	$self->runners({ });
}

sub runCommandLine {
	my ($self, @args) = @_;
	
	# Setup a config
	my $co = $self->config->withArgs(\@args);
	
	# Get the command
	my $name = shift @args;
	$name = 'help' unless defined $name;
	my $cmd = Nova::Runner->getCommand($name);
	
	# Get a runner
	my $runnerPkg = $cmd->runner;
	unless (exists $self->runners->{$runnerPkg}) {
		$self->runners->{$runnerPkg} = $runnerPkg->new($co);
	}
	my $runner = $self->runners->{$runnerPkg};
	
	# Go!
	$runner->run($cmd, $co, @args);
}
	
sub serve {
	# FIXME: implement
}

1;
