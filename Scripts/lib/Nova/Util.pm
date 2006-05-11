# Copyright (c) 2006 Dave Vasilevsky

package Nova::Util;
use strict;
use warnings;

use base qw(Exporter);

use utf8;

our @EXPORT_OK = qw(deaccent methods);

=head1 NAME

Nova::Util - Miscellaneous utilities

=head1 SYNOPSIS

  my $str = deaccent($str);

=cut

# $str = deaccent($str);
#
# Remove accents from a resource type
sub deaccent {
	my ($s) = @_;
	$s =~ tr/äëïöüÿ/aeiouy/;
	return lc $s;
}

# my @methods = methods($pkg);
#
# List all the methods/subroutines in a package.
sub methods {
	my ($pkg) = @_;
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

1;