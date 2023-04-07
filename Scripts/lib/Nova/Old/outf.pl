use warnings;
use strict;

sub dps {
    my ($weap, $shield) = @_;
    $shield //= 50;
	my $reload = $weap->{Reload} || 1;
    my $shot = $weap->{MassDmg} * (100 - $shield) +
        $weap->{EnergyDmg} * $shield;
    return $shot / 100 * 30 / $reload;
}

sub weapRange {
    my ($weap) = @_;
    if ($weap->{BeamLength} > 0) {
        return $weap->{BeamLength};
    }
    return $weap->{Speed} * $weap->{Count} / 100;
}

sub showDPS {
    my ($shield) = 50;
    moreOpts(\@_,
        'armor|a:100' => sub { $shield = 100 - $_[1] },
        'shield|s:100' => sub { $shield = $_[1] });

    rankHeaders(qw(EnergyDmg MassDmg Reload Range));
    listBuildSub(type => 'weap',
        value => sub { sprintf "%.1f", dps(\%::r, $shield) },
        filter => sub {
            $::r{AmmoType} < 0
                && ($::r{EnergyDmg} + $::r{MassDmg}) > 0 },
        print => sub { @::r{qw(EnergyDmg MassDmg Reload)}, weapRange(\%::r) }
    );
}

sub persistent {
	my $outfs = resource('outf');

	for my $id (sort keys %$outfs) {
		my $o = $outfs->{$id};
		my $flags = $o->{Flags};
		next unless $flags & 0x4;

		printf "%4d: %s\n", $id, $o->{Name};
	}
}

sub cantSell {
    my ($gifts, $mass);
    moreOpts(\@_, 'gifts' => \$gifts, 'mass' => \$mass);
	my $outfs = resource('outf');

    my %techs;
    my %defaults;
    if ($gifts) {
        # Sold techs aren't gifts
        my $spobs = resource('spob');
        foreach my $spob (values %$spobs) {
            for (my $i = $spob->{TechLevel}; $i > 0; $i--) {
                $techs{$i} = 1;
            }
            foreach my $level (multiProps($spob, 'SpecialTech')) {
                $techs{$level} = 1 unless $level == -1;
            }
        }

        # Ship defaults aren't gifts
        my $weaps = resource('weap');
        my $w2o = weaponOutfits($outfs, $weaps);
        my $ships = resource('ship');
        foreach my $ship (values %$ships) {
            foreach my $item (shipDefaultItems($ship)) {
                eval {
                    my $outf = itemOutfit($w2o, $outfs, $item);
                    $defaults{$outf->{ID}} = 1 if defined $outf;
                }
            }
        }
    }

	for my $id (sort keys %$outfs) {
        next if $defaults{$id};
		my $o = $outfs->{$id};
		my $flags = $o->{Flags};
		next unless $flags & 0x8;
        next if $mass && $o->{Mass} <= 0;
        next if $techs{$o->{TechLevel}};

		printf "%4d: %s\n", $id, $o->{Name};
	}
}

1;
