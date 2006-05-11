# Copyright (c) 2006 Dave Vasilevsky
package Nova::Config;
use strict;
use warnings;

use base qw(Nova::Base);

use YAML;
use File::Spec::Functions qw(catfile);
use Cwd	qw(realpath);
use Getopt::Long qw(:config bundling pass_through);

my $CONFIG_FILE = '.nova';

sub _init {
	my ($self, $args) = @_;
	eval {
		my $config = YAML::LoadFile($self->configFile);
		%$self = %$config;
	};
	
	# Handle options
	$DB::single = 1;
	{
		local @ARGV = @$args;
		GetOptions(
			'context|c=s'	=> \$self->{conText},
		) or die "Bad options!\n";
		@$args = @ARGV;
	}
}

sub configFile {
	return catfile($ENV{HOME}, $CONFIG_FILE);
}

sub DESTROY {
	my ($self) = @_;
	YAML::DumpFile($self->configFile, $self);
}

# Get the context file.
sub conText {
	my ($self, $val) = @_;
	$self->{conText} = realpath($val) if defined $val;
	die "No ConText set in config\n" unless defined $self->{conText};
	return $self->{conText};
}


1;
