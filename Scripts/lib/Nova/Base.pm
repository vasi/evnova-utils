# Copyright (c) 2006 Dave Vasilevsky

package Nova::Base;
use strict;
use warnings;

=head1 NAME

Nova::Base - base class for EV Nova packages

=head1 SYNOPSIS

  package SubClass;
  use base 'Nova::Base';

  my $obj = SubClass->new(@params);

=cut

BEGIN {
	binmode STDOUT, ':utf8';
}

# my $obj = SubClass->new(@params);
sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $self = {};
	bless($self, $class);

	$self->init(@_);

	return $self;
}

# Called by the constructor to initialize the object.
# By default, treat the args as field initializers.
sub init {
	my ($self, %params) = @_;
	while (my ($k, $v) = each %params) {
		$self->$k($v);
	}
}

# my @methods = $pkg->methods;
#
# List all the methods/subroutines in a package.
sub methods {
	my ($pkg) = @_;
	$pkg = ref($pkg) || $pkg;
	my @methods;
	
	no strict 'refs';
	while (my ($k, $v) = each %{"${pkg}::"}) {
		next if $k =~ /::/ or $k eq '_temp'; # sub-modules
		*_temp = $v;
		next unless defined &_temp;
		push @methods, $k;
	}
	return @methods;
}

# my @subpkgs = $pkg->subPackages;
#
# Find 'sub-packages' of this package. Eg: Foo->subPackages could include
# Foo::Bar and Foo::Iggy::Blah. Each sub-package is require'd, and returned
# as a string.
sub subPackages {
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


# $pkg->fields(qw(title @authors %editions));
# 
# Setup fields for a class
sub fields {
	my ($pkg, @fields) = @_;
	
	for my $field (@fields) {
		my $sub = sub { $#_ ? ($_[0]->{$field} = $_[1])
				: $_[0]->{$field} };
		no strict 'refs';
		*{"${pkg}::$field"} = $sub;
		*{"${pkg}::_accessor_$field"} = $sub;
	}
}	

1;
