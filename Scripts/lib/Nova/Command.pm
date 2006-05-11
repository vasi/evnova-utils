# Copyright (c) 2006 Dave Vasilevsky
package Nova::Command;
use strict;
use warnings;

use base qw(Nova::Base Exporter);
our @EXPORT_OK = qw(command);

use Nova::Resources;
use Nova::Config;

use File::Spec::Functions qw(catdir abs2rel);
use File::Find;

my %COMMANDS;
my %CATEGORIES;

# Run the command line
sub execute {
	my ($class, @args) = @_;
	__PACKAGE__->findSubpackages; # load them	
	
	my $config = Nova::Config->new(\@args);
	
	my $cmd = shift @args;
	die "No such command '$cmd'\n" unless exists $COMMANDS{lc $cmd};
	$COMMANDS{lc $cmd}->run($config, @args);
}

sub _init {
	my $self = shift; 
	@$self{qw(sub name help)} = @_;
}

sub setup { }

sub run {
	my ($self, $config, @args) = @_;
	$self->{config} = $config;
	$self->{args} = \@args;
	
	$self->setup();
	$self->{sub}->($self, @{$self->{args}});
}

sub help	{	$_[0]->{help}	}
sub name	{	$_[0]->{name}	}
sub config	{	$_[0]->{config}	}

# Register a command
sub command (&$$) {
	my ($sub, $name, $help) = @_;
	my $pkg = scalar(caller);
	my $cmd = $pkg->new($sub, $name, $help);
	$COMMANDS{lc $name} = $cmd;
	
	my $root = __PACKAGE__;
	$pkg =~ s/${root}(::)?([^:]*).*/$2/;
	push @{$CATEGORIES{$pkg}}, $cmd;
}

sub findSubpackages {
	my $pkg = shift;
	(my $pkgdir = $pkg) =~ s,::,/,g;
	
	my %found;
	my @found; # keep ordered
	for my $dir (@INC) {
		my $subdir = catdir($dir, $pkgdir);
		next unless -d $subdir;
		
		find({
			follow => 1, no_chdir => 1,
			wanted => sub {
				return unless /\.pm$/;
				
				my $subpkg = abs2rel($File::Find::name, $dir);
				$subpkg =~ s,/,::,g;
				$subpkg =~ s,\.pm$,,;
				return if $found{$subpkg}++;
				
				eval "require $subpkg";
				push @found, $subpkg;
			}
		}, $subdir);
	}
	
	return @found;
}

sub printHelp {
	my ($self) = @_;
	printf STDERR "  %-15s - %s\n", $self->name, $self->help;
}

sub printCategory {
	my ($self, $cat, $name) = @_;
	print STDERR "\n$name:\n";
	$_->printHelp for @{$CATEGORIES{$cat}};
}

command {
	my ($self, $cmd) = @_;
	if (defined $cmd) {
		if (exists $COMMANDS{lc $cmd}) {
			my $cmd = $COMMANDS{lc $cmd};
			$cmd->printHelp;
			exit 0;
		} else {
			print STDERR "No such command '$cmd'\n\n";
			# continue
		}
	}
	
	# Print all help
	printf "%s - EV Nova command line tool\n", $0;
	$self->printCategory('', 'General');
	$self->printCategory($_, $_) for grep { "$_" } keys %CATEGORIES;
} help => 'get help on available commands';

command {
	print "foo\n";
} misc => 'test';

1;
