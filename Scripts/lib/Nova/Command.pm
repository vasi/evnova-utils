# Copyright (c) 2006 Dave Vasilevsky

package Nova::Command;
use strict;
use warnings;

=head1 NAME

Nova::Command - routines to be run from the command line

=head1 SYNOPSIS

  Nova::Command->run(@ARGV);

=cut

sub run {
	my ($cmd, @args) = @_;
	
	no strict 'refs';
	my $sub = __PACKAGE__ . "::$cmd";
	die "No such command $cmd\n" unless exists &$sub;
	&$sub(@args);
}

sub dump {
	my ($type, $spec) = @_;
}
