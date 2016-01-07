package Heap;
use warnings;
use strict;

use Fcntl qw(:DEFAULT :seek);
use Encode;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	$self->_init(@_);
	return $self;
}

sub _init {
	my $self = shift;

	if (ref($_[0]) eq 'SUB') {
		$self->{cmp} = shift;
	} else {
		# Default to max-heap
		$self->{cmp} = sub { $a <=> $b };
	}

	$self->{items} = \@_;
	$self->_buildHeap();
}

sub _parent {
	my ($self, $i) = @_;
	return undef if $i == 0;
	return int(($i - 1) / 2);
}

sub _children {
	my ($self, $i) = @_;
	return grep { $_ < $self->size() } ($i * 2 + 1, $i * 2 + 2);
}

sub _topChild {
	my ($self, $i) = @_;
	my $top = undef;
	for my $j ($self->_children($i)) {
		$top = $j if !defined($top) || $self->_cmp($j, $top) > 0;
	}
	return $top;
}

sub _cmp {
	my $self = shift;
	local ($a, $b) = map { $self->{items}[$_] } @_;
	return $self->{cmp}->();
}

sub _swap {
	my ($self, $i, $j) = @_;
	my $items = $self->{items};
	my $tmp = $items->[$i];
	$items->[$i] = $items->[$j];
	$items->[$j] = $tmp;
}

sub _cmpSwap {
	my ($self, $i, $j) = @_;
	if ($self->_cmp($i, $j) > 0) {
		$self->_swap($i, $j);
		return 1;
	}
	return 0;
}


sub _buildHeap {
	my $self = shift;
	my $last_parent = $self->_parent($#{$self->{items}});
	next unless defined $last_parent;

	for (my $i = $last_parent; $i >= 0; --$i) {
		$self->_heapify($i);
	}
}

sub _heapify {
	my ($self, $i) = @_;
	my $j = $self->_topChild($i) or return;
	$self->_cmpSwap($j, $i) or return;
	$self->_heapify($j);
}

sub _heapUp {
	my ($self) = @_;

	my $i = $#{$self->{items}};
	while ($i > 0) {
		my $parent = $self->_parent($i);
		$self->_cmpSwap($i, $parent);
		$i = $parent;
	}
}

sub _heapDown {
	my ($self) = @_;

	my $i = 0;
	while (1) {
		my $j = $self->_topChild($i) or last;
		$self->_cmpSwap($j, $i) or last;
		$i = $j;
	}
}

sub size {
	return scalar(@{$_[0]->{items}});
}

sub empty {
	return $_[0]->size() == 0;
}

sub push {
	my $self = shift;
	for my $item (@_) {
		push @{$self->{items}}, $item;
		$self->_heapUp();
	}
}

sub peek {
	my $self = shift;
	return undef if $self->empty();
	return ${$self->{items}}[0];
}

sub pop {
	my $self = shift;
	my $ret = $self->peek();
	return $ret unless defined $ret;

	$self->_swap(0, $#{$self->{items}});
	pop @{$self->{items}};
	$self->_heapDown();

	return $ret;
}

sub _debug {
	my ($self, $io) = @_;
	$io //= *STDERR;

	my @items = @{$self->{items}};
	if (!@items) {
		print $io "EMPTY\n";
		return;
	}

	my $max = log(scalar(@items)) / log(2);
	for (my $level = 0; $level <= $max; ++$level) {
		my $start = 2 ** $level - 1;
		my $end = 2 ** ($level + 1) - 2;
		$end = $#items if $end > $#items;
		printf $io "%s\n", join(' ', @items[$start...$end]);
	}
}

1;
