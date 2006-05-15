# Copyright (c) 2006 Dave Vasilevsky
package Nova::Resource::Type::Outf;
use strict;
use warnings;

use base qw(Nova::Resource Exporter);
__PACKAGE__->register('outf');

our (@EXPORT, %MOD_TYPE_NAMES);

sub mods {
	my ($self) = @_;
	return $self->multiObjs('ModType', 'ModVal');
}

sub modTypeName {
	my ($class, $type) = @_;
	return $MOD_TYPE_NAMES{$type};
}


BEGIN {

	sub modTypes {
		my ($data) = @_;
		my @mts = split /\n/, $data;
		
		for my $line (@mts) {
			my ($n, $name, $const) = split /\s{3,}/, $line;
			$MOD_TYPE_NAMES{$n} = $name;
			
			$const =~ s/\s/_/g;
			$const = uc $const;
			$const = "MT_$const";
			push @EXPORT, $const;
			
			no strict 'refs';
			*{__PACKAGE__ . "::$const"} = sub { $n };
		}
	}

modTypes(<<DATA);
1              a weapon                     weapon
2              more cargo space             cargo
3              ammunition                   ammo
4              more shield capacity         shield
5              faster shield recharge       shield charge
6              armor                        armor
7              acceleration booster         accel
8              speed increase               speed
9              turn rate change             turn
11             escape pod                   escape pod
12             fuel capacity increase       fuel cap
13             density scanner              density scan
14             IFF (colorized radar)        iff
15             afterburner                  afterburner
16             map                          map
17             cloaking device              cloak
18             fuel scoop                   fuel scoop
19             auto-refueller               auto refuel
20             auto-eject                   auto eject
21             clean legal record           clean record
22             hyperspace speed mod         hyper days
23             hyperspace dist mod          hyper dist
24             interference mod             interference
25             marines                      marines
27             increase maximum             max mult
28             murk modifier                murk
29             faster armor recharge        armor charge
30             cloak scanner                cloak scan
31             mining scoop                 mining scoop
32             multi-jump                   multi jump
33             Jamming Type 1               jam 1
34             Jamming Type 2               jam 2
35             Jamming Type 3               jam 3
36             Jamming Type 4               jam 4
37             fast jumping                 fast jump
38             inertial dampener            no inertia
39             ion dissipator               ionize charge
40             ion absorber                 ionize
41             gravity resistance           no gravity
42             resist deadly stellar        no deadly
43             paint                        paint
44             reinforcement inhibitor      no reinf
45             modify max guns              max guns
46             modify max turrets           max turrets
47             bomb                         bomb
48             IFF scrambler                iff scrambler
49             repair system                repair
50             nonlethal bomb               nonlethal bomb
DATA

}

1;
