# Copyright (c) 2006 Dave Vasilevsky
package Nova::Config;
use strict;
use warnings;

use base qw(Nova::Base);

use YAML;
use File::Spec::Functions qw(catfile);
use Cwd qw(realpath);

my $CONFIG_FILE = '.nova';

sub _init {
$DB::single = 1;
	my ($self) = @_;
	eval {
		my $config = YAML::LoadFile($self->configFile);
		%$self = %$config;
	};
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
