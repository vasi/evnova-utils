use warnings;
use strict;

our $globalCache;
{
	my $dir = File::Spec->rel2abs(dirname $0);
	$globalCache = File::Spec->catdir($dir, '.nova-cache');
}
our $conTextOpt;

sub getConText {
	return File::Spec->rel2abs($conTextOpt) if defined $conTextOpt;
	my $file = File::Spec->catfile($globalCache, '.context');
	die "No context set!\n" unless -f $file;

	open my $fh, '<', $file;
	my $context = <$fh>;
	chomp $context;
	close $fh;
	return $context;
}

sub setConText {
	my ($context) = @_;
	$context = File::Spec->rel2abs($context);
	mkdir_p($globalCache);
	my $file = File::Spec->catfile($globalCache, '.context');
	open my $fh, '>', $file;
	print $fh $context;
	close $fh;
}

sub contextCache {
	my $context = getConText();
	$context =~ s,/,_,g;
	return File::Spec->catdir($globalCache, $context);
}

sub printConText {
	my $context = getConText();
	print "$context\n";
}

1;
