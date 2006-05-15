# Copyright (c) 2006 Dave Vasilevsky
package Nova::Command;
use strict;
use warnings;

use base qw(Nova::Base Exporter);
our @EXPORT_OK = qw(command);
Nova::Config->fields(qw(help name config code));

use Nova::Resources;
use Nova::Config;

use File::Spec::Functions qw(catdir abs2rel);
use File::Find;

=head1 NAME

Nova::Command - parse the command line, and run the appropriate command

=head1 SYNOPSIS

  Nova::Command->execute(@ARGV);

=cut

# Globals
our %COMMANDS;		# Known commands
our %CATEGORIES;	# Known categories of commands (for help)

# Nova::Command->execute(@ARGV);
#
# Run the command line
sub execute {
	my ($class, @args) = @_;
	__PACKAGE__->subPackages; # load them	
	
	my $config = Nova::Config->new(\@args);
	
	my $cmd = shift @args;
	die "No such command '$cmd'\n" unless exists $COMMANDS{lc $cmd};
	$COMMANDS{lc $cmd}->run($config, @args);
}

# Do any preflight before running this command
sub setup {
	# Intentionally left blank
}

# Run this command
sub run {
	my ($self, $config, @args) = @_;
	$self->{config} = $config;
	$self->{args} = \@args;
	
	$self->setup();
	$self->{sub}->($self, @{$self->{args}});
}

# command { ... } foo => "do foo";
#
# Create and register a command, which runs the given code, has name 'foo',
# and has the help string 'do foo'.
sub command (&$$) {
	my ($sub, $name, $help) = @_;
	my $pkg = scalar(caller);
	my $cmd = $pkg->new(code => $sub, name => $name, help => $help);
	$COMMANDS{lc $name} = $cmd;
	
	my $root = __PACKAGE__;
	$pkg =~ s/${root}(::)?([^:]*).*/$2/;
	push @{$CATEGORIES{$pkg}}, $cmd;
}

# Print help for this command
sub _printHelp {
	my ($self) = @_;
	printf STDERR "  %-15s - %s\n", $self->name, $self->help;
}

# Print an entire category of commands
sub _printCategory {
	my ($self, $cat, $name) = @_;
	print STDERR "\n$name:\n";
	$_->_printHelp for @{$CATEGORIES{$cat}};
}

command {
	my ($self, $cmd) = @_;
	if (defined $cmd) {
		if (exists $COMMANDS{lc $cmd}) {
			my $cmd = $COMMANDS{lc $cmd};
			$cmd->_printHelp;
			exit 0;
		} else {
			print STDERR "No such command '$cmd'\n\n";
			# continue
		}
	}
	
	# Print all help
	printf "%s - EV Nova command line tool\n", $0;
	$self->_printCategory('', 'General');
	$self->_printCategory($_, $_) for grep { "$_" } keys %CATEGORIES;
} help => 'get help on available commands';

1;
