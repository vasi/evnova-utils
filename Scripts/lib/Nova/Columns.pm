# Copyright (c) 2006 Dave Vasilevsky
package Nova::Columns;
use strict;
use warnings;

use base qw(Nova::Base Exporter);
our @EXPORT = qw(columns);

use Nova::Util qw(termWidth);
use List::Util qw(sum);

=head1 NAME

Nova::Columns - print data in columns

=cut

our $PCT_RE = qr/(%[^%\w]*\w)/;


# columns($fmt, \@list, $colGen, %opts);
#
# Print something in columns.
# Opts include:
#	rank:	field to rank by
#	total:	last field is a total
sub columns {
	my ($fmt, $list, $colGen, %opts) = @_;
	unless (@$list) {
		print "No items found.\n";
		return;
	}
	
	Nova::Columns->new($fmt, $list, $colGen, %opts)->print;
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
	my @parts = split /$PCT_RE/, $fmt;
	my @fmts = map { Nova::Columns::Formatter->new($_, \@cols, %opts) } @parts;
	$self->formatters(\@fmts);
}


sub print {
	my ($self) = @_;
	
	$self->width( termWidth() );
	$self->len	( sum map { $_->len } @{$self->formatters}	);
	
	if ($self->len > $self->width) {
		$self->reduceLen;
	}
	
	# Print (including total)
	my $maxIdx = $self->nrows() - 1;
	for my $i (0..$maxIdx) {
		print '-' x $self->len, "\n" if $i == $maxIdx && $self->opts->{total};
		map { $_->print($i) } @{$self->formatters};
		print "\n";
	}
}

sub reduceLen { }


# Format and print a column
package Nova::Columns::Formatter;
use base qw(Nova::Base);

sub init {
	my ($self, $str, $cols, %opts) = @_;
	
	my ($subclass, @args);
	if ($str =~ /$PCT_RE/) {
		($subclass, @args) = (Data => $str, shift @$cols, %opts);
	} else {
		($subclass, @args) = (Literal => $str);
	}
	
	my $pkg = ref($self) . "::$subclass";
	bless $self, $pkg;
	$self->init(@args);
}


package Nova::Columns::Formatter::Literal;
use base qw(Nova::Columns::Formatter);
__PACKAGE__->fields(qw(str));

sub init {
	my ($self, $str) = @_;
	$self->str($str);
}

sub len { length($_[0]->str) }

sub print { print $_[0]->str }


package Nova::Columns::Formatter::Data;
use base qw(Nova::Columns::Formatter);
__PACKAGE__->fields(qw(type fmt num alignChar maxlen trunc col opts));

use List::Util qw(max);

sub init {
	my ($self, $fmt, $col, %opts) = @_;
	$self->opts(\%opts);
	$self->col($col);
	
	($fmt, my $type) = $fmt =~ /^%(.*)(\w)$/;
	$self->type($type);
	
	$self->alignChar(($fmt =~ /([-?])/) || '');
	$self->maxlen(max map { length($_) } @$col);
	$self->trunc($fmt =~ s/<//);
	$self->fmt($fmt);
	
	if ($self->alignChar eq '?') {
		my $cnt = scalar(@$col);
		my $nums = scalar(grep { /^\D*[\d,.eEx ]*\D*$/ } @$col);
		$self->num($nums / $cnt >= 3/4);
	}
}

sub len { $_[0]->maxlen }

sub print {
	my ($self, $idx) = @_;
	
	# TODO: Unknown align, truncation
	
	my $fmt = '%' . $self->fmt . $self->maxlen . $self->type;	
	$fmt =~ s/\?//;
	
	printf $fmt, $self->col->[$idx];
}

1;
