use warnings;
use strict;

sub dps {
    my ($weap, $shield) = @_;
    $shield //= 50;
    my $shot = $weap->{MassDmg} * (100 - $shield) +
        $weap->{EnergyDmg} * $shield;
    return $shot / 100 * 30 / $weap->{Reload};
}

sub showDPS {
    my ($shield) = 50;
    moreOpts(\@_,
        'armor|a:100' => sub { $shield = 100 - $_[1] },
        'shield|s:100' => sub { $shield = $_[1] });

    rankHeaders(qw(EnergyDmg MassDmg Reload));
    listBuildSub(type => 'weap',
        value => sub { sprintf "%.1f", dps(\%::r, $shield) },
        filter => sub { ~$::r{Flags} & 2 },
        print => sub { @::r{qw(EnergyDmg MassDmg Reload)} }
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
	my $outfs = resource('outf');

	for my $id (sort keys %$outfs) {
		my $o = $outfs->{$id};
		my $flags = $o->{Flags};
		next unless $flags & 0x8;

		printf "%4d: %s\n", $id, $o->{Name};
	}
}

1;
