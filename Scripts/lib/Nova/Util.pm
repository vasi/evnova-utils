# Copyright (c) 2006 Dave Vasilevsky

package Nova::Util;
use strict;
use warnings;

use base qw(Exporter);

use List::Util qw(max min sum);
use Text::Wrap qw();

our @EXPORT_OK = qw(deaccent commaNum termWidth wrap prettyPrint);

=head1 NAME

Nova::Util - Miscellaneous utilities

=head1 SYNOPSIS

  my $str = deaccent($str);
  my $str = commaNum($num);
  my $width = termWidth;

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

# Get the comma-delimited form of the given number. Eg: 1234567 => 1,234,567
sub commaNum {
	my ($n) = @_;
	return $n if $n < 1000;
	return commaNum(int($n/1000)) . sprintf ",%03d", $n % 1000;
}

# Get the width of the terminal
sub termWidth {
	if (eval { require Fink::CLI }) {
		return Fink::CLI::get_term_width();
	} elsif (exists $ENV{COLUMNS}) {
		return $ENV{COLUMNS};
	} else {
		return 80;
	}
}

# wrap($text, $first, $rest);
# 
# Wrap a line of text.
sub wrap {
	my ($text, $first, $rest) = @_;
	$first = '' unless defined $first;
	$rest = '' unless defined $rest;
	local $Text::Wrap::columns = termWidth;
	return Text::Wrap::wrap($first, $rest, $text);
}

# prettyPrint($text);
#
# Print some text nicely
sub prettyPrint {
	my ($text) = @_;
	print wrap($text);
}

1;