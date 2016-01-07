package PQueue;
use warnings;
use strict;

use Heap;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	$self->_init(@_);
	return $self;
}

sub _pairs {
	my @ret;
	while (my @pair = splice(@_, 0, 2)) {
		push @ret, \@pair;
	}
	return @ret;
}

use Data::Dumper;

sub _init {
	my ($self, $type, @items) = @_;

	my $cmp = sub { $_[0]->[1] <=> $_[1]->[1] };
	$cmp = sub { $_[1]->[1] <=> $_[0]->[1] }
		if defined($type) && $type eq 'min';

	$self->{heap} = Heap->new($cmp, _pairs(@items));
}

sub size { shift->{heap}->size() }
sub empty { shift->{heap}->empty() }

sub peek {
	my $v = shift->{heap}->peek() or return undef;
	return wantarray ? @$v : $$v[0];
}

sub pop {
	my $v = shift->{heap}->pop() or return undef;
	return wantarray ? @$v : $$v[0];
}

sub push {
	my ($self, @items) = @_;
	$self->{heap}->push(_pairs(@items));
}

1;
