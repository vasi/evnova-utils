# Copyright (c) 2006 Dave Vasilevsky
package Nova::Config;
use strict;
use warnings;

use base qw(Nova::ResFork);

=head1 NAME

Nova::Config - Configuration for EV Nova scripts

=head1 SYNOPSIS

  my $fork = Nova::ResFork->new($file);

  my @types = $fork->types;
  my @ids = $fork->ids($type);
  my $data = fork->read($type => $id);

  

=cut

### FIXME: Merge this with Nova::Resources somehow?

1;
