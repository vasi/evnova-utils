# Copyright (c) 2006 Dave Vasilevsky
package Nova::Config;
use strict;
use warnings;

use base qw(Nova::Base);
Nova::Config->fields(qw(modified));

use YAML;
use File::Spec::Functions qw(catfile);
use Cwd	qw(realpath);
use Getopt::Long qw(:config bundling pass_through);

=head1 NAME

Nova::Config - Configuration for EV Nova scripts

=head1 SYNOPSIS

  my $config = Nova::Config->new(\@ARGV);

  my $val = $config->option('my_opt');
  $config->persist(my_opt => 'foo');
  $config->runtime(my_opt => 'bar');

  my $conText = $config->conText;
  $config->conText($path);

=cut

my $CONFIG_FILE = '.nova';

# my $config = Nova::Config->new(\@ARGV);
#
# Create a new config object.
sub init {
	my ($self, $args) = @_;
	$self->{persistent} = { };
	eval {
		my $config = YAML::LoadFile($self->_configFile);
		$self->{persistent} = $config;
	};
	$self->modified(0);
	
	# Handle options
	{
		local @ARGV = @$args;
		GetOptions(
			'context|c=s'	=> sub { $self->runtime(conText => $_[1]) },
		) or die "Bad options!\n";
		@$args = @ARGV;
	}
}

# Get the file where config should be read or written
sub _configFile {
	return catfile($ENV{HOME}, $CONFIG_FILE);
}

# Save the config, if it has been modified
sub DESTROY {
	my ($self) = @_;
	return unless $self->modified;
	YAML::DumpFile($self->_configFile, $self->{persistent});
}

# Get the value of a config option
sub option {
	my ($self, $name) = @_;
	return $self->{runtime}{$name} if defined $self->{runtime}{$name};
	return $self->{persistent}{$name};
}

# Change the value of a config option, and request that the value be saved
sub persist {
	my ($self, $name, $val) = @_;
	$self->modified(1);
	$self->{persistent}{$name} = $val;
}

# Change the value of a config option, and request that the value only last
# for the duration of this program.
sub runtime {
	my ($self, $name, $val) = @_;
	$self->{runtime}{$name} = $val;
}
	
# Get/set the default ConText file to be read.
sub conText {
	my ($self, $val) = @_;
	$self->persist(conText => realpath($val)) if defined $val;
	
	my $context = $self->option('conText');
	die "No ConText set in config\n" unless defined $context;
	return $context;
}


1;
