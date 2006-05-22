# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::StrNum;
use strict;
use warnings;

use base qw(Nova::Base);
use Nova::Resource;
Nova::Resource->registerType('STR#');

use Nova::Util qw(wrap);

# Get the list of strings
sub list {
	my ($self) = @_;
	return @{$self->strings};
}

# Show the list of strings
sub showList {
	my ($self, $name) = @_;
	my $text = '';
	for my $s ($self->list) {
		$text .= wrap($s, '  * ', '    ') . "\n";
	}
	return $text;
}

1;
	