# Copyright (c) 2006 Dave Vasilevsky

package Nova::Base;
use strict;
use warnings;

use File::Spec::Functions qw(catdir abs2rel);
use File::Find;

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

# my %methods = $pkg->methods;
#
# List all the methods/subroutines in a package.
sub methods {
	my ($pkg) = @_;
	$pkg = ref($pkg) || $pkg;
	my %methods;
	
	no strict 'refs';
	while (my ($k, $v) = each %{"${pkg}::"}) {
		next if $k =~ /::/ or $k eq '_temp'; # sub-modules
		local *_temp = $v;
		next unless defined &_temp;
		$methods{$k} = \&_temp;
	}
	return %methods;
}

# my @subpkgs = $pkg->subPackages;
# my @subpkgs = $pkg->subPackages($parent);
#
# Find 'sub-packages' of this package. Eg: Foo->subPackages could include
# Foo::Bar and Foo::Iggy::Blah. Each sub-package is require'd, and returned
# as a string.
sub subPackages {
	my ($pkg, $parent) = @_;
	
	if (defined $parent) {
		$pkg = $parent;
		eval("package $pkg; our \@ISA = ('" . __PACKAGE__ . "')");
	}
	
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
				die $@ if $@;
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
	
	local *_alias;
	for my $field (@fields) {
		my $sub = sub { $#_ ? ($_[0]->{$field} = $_[1])
				: $_[0]->{$field} };
		
		for my $subname ($field, "_accessor_$field") {
			$pkg->makeSub($subname, $sub);
		}
	}
}

# $pkg->symref($var);
#
# Get a symbolic reference
sub symref {
	my ($pkg, $var) = @_;
	$pkg = ref($pkg) || $pkg;
	my $name = "${pkg}::$var";
	
	no strict 'refs'; no warnings 'once';
	return *$name;
}

# $pkg->makeSub($name, $code);
#
# Insert a subroutine into the symbol table. Will NOT insert the subroutine
# if over an existing method.
sub makeSub {
	my ($pkg, $name, $code) = @_;
	local *_ref = $pkg->symref($name);
	*_ref = $code unless exists &_ref;
}

1;
