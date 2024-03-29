package ResourceFork;
use warnings;
use strict;

use Fcntl qw(:DEFAULT :seek);
use Encode;
use File::Basename;

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

sub iread {
    my ($self, $len, $fmt) = @_;
    my $data;
    read($self->{fh}, $data, $len) or die "Can't read: $@";
    return unpack($fmt, $data);
}

my $appleDoubleMagic = 0x00051607;
my $appleSingleMagic = 0x00051600;
my $appleDoubleVersion = 0x00020000;
my $appleDoubleResourceID = 2;

sub findBaseOffset {
    my ($self) = @_;
    seek $self->{fh}, 0, SEEK_SET or die "Can't seek: $@";

    # Maybe it's AppleSingle/AppleDouble?
    my $magic = $self->iread(4, 'l>');
    return 0 unless $magic == $appleSingleMagic || $magic == $appleDoubleMagic;

    $self->iread(4, 'l>') == $appleDoubleVersion or die "Bad AppleDouble version";
    seek $self->{fh}, 16, SEEK_CUR; # filler

    my $entries = $self->iread(2, 's>');
    for (my $i = 0; $i < $entries; $i++) {
        my $id = $self->iread(4, 'l>');
        my $offset = $self->iread(4, 'l>');
        my $length = $self->iread(4, 'l>');
        if ($id == $appleDoubleResourceID) {
            return $offset;
        }
    }

    die "No resource fork found in AppleDouble";
}

sub choosePath {
    my ($path) = @_;
    my $base = basename($path);
    my $exists = sub { return -e $_[0 ] };
    my $nonempty = sub {
        my $size = -s $_[0];
        return $size && $size > 0
    };
    my @choices = (
        $base => $nonempty,
        "$base/..namedfork/rsrc" => $exists,
        "._$base" => $nonempty,
        ".rsrc/$base" => $nonempty,
    );

    my $dir = dirname($path);
    while (my ($f, $ok) = splice(@choices, 0, 2)) {
        my $full = "$dir/$f";
        if ($ok->($full)) {
            return $full
        }
    }

    return $path;
}

sub init {
    my ($self, $path) = @_;
	$self->{path} = choosePath($path);
	$self->open('<');

    if ($path =~ /\.rez$/) {
        $self->initRez();
        return;
    } elsif ($path =~ /\.plt$/) {
        $self->initPlt();
        return;
    }
    
    my $baseoff = $self->findBaseOffset();
    seek($self->{fh}, $baseoff, SEEK_SET) or die "Can't seek to base offset: $@";
    
    my ($filehdr, $map);
    read($self->{fh}, $filehdr, 16) == 16 or die "header too short";
    my ($dataoff, $mapoff, undef, $maplen) = unpack('N4', $filehdr);
    $dataoff += $baseoff;
    $mapoff += $baseoff;

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

sub initRez {
  my ($self) = @_;
  
  my $header;
  read($self->{fh}, $header, 24) == 24 or die "rez header too short";
  my ($sig, $vers, $entries) = unpack('a4Vx12V', $header);
  die 'bad rez sig' unless $sig eq 'BRGR';

  my $offsetsRaw;
  read($self->{fh}, $offsetsRaw, 12 * $entries) == 12 * $entries or die "can't read map offset";
  my @offsets = unpack('(Vx8)*', $offsetsRaw);
  my @sizes = unpack('(x4Vx4)*', $offsetsRaw);

  my $mapHeader;
  seek($self->{fh}, $offsets[-1], SEEK_SET) or die "can't seek to map";
  read($self->{fh}, $mapHeader, 8) == 8 or die "can't read map header";
  my $numTypes = unpack('x4N', $mapHeader);
  seek($self->{fh}, 12 * $numTypes, SEEK_CUR) or die "can't skip type infos";
  
  my $resInfo;
  for (my $i = 0; $i < $entries - 1; $i++) {
    read($self->{fh}, $resInfo, 266) == 266 or die "can't read resource info";
    my ($type, $id, $name) = unpack('x4a4nZ256', $resInfo);
    $type = decode('MacRoman', $type);
    $name = decode('MacRoman', $name);
    
    my $rsrc = {
      fork => $self,
      type => $type,
      id => $id,
      name => $name,
      oob_length => $sizes[$i],
      offset => $offsets[$i],
    };
    bless $rsrc, 'ResourceFork::Resource';
    $self->{rsrc}{$type}{$id} = $rsrc;
  }
}

sub pltResource {
    my ($self, $id) = @_;
    my $len;
    read($self->{fh}, $len, 4) == 4 or die "can't read length";
    $len = unpack('V', $len);
    my $rsrc = {
        fork => $self,
        type => 'plt',
        id => $id,
        name => 'NONE',
        oob_length => $len,
        offset => tell($self->{fh}),
    };
    bless $rsrc, 'ResourceFork::Resource';
    $self->{rsrc}{plt}{$id} = $rsrc;
    seek($self->{fh}, $len, SEEK_CUR) or die "can't skip contents";
}

sub initPlt {
    my ($self) = @_;
    $self->pltResource(128);
    $self->pltResource(129);

    my $name;
    read($self->{fh}, $name, 256);
    $name = unpack('Z*', $name);
    $name = decode('MacRoman', $name);
    $self->{rsrc}{plt}{129}{name} = $name;
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
    return $self->{oob_length} if defined($self->{oob_length});

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
        $self->_readLength == CORE::length($data);
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
