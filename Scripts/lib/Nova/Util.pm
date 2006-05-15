# Copyright (c) 2006 Dave Vasilevsky

package Nova::Util;
use strict;
use warnings;

use base qw(Exporter);

use utf8;

our @EXPORT_OK = qw(deaccent);

=head1 NAME

Nova::Util - Miscellaneous utilities

=head1 SYNOPSIS

  my $str = deaccent($str);

=cut

# $str = deaccent($str);
#
# Remove accents from a resource type, and canonicalizes is to lower-case.
# Eg: mïsn => misn
sub deaccent {
	my ($s) = @_;
	$s =~ tr/\x{e4}\x{eb}\x{ef}\x{f6}\x{fc}\x{ff}/aeiouy/;
	return lc $s;
}

1;