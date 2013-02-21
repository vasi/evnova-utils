package ResourceFork;
use warnings;
use strict;

use Fcntl qw(:DEFAULT :seek);
use Encode;

sub rsrcFork {
    my ($proto, $path) = @_;
    $path .= "/..namedfork/rsrc";
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
	$self->{path} = $path;
	$self->open('<');
    
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

sub open {
	my ($self, $mode) = @_;
	close $self->{fh} if defined $self->{fh};
    open $self->{fh}, "$mode:bytes", $self->{path} or die "open: $!";
}
sub writable {
	my ($self) = @_;
	my $mode = fcntl($self->{fh}, F_GETFL, 0);
	$self->open('+<') unless $mode == O_RDWR;
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

sub _readLength {
    my ($self, $force) = @_;
    return $self->{length} if !defined($force) && defined($self->{length});
    
    my $fh = $self->{fork}{fh};
    seek $fh, $self->{offset}, SEEK_SET or die "seek: $!";
    my $len;
    read($fh, $len, 4) == 4 or die "resource length too short";
    return $self->{length} = unpack('N', $len);
}

sub length {
	my ($self) = @_;
	return $self->_readLength;
}

sub read {
    my ($self) = @_;
    my $fh = $self->{fork}{fh};
    my $len = $self->_readLength('force');
    my $data;
    read($fh, $data, $len) == $len or die "resource too short";
    return $data;
}

sub write {
    my ($self, $data) = @_;
	$self->{fork}->writable();
    my $fh = $self->{fork}{fh};
    die "new data must be the same size" unless
        $self->_readLength == length($data);
    seek $fh, $self->{offset} + 4, SEEK_SET or die "seek: $!";
    print $fh $data;
}


package FinderInfo;
use warnings;
use strict;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(creatorCode typeCode);
our @EXPORT_OK = qw(listxattr getxattr finderInfo);

use Encode;

sub xattr {
    my ($file, @opts) = @_;
    open my $fh, '-|', '/usr/bin/xattr', @opts, $file or die "Can't run xattr: $!\n";
    my @lines = <$fh>;
    close $fh;
    chomp @lines;
    return @lines;
}

sub listxattr {
    my ($file) = @_;
    return xattr($file);
}

sub getxattr {
    my ($file, $attr) = @_;
    return undef unless grep { $_ eq $attr } listxattr($file);
    my $data = join('', xattr($file, '-px', $attr));
    $data =~ s/\s+//g;
    return pack 'H*', $data;
}

sub finderInfo {
    my ($file) = @_;
    return getxattr($file, 'com.apple.FinderInfo');
}

sub typeCode {
    my ($file) = @_;
    my $finfo = finderInfo($file) or return undef;
    return decode('MacRoman', unpack('a4', $finfo));
}

sub creatorCode {
    my ($file) = @_;
    my $finfo = finderInfo($file) or return undef;
    return decode('MacRoman', unpack('@4a4', $finfo));
}

1;
