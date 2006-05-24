# Copyright (c) 2006 Dave Vasilevsky
package Nova::Columns::Formatter;
use strict;
use warnings;

use base qw(Nova::Base);

use Nova::Util qw(termWidth);
use Nova::Columns::Formatter::Data;
use List::Util qw(sum);

sub init {
	my ($self, $str, $cols, %opts) = @_;
	
	my ($subclass, @args);
	if ($str =~ /$Nova::Columns::PCT_RE/) {
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

sub output { sprintf $_[0]->str }


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
