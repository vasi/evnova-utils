# Copyright (c) 2006 Dave Vasilevsky

package Nova::Util;
use strict;
use warnings;

use base qw(Exporter);

use List::Util qw(max min sum);
use Text::Wrap qw();

our @EXPORT_OK = qw(deaccent commaNum termWidth wrap prettyPrint printIter
	makeFilter regexFilter);

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
		my $w = Fink::CLI::get_term_width();
		return $w if $w;
	}
	if (exists $ENV{COLUMNS} && $ENV{COLUMNS}) {
		return $ENV{COLUMNS};
	}
	return 80;
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

# printIter { $code }, $iter, $verb;
#
# Print the results of applying a code-block to an iterator's contents
sub printIter (&$$) {
	my ($code, $iter, $verb) = @_;
	my $found = 0;
	my $delim = $verb ? "\n\n" : "\n";
	while (defined(local $_ = $iter->next)) {
		my $s = $code->();
		next unless $s;
		print $delim if $found++;
		prettyPrint $s;
	}
}

sub _filterFromCode {
	my ($code, $spec) = @_;
	my $filt = eval "sub { $code }";
	die "Bad filter '$spec': $@\n" if $@;
	return $filt;
}

# Make a filter from a specification
sub makeFilter {
	my ($spec) = @_;
	my $code;
	
	if (defined (my $filt = regexFilter($spec))) {
		return $filt;			# Regex
	} elsif ($spec =~ /\$_/) {
		$code = $spec;			# Code
	} elsif ($spec =~ /^\s*([><=]+|eq|ne|ge|le|gt|lt)/) {
		$code = "\$_ $spec";	# Relation
	} elsif ($spec =~ /^\s*-?\d[_\d]*([eE]-?\d+)?(\.\d*)?\s*$/) {
		$code = "\$_ == $spec";	# Numeric equality
	} else {
		$code = "\$_ eq \"\Q$spec\E\"";		# String equality
	}
	return _filterFromCode($code, $spec);
}

# Make a filter from a regex spec. If it doesn't look like a regex, return
# undef.
sub regexFilter {
	my ($spec) = @_;
	if ($spec =~ m,^\s*/.*/[imsx]*\s*$,
			|| $spec =~ /^\s*m(\W).*\1[imsx]*\s*$/
			|| $spec =~ /^\s*m[[<({].*[]>)}][imsx]*\s*$/) {
		return _filterFromCode($spec, $spec);
	} else {
		return undef;
	}
}

1;