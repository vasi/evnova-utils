# Copyright (c) 2006 Dave Vasilevsky
package Nova::Runner::Command;
use strict;
use warnings;

use base qw(Nova::Base Exporter);
our @EXPORT = qw(command);
__PACKAGE__->fields(qw(help name code category runner));

use Nova::Runner;

# command { ... } foo => "do foo";
#
# Create and register a command, which runs the given code, has name 'foo',
# and has the help string 'do foo'.
sub command (&$$;$) {
	my ($sub, $name, $help, $cat) = @_;
	my $pkg = scalar(caller);
	
	my $root = 'Nova::Runner';
	($cat = $pkg) =~ s/${root}(::)?([^:]*).*/$2/ unless defined $cat;
	
	my $cmd = __PACKAGE__->new(code => $sub, name => $name, help => $help,
		category => $cat, runner => $pkg);
	Nova::Runner->register($cmd);
}

# Run this command
sub run {
	my ($self, @args) = @_;
	$self->code->(@args);
}

1;
