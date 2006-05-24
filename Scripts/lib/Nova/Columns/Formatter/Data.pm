# Copyright (c) 2006 Dave Vasilevsky
package Nova::Columns::Formatter::Data;
use strict;
use warnings;

use base qw(Nova::Columns::Formatter);
__PACKAGE__->fields(qw(type fmt num alignChar maxlen trunc col opts finalFmt));

use List::Util qw(max);

sub init {
	my ($self, $fmt, $col, @opts) = @_;
	my %opts = (truncMin => 5, @opts);
	$self->opts(\%opts);
	$self->col($col);
	
	($fmt, my $type) = $fmt =~ /^%(.*)([a-zA-Z])$/;
	$self->type($type);

	my ($chr) = ($fmt =~ /([-?])/);
	$chr ||= '';
	$self->alignChar($chr);

	if ($fmt =~ s/([1-9]\d*)//) {
		$self->maxlen($1);
	} else {
		$self->maxlen(max map { length($_) } @$col);
	}
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
		my $trunc = $self->type eq 's' ? ('.' . $self->maxlen) : '';
		my $fmt = sprintf "%%%s%d%s%s", $self->fmt, $self->maxlen, $trunc,
			$self->type;
		$self->finalFmt($fmt);
	}
	
	my $str = sprintf $self->finalFmt, $self->col->[$idx];
	return '#' x $self->maxlen if length($str) > $self->maxlen;
	return $str;
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

1;
