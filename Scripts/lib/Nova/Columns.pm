# Copyright (c) 2006 Dave Vasilevsky
package Nova::Columns;
use strict;
use warnings;

use base qw(Nova::Base Exporter);
our @EXPORT = qw(columns);
our @EXPORT_OK = qw(columnsStr);

use Nova::Columns::Formatter;
use Nova::Util qw(termWidth);
use List::Util qw(sum);

=head1 NAME

Nova::Columns - print data in columns

=cut

our $PCT_RE = qr/(%[^%a-zA-Z]*[a-zA-Z])/;


# columns($fmt, \@list, $colGen, %opts);
#
# Print something in columns.
# Opts include:
#	rank:	field to rank by
#	total:	last field is a total
sub columns {
	print columnsStr(@_);
}

sub columnsStr {
	my ($fmt, $list, $colGen, %opts) = @_;
	return "No items found.\n" unless @$list;
	return Nova::Columns->new($fmt, $list, $colGen, %opts)->output;
}

__PACKAGE__->fields(qw(formatters opts width len nrows));

sub init {
	my ($self, $fmt, $list, $colGen, %opts) = @_;
	$self->opts(\%opts);
	
	# Rank rows
	my @rows = @$list;
	if ($opts{rank}) { # Schwartzian
		@rows = map { $_->[0] } sort { $b->[1] <=> $a->[1] }
			map { [ $_, $opts{rank}->($_) ] } @rows;
	}
	$self->nrows(scalar(@rows));
	
	# Turn into columns
	@rows = map { [ $colGen->() ] } @rows;
	my @cols;
	for my $r (@rows) {
		push @{$cols[$_]}, $r->[$_] for (0..$#$r);
	}
	
	# Create formatters
$DB::single = 1;
	my @parts = split /$PCT_RE/, $fmt;
	my @fmts = map { Nova::Columns::Formatter->new($_, \@cols, %opts) } @parts;
	$self->formatters(\@fmts);
}

sub output {
	my ($self) = @_;
	
	$self->width( termWidth() );
	$self->len	( sum map { $_->len } @{$self->formatters}	);
	
	if ($self->len > $self->width) {
		$self->reduceLen;
	}
	
	# Print (including total)
	my $ret = '';
	my $maxIdx = $self->nrows() - 1;
	for my $i (0..$maxIdx) {
		$ret .= '-' x $self->len . "\n"
			if $i == $maxIdx && $self->opts->{total};
		map { $ret .= $_->output($i) } @{$self->formatters};
		$ret .= "\n";
	}
	return $ret;
}

sub reduceLen {
	my ($self) = @_;
	
	my $fmts = $self->formatters;
	my ($trunc) = grep { $_->trunc } @$fmts;
	return unless defined $trunc;
	
	$trunc->truncate($fmts, $self->len - $self->width);
	$self->formatters($fmts);
}

1;
