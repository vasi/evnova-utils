# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::StrNum;
use strict;
use warnings;

use base 'Nova::Resource';
__PACKAGE__->register('STR#');

use Nova::Util qw(wrap);

__PACKAGE__->flagInfo('Flags',
	iterativeEntry	=> 'iterative entry',
	iterativeExit	=> 'iterative exit',
);

# Get the list of strings
sub list {
	my ($self) = @_;
	return @{$self->strings};
}

# Show the list of strings
sub showList {
	my ($self, $name) = @_;
	my $text;
	for my $s ($self->list) {
		$text .= wrap($s, '  * ', '    ');
	}
	return $text;
}

1;
	