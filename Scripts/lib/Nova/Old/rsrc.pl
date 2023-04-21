use warnings;
use strict;
use utf8;

sub readResources {
	my ($file, @specs) = @_;

	my @ret;
  my $rf = ResourceFork->new($file);
	for my $spec (@specs) {
		my $r = $rf->resource($spec->{type}, $spec->{id});
		next unless $r;

		my %res = %$spec;
		$res{name} = $r->{name};
		$res{data} = $r->read;
		push @ret, \%res;
	}

	return @ret;
}

sub writeResources {
	my ($file, @specs) = @_;
  my $rf = ResourceFork->new($file);
	for my $spec (@specs) {
		my $r = $rf->resource($spec->{type}, $spec->{id});
		die "Can't change name"
		    if $spec->{name} && $spec->{name} ne $r->{name};
		$r->write($spec->{data});
	}
}

sub resForkDump {
	my ($file, $type, $id) = @_;
	$type = decode_utf8($type);

	# Hack for pilot files
	if ($type =~ /[MON]piL/) {
		$type =~ tr/i/ï/;
	}

	my ($res) = readResources($file, { type => $type, id => $id });
	print $res->{name}, "\n" if $res->{name};
	hexdump($res->{data});
}

sub resourceLength {
	my ($r) = @_;
	return length $r->{data};
}

sub skip {
	my ($r, $skip) = @_;
	$r->{offset} += $skip;
}
sub skipTo {
	my ($r, $offset) = @_;
	$r->{offset} = $offset;
}

sub readItem {
	my ($r, $len, $fmt) = @_;
	my $offset = $r->{offset} || 0;
	my $d = substr $r->{data}, $offset, $len;
	$offset += $len;
	$r->{offset} = $offset;
	return unpack $fmt, $d;
}

sub readShort {
	readItem(@_, 2, 's>');
}

sub readLong {
	readItem(@_, 4, 'l>');
}

sub readChar {
	readItem(@_, 1, 'C');
}

sub readString {
	my ($r, $len) = @_;
	my @bytes = readItem($r, $len, 'C*');
	my ($end) = grep { $bytes[$_] == 0 } (0..$len-1);
	return '' if $end == 0;
	return pack('C*', @bytes[0..$end-1]);
}

sub readPString {
	my ($r, $len) = @_;
	my @bytes = readItem($r, $len + 1, 'C*');
	my $strlen = shift @bytes;
	return '' if $strlen == 0 || $strlen > $len;
	return pack('C*', @bytes[0..$strlen-1]);
}

sub readDate {
	my ($p, $r) = @_;
	my $year = $p->readShort($r);
	my $month = $p->readShort($r);
	my $day = $p->readShort($r);
	$p->readShort($r) for (1..4);
	return ParseDate(sprintf "%d-%d-%d", $year, $month, $day);
}

sub readSeq {
	my ($r, $sub, $num) = @_;
	return [ map { $sub->($r) } (1..$num) ];
}

sub rsrcList {
	my $verbose = 0;
	moreOpts(\@_, 'verbose|v+' => \$verbose);
	my (@files) = @_;

	for my $file (@files) {
		  my $rf = ResourceFork->new($file);
	    if ($@) {
	        print "$file not a resource fork\n";
	        next;
	    }
		print "File: $file\n";
		for my $type ($rf->types) {
		    my @rs = $rf->resources($type);
			printf "  %4s: %d\n", $type, scalar(@rs);
			if ($verbose) {
				for my $r (@rs) {
					my $size = $r->length;
					if ($size > 9999) {
						$size = sprintf "%.4f", $size;
						$size = substr($size, 0, 4) . " K";
					} else {
						$size .= " b";
					}
					printf "    %4d: %-40s (%6s)\n", $r->{id},
						($r->{name} || ""), $size;
				}
			}
		}
	}
}

1;
