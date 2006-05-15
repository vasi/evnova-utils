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

# my $cache = Nova::Cache->cache(@ids);
#
# Get a cache, given a list of identifiers. The ids serve to uniquely identify
# the desired cache.
sub cache {
	my ($class, @ids) = @_;
	my $cache = $class->_cacheFile(@ids);
	return $class->_cache_attach($cache);
}

# Attach to a cache
sub _cache_attach {
	my ($class, $file) = @_;
	unless (exists $CACHES{$file}) {
		my %h;
		tie %h, MLDBM => $file or die "Can't tie cache: $!\n";
		$CACHES{$file} = \%h;
	}
	return $CACHES{$file};
}	

# Get a cache, treating the first identifier as the name of a file. This allows
# the returned cache to be emptied if the cache is not up to date with the file.
sub cacheForFile {
	my ($class, $file, @ids) = @_;
	@ids = ($file, @ids);
	
	my $cache = $class->_cacheFile(@ids);
	unlink $cache unless -f $cache && -M $cache <= -M $file;
	return $class->_cache_attach($cache);
}

# Get the cache file for a given @ids list.
sub _cacheFile {
	my ($class, @ids) = @_;
	unshift @ids, scalar(caller(1));
	my $id = join '_', map { uri_escape($_, '^a-zA-Z0-9') } @ids;
	
	my $dir = catdir($ENV{HOME}, $CACHEDIR);
	mkpath($dir) unless -d $dir;
	my $file = catfile($dir, $id);
	return $file;
}

# Delete the current file that we're caching
sub deleteCache {
	my ($class, @ids) = @_;
	my $file = $class->_cacheFile(@ids);
	delete $CACHES{$file};
	unlink $file;
}
	

1;
