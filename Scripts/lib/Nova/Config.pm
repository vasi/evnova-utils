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
	$self->{persistent} = { };
	eval {
		my $config = YAML::LoadFile($self->configFile);
		$self->{persistent} = $config;
	};
	
	# Handle options
	{
		local @ARGV = @$args;
		GetOptions(
			'context|c=s'	=> sub { $self->runtime(conText => $_[1]) },
		) or die "Bad options!\n";
		@$args = @ARGV;
	}
}

sub configFile {
	return catfile($ENV{HOME}, $CONFIG_FILE);
}

sub DESTROY {
	my ($self) = @_;
	YAML::DumpFile($self->configFile, $self->{persistent});
}

sub option {
	my ($self, $name) = @_;
	return $self->{runtime}{$name} if defined $self->{runtime}{$name};
	return $self->{persistent}{$name};
}

sub persist {
	my ($self, $name, $val) = @_;
	$self->{persistent}{$name} = $val;
}
	
sub runtime {
	my ($self, $name, $val) = @_;
	$self->{runtime}{$name} = $val;
}
	
# Get/set the context file.
sub conText {
	my ($self, $val) = @_;
	$self->persist(conText => realpath($val)) if defined $val;
	
	my $context = $self->option('conText');
	die "No ConText set in config\n" unless defined $context;
	return $context;
}


1;
