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
		map { print $_->output($i) } @{$self->formatters};
		print "\n";
	}
}

sub reduceLen {
	my ($self) = @_;
	
	my $fmts = $self->formatters;
	my ($trunc) = grep { $_->trunc } @$fmts;
	return unless defined $trunc;
	
	$trunc->truncate($fmts, $self->len - $self->width);
	$self->formatters($fmts);
}


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

sub trunc { 0 }



package Nova::Columns::Formatter::Literal;
use base qw(Nova::Columns::Formatter);
__PACKAGE__->fields(qw(str));

sub init {
	my ($self, $str) = @_;
	$self->str($str);
}

sub len { length($_[0]->str) }

sub output { $_[0]->str }


package Nova::Columns::Formatter::Data;
use base qw(Nova::Columns::Formatter);
__PACKAGE__->fields(qw(type fmt num alignChar maxlen trunc col opts finalFmt));

use List::Util qw(max);

sub init {
	my ($self, $fmt, $col, @opts) = @_;
	my %opts = (truncMin => 5, @opts);
	$self->opts(\%opts);
	$self->col($col);
	
	($fmt, my $type) = $fmt =~ /^%(.*)(\w)$/;
	$self->type($type);

	my ($chr) = ($fmt =~ /([-?])/);
	$chr ||= '';
	$self->alignChar($chr);
	
	$self->maxlen(max map { length($_) } @$col);
	$self->trunc($fmt =~ s/<//);
	$self->fmt($fmt);
	
	if ($self->alignChar eq '?') {
		my $cnt = scalar(@$col);
		my $nums = 0;
		for my $c (@$col) {
			$nums++ if $c =~ /^(\D*)([\d,.eEx ]+)(\D*)$/
				&& length($2) > length($1) + length($3);
		}
		$self->num($nums / $cnt >= 0.8);
	}
}

sub len { $_[0]->maxlen }

sub align {
	my ($self, $align) = @_;
	$align = $self->num ? '' : '-' unless defined $align;
	if ($self->alignChar eq '?') {
		(my $fmt = $self->fmt) =~ s/\?/$align/;
		$self->fmt($fmt);
	}
	$self->alignChar($align);
}		

sub output {
	my ($self, $idx) = @_;
	
	unless (defined $self->finalFmt) {
		$self->align;
		my $fmt = sprintf "%%%s%d.%d%s", $self->fmt, $self->maxlen,
			$self->maxlen, $self->type;
		$self->finalFmt($fmt);
	}
	return sprintf $self->finalFmt, $self->col->[$idx];
}

sub neighbors {
	my ($self, $formats, $idx) = @_;
	
	my @dirs;
	push @dirs, 1 if $self->alignChar ne '';
	push @dirs, -1 if $self->alignChar ne '-';
	
	my @others;
	for my $dir (@dirs) {
		my $i = $idx + $dir;
		while ($i >= 0 && $i <= $#$formats) {
			if ($formats->[$i]->isa(__PACKAGE__)) {
				push @others, $i;
				last;
			}
			last if $formats->[$i]->str =~ /\S/;
			$i += $dir;
		}
	}
	return @others;
}

sub combine {
	my ($self, $formats, $cutlen) = @_;
	return if $self->alignChar eq '?';
	
	my ($idx) = grep { $formats->[$_] == $self } (0..$#$formats);
	my @others = $self->neighbors($formats, $idx) or return 0;
	
	my @sols;
	for my $other (@others) {
		my ($start, $end) = sort { $a <=> $b } ($idx, $other);
		my ($fstart, $fend) = map { $formats->[$_] } ($start, $end);
		next unless $fstart->alignChar ne '' && $fend->alignChar ne '-';
		
		# How many characters will be truncated if we choose this neighbor?
		my $oklen = $fstart->len + $fend->len - $cutlen;
		my $lost = 0;
		my $rows = scalar(@{$fstart->col});
		for my $r (0..$rows - 1) {
			my $extra = length($fstart->col->[$r]) + length($fend->col->[$r])
				- $oklen;
			$lost += $extra if $extra > 0;
		}
		
		push @sols, { lost => $lost, start => $start, end => $end };
	}
	return 0 unless @sols;
	
	# Choose the best neighbor
	@sols = sort { $a->{lost} <=> $b->{lost} } @sols;
	my ($start, $end) = @{$sols[0]}{'start','end'};
	splice @$formats, $start, $end - $start + 1,
		Nova::Columns::Formatter::Combined->new($cutlen,
			[ @$formats[$start..$end] ], %{$self->opts});
	return 1;
}

sub truncate {
	my ($self, $formats, $len) = @_;
	
	# Find something to combine with
	return if $self->combine($formats, $len);
	
	# Truncate
	my $truncMin = $self->opts->{truncMin};
	$self->maxlen(max($self->maxlen - $len, $truncMin));
}


package Nova::Columns::Formatter::Combined;
use base qw(Nova::Columns::Formatter);
__PACKAGE__->fields(qw(start end restlen spaces));

use List::Util qw(sum min);

sub init {
	my ($self, $cutlen, $others, %opts) = @_;
	my ($start, $end) = (shift @$others, pop @$others);
	$start->align('-');
	$end->align('');
	$self->start($start);
	$self->end($end);
	
	$self->spaces(sum map { $_->len } @$others);
	
	my $trunclen = ($start->trunc ? $start : $end)->len;
	my $maxcut = $trunclen - $opts{truncMin};
	$cutlen = min($cutlen, $maxcut);
	$self->restlen($start->len + $end->len - $cutlen);
}

sub output {
	my ($self, $idx) = @_;
	
	my ($start, $end) = map { $_->output($idx) } ($self->start, $self->end);
	$start =~ s/\s*$//;
	$end =~ s/^\s*//;
	
	my $restlen = $self->restlen;
	my $spaces = $self->spaces;
	my $len = length($start) + length($end);
	
	if ($len > $restlen) {
		my $trim = $len - $restlen;
		my $trimref = $self->start->trunc ? \$start : \$end;
		$$trimref = substr $$trimref, 0, -$trim;
		$len = $restlen;
	}
	return $start . ' ' x ($spaces + $restlen - $len) . $end;
}


1;
