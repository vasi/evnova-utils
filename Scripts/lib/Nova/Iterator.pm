# Copyright (c) 2006 Dave Vasilevsky
package Nova::Iterator;
use strict;
use warnings;

=head1 NAME

Nova::Iterator - Iterate over a collection one at a time

=head1 SYNOPSIS

  my $iter = Nova::Iterator->new(sub { ... });
  while (defined (my $i = $iter->next)) {
  	# Do something with $i
  }

=cut

use base qw(Nova::Base);
__PACKAGE__->fields(qw(code));

# my $iter = Nova::Iterator->new($code);
#
# Create an iterator that uses the code-ref $code to get the next element.
sub init {
	my ($self, $next) = @_;
	$self->code($next);
}

# my $item = $iter->next;
#
# Get the next element of this iterator. 'undef' sigals exhaustion.
sub next {
	my ($self) = @_;
	return $self->code->();
}

# my @list = $iter->collect;
#
# Collect the list output by this iterator
sub collect {
	my ($self) = @_;
	
	my @rs;
	while (defined(my $r = $self->next)) {
		push @rs, $r;
	}
	return @rs;
}


1;
