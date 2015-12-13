use warnings;
use strict;

sub misc {
	my ($file) = @_;
	my $vers = pilotVers($file);
	my ($res) = readResources($file, { type => $vers->{type}, id => 129 });
	my $data = simpleCrypt($vers->{key}, $res->{data});
	my $spobid = 502;
	my $defPos = 4;
	my $pos = $defPos + 2 * ($spobid - 128);
	my $str = substr $data, $pos, 2;
	my $count = unpack 's>', $str;
	printf "Remaining: %3d\n", $count;
}

1;
