package ResourceFork;
use warnings;
use strict;

use Fcntl qw(:seek);
use Encode;

sub rsrcFork {
    my ($proto, $path) = @_;
    $path .= "/rsrc";
    return $proto->new($path);
}

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	$self->init(@_);
	return $self;
}

sub DESTROY {
    my ($self) = @_;
    close $self->{fh};
}

sub init {
    my ($self, $path) = @_;
    open $self->{fh}, '<:bytes', $path or die "open: $!";
    
    my ($filehdr, $map);
    read($self->{fh}, $filehdr, 16) == 16 or die "header too short";
    my ($dataoff, $mapoff, undef, $maplen) = unpack('N4', $filehdr);
    seek $self->{fh}, $mapoff, SEEK_SET;
    read($self->{fh}, $map, $maplen) == $maplen or die "map too short";
    
    # attrs?
    my ($typeloff, $nameloff, $ntypes) = unpack('@24n3', $map);
    ++$ntypes;
    
    # may point within header, wtf?
    my $origtypeloff = $typeloff;
    $typeloff = 30 if $typeloff < 30;
    
    my @tdata = unpack("\@$typeloff(a4nn)$ntypes", $map);
    while (my ($tname, $tcount, $toff) = splice @tdata, 0, 3) {
        $tname = decode('MacRoman', $tname);
        ++$tcount;
        $toff += $origtypeloff;
        
        my %type;
        my @refdata = unpack("\@$toff(ns>NN)$tcount", $map);
        while (my ($rid, $noff, $doff) = splice @refdata, 0, 4) {
            $doff &= 0xFFFFFF; # 3-byte int
            my $rname;
            if ($noff != -1) {
                $noff += $nameloff;
                $rname = decode('MacRoman', unpack("\@${noff}C/a", $map));
            }
            
            my $rsrc = {
                fork => $self,
                type => $tname,
                id => $rid,
                name => $rname,
                offset => $dataoff + $doff,
            };
            bless $rsrc, 'ResourceFork::Resource';
            $type{$rid} = $rsrc;
        }
        
        $self->{rsrc}{$tname} = \%type;
    }
}

sub types {
    my ($self) = @_;
    return sort keys %{$self->{rsrc}};
}

sub resources {
    my ($self, $type) = @_;
    return sort { $a->{id} <=> $b->{id} } values %{$self->{rsrc}{$type}};
}

sub resource {
    my ($self, $type, $id) = @_;
    return $self->{rsrc}{$type}{$id};
}

sub dump {
    my ($self) = @_;
    foreach my $t ($self->types) {
        foreach my $r ($self->resources($t)) {
            print $r->desc, "\n";
        }
    }
}

package ResourceFork::Resource;
use warnings;
use strict;

use Fcntl qw(:seek);

sub desc {
    my ($self) = @_;
    my $d = sprintf "%4s %5d", $self->{type}, $self->{id};
    $d .= ": $self->{name}" if defined($self->{name});
}

sub read {
    my ($self) = @_;
    my ($len, $data);
    my $fh = $self->{fork}{fh};
    seek $fh, $self->{offset}, SEEK_SET or die "seek: $!";
    read($fh, $len, 4) == 4 or die "resource length too short";
    $len = $self->{length} = unpack('N', $len);
    read($fh, $data, $len) == $len or die "resource too short";
    return $data;
}

sub write {
    my ($self, $data) = @_;
    my $fh = $self->{fork}{fh};
    die "new data must be the same size"
        unless defined($self->{length}) && $self->{length} == length($data);
    seek $fh, $self->{offset} + 4, SEEK_SET or die "seek: $!";
    print $fh, $data;
}


package FinderInfo;
use warnings;
use strict;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(creatorCode typeCode);
our @EXPORT_OK = qw(getxattr finderInfo);

use Encode;

sub getxattr {
    my ($file, $attr) = @_;
    my $data = '';
    open my $fh, '-|', '/usr/bin/xattr', '-px', $attr, $file;
    while (defined(my $line = <$fh>)) {
        $line =~ s/\s+//g;
        $data .= pack 'H*', $line;
    }
    close $fh;
    return $data;
}

sub finderInfo {
    my ($file) = @_;
    return getxattr($file, 'com.apple.FinderInfo');
}

sub typeCode {
    my ($file) = @_;
    return decode('MacRoman', unpack('a4', finderInfo($file)));
}

sub creatorCode {
    my ($file) = @_;
    return decode('MacRoman', unpack('@4a4', finderInfo($file)));
}

1;
