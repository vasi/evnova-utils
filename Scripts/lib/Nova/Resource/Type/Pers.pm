# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Pers;
use strict;
use warnings;

use base qw(Nova::Base);
use Nova::Resource;
Nova::Resource->registerType('pers');

sub importantBitFields { qw(ActivateOn) }

1;
