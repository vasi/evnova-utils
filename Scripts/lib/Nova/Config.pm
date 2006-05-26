# Copyright (c) 2006 Dave Vasilevsky
package Nova::Config;
use strict;
use warnings;

use base qw(Nova::Base);
__PACKAGE__->fields(qw(options));

=head1 NAME

Nova::Config - Configuration for EV Nova scripts

=head1 SYNOPSIS

  my $config = Nova::Config->new;

  my $val = $config->option('my_opt');
  $config->persist(my_opt => 'foo');
  $config->runtime(my_opt => 'bar');

  my $conText = $config->conText;
  
  my $oc = $config->withArgs(\@args);

=cut

use Cwd	qw(realpath);


our @OPTIONS = qw(conText verbose);

# Setup our accessors
for my $opt (@OPTIONS) {
	__PACKAGE__->makeSub($opt, sub {
		my ($self, @args) = @_;
		return $self->runtime($opt, @args) if @args;
		return $self->option($opt);
	});
}


# Proxy to file config
sub init {
	my ($self, @args) = @_;
	$self->options({ });
	if (ref($self) eq __PACKAGE__) {
		bless $self, 'Nova::Config::File';
		$self->init(@args);
	}
}

# Use case-insensitive methods 
sub can {
	my ($self, $meth) = @_;
	my $code = $self->caseInsensitiveMethod($meth);
}	
sub AUTOLOAD {
	unshift @_, our $AUTOLOAD;
	goto &Nova::Base::autoloadCan;
}

# Get the value of a config option
sub option {
	my ($self, $opt) = @_;
	return $self->options->{lc $opt};
}

# Change the value of a config option, and request that the value only last
# for the duration of this program.
sub runtime {
	my ($self, $opt, $val) = @_;
	my $meth = "transformSet$opt";
	eval { $val = $self->$meth($val) }; # Attempt to transform
	$self->options->{lc $opt} = $val;
}

sub withArgs {
	my ($self, $args) = @_;
	return Nova::Config::Args->new($self, $args);
}

sub transformSetConText {
	my ($self, $val) = @_;
	return realpath($val);
}


package Nova::Config::File;
use base qw(Nova::Config);
__PACKAGE__->fields(qw(modified file));

use YAML;
use File::Spec::Functions qw(catfile);

my $CONFIG_FILE = '.nova';


# my $config = Nova::Config->new(\@ARGV);
#
# Create a new config object.
sub init {
	my ($self, $file) = @_;
	$file = $self->_defaultConfigFile unless defined $file;
	$self->file($file);
	
	$self->options({ });
	eval {
		my $config = YAML::LoadFile($self->file);
		$self->options($config);
	};
	$self->modified(0);
}

# Get the file where config should be read or written
sub _defaultConfigFile {
	return catfile($ENV{HOME}, $CONFIG_FILE);
}

# Save the config, if it has been modified
sub DESTROY {
	my ($self) = @_;
	return unless $self->modified;
	YAML::DumpFile($self->file, $self->options);
}

# We can't really have a runtime change, just change permanently
sub runtime {
	my ($self, @args) = @_;
	$self->modified(1);
	return $self->SUPER::runtime(@args);
}

# Change the value of a config option, and request that the value be saved
sub persist { runtime(@_) }



package Nova::Config::Args;
use base qw(Nova::Config);
__PACKAGE__->fields(qw(parent));

use Getopt::Long qw(:config bundling pass_through);

sub init {
	my ($self, $parent, $args) = @_;
	$self->SUPER::init;
	$self->parent($parent);
	
	# Handle options
	{
		local @ARGV = @$args;
		my $verbose = 0;
		GetOptions(
			'context|c=s'	=> sub { $self->conText($_[1]) },
			'verbose|v+'	=> \$verbose,
			'width|w=i'		=> sub { local $ENV{COLUMNS} = $_[1] },
			'read-write-context|rw'	=> sub { $self->runtime(rw => 1) },
			'memory-context|mem'	=> sub { $self->runtime(mem => 1) },
		) or die "Bad options!\n";
		@$args = @ARGV;
		$self->verbose($verbose);
	}
}

sub persist {
	my ($self, $opt, $val) = @_;
	delete $self->options->{lc $opt};
	return $self->parent->persist($opt, $val);
}

sub option {
	my ($self, $opt) = @_;
	return $self->options->{lc $opt} if exists $self->options->{lc $opt};
	return $self->parent->option($opt);
}

1;
