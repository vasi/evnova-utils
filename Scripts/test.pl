#!/usr/bin/perl
use warnings;
use strict;
use Data::Dumper;

# $pkg->symref($string);
#
# Get a symbolic reference
sub symref {
	my ($pkg, $ref) = @_;
	$pkg = ref($pkg) || $pkg;
	my $name = "${pkg}::$ref";
	
	no strict 'refs';
	return *$name;
}

{
	my $pkg = __PACKAGE__;
	my $ref;
	
	$ref = $pkg->symref('foo');
	@$ref = (1, 1, 2, 3, 5, 8);
	
	$ref = $pkg->symref('bar');
	$$ref = "bar\n";
	
	local *ref = $pkg->symref('func');
	*ref = sub { print "func\n" };
}
{
	no strict 'vars'; no warnings 'once';
	print join(',', @main::foo), "\n";
	print $main::bar;
	main->func;
	print Dumper \%{main::};
}
