# Copyright (c) 2006 Dave Vasilevsky

package Nova::Cache;
use strict;
use warnings;

use MLDBM qw(DB_File Storable);
use URI::Escape;
use File::Path;
use File::Basename;
use File::Spec::Functions;

=head1 NAME

Nova::Cache - utilities for caching

=head1 SYNOPSIS

  my $cache = Nova::Cache->cache(@ids);

  $cache->{foo} = 4;
  $val = $cache->{bar};

=cut

our $CACHEDIR = '.nova-cache';
our %CACHES;

sub cache {
	my ($class, @ids) = @_;
	unshift @ids, scalar(caller);
	my $id = join '_', map { uri_escape($_, '^a-zA-Z0-9') } @ids;
	
	unless (exists $CACHES{$id}) {
		my $dir = catdir($ENV{HOME}, $CACHEDIR);
		mkpath($dir);
		my $file = catfile($dir, $id);
		
		my %h;
		tie %h, MLDBM => $file or die "Can't tie cache: $!\n";
		$CACHES{$id} = \%h;
	}
	return $CACHES{$id};
}

1;
