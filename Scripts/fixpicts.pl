#!/usr/bin/perl
use warnings;
use strict;

use Image::Magick;
use File::Spec;
use File::Basename qw(basename);

sub fixone {
	my ($file) = @_;
	my $base = basename $file;
	
	my $image = Image::Magick->new;
	$image->Read($file);
	if ($image->Get('depth') < 8) {
		print "Fixing $base\n";
		$image->Set(depth => 8);
		$image->Write($file);
	}
}

sub fixdir {
	my ($dir) = @_;
	
	my $dirh;
	opendir $dirh, $dir;
	my @files = readdir $dirh;
	closedir $dirh;
	
	for my $file (@files) {
		next if $file =~ /^\.*$/;
		my $path = File::Spec->catfile($dir, $file);
		fixone($path);
	}
}

fixdir(@ARGV);
