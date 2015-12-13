use warnings;
use strict;

use utf8;

sub print_breaking {
	my $string = shift;
	my $linebreak = shift // 1; # ignore
	my $pref1 = shift // "";
	my $pref2 = shift // $pref1;

	my ($width) = GetTerminalSize();
	$Text::Wrap::columns = $width if $width;

	print wrap($pref1, $pref2, $string), "\n";
}

sub mkdir_p {
	my $dir = shift;
	make_path($dir);
}

sub deaccent {
	my ($s) = @_;
	$s =~ tr/äëïöüÿ/aeiouy/;
	return lc $s;
}

sub readLineSafe {
    my ($fh) = @_;

    # Ignore encoding errors
    my $w;
    local $SIG{__WARN__} = sub { $w = $_[0] };
    my $line = <$fh>;
    die $w if defined($w) && $w !~ /does not map to Unicode/;

    return $line;
}

sub openFindEncoding {
    my ($file) = @_;
    open my $fh, '<:raw', $file or return undef;

    my $block;
    read $fh, $block, 512;
    binmode $fh, ':eol(LF)' if index($block, "\r") != -1;

    eval { decode_utf8($block, Encode::FB_CROAK) };
    binmode $fh, ($@ ? ':encoding(MacRoman)' : ':utf8');

    seek $fh, 0, SEEK_SET;
    return $fh;
}

sub fileType {
	my ($file) = @_;
	return FinderInfo::typeCode($file);
}

sub moreOpts {
    my ($args, %opts) = @_;
    local @ARGV = @$args;
    GetOptions(%opts) or die "Can't get options: $!\n";
    @$args = @ARGV;
}

sub tsv {
	my (@data) = @_;
	for my $d (@data) {
		$d =~ s/"/\\"/g;
		$d =~ s/^(.*\s.*)$/"$1"/; # quote;
		$d = '""' if $d eq '';
	}
	return join("\t", @data) . "\n";
}

sub commaNum {
	my ($n) = @_;
	return $n if $n < 1000;
	return commaNum(int($n/1000)) . sprintf ",%03d", $n % 1000;
}

sub hexdump {
	my ($data) = @_;
	my @bytes = unpack 'C*', $data;

	my $last;
	my $continuing = 0;
	my $offset = 0;
	my $perline = 16;
	my $linelen = 3 * $perline + int($perline / 8);
	while (scalar(@bytes) >= $offset) {
		my $max = $offset + $perline - 1;
		$max = $#bytes if $#bytes < $max;
		my @line = @bytes[$offset..$max];

		my $key = pack 'C*', @line;
		if (defined $last && $last eq $key) {
			printf "%8s\n", '*' unless $continuing;
			$continuing = 1;
		} else {
			$continuing = 0;
			$last = $key;

			my ($text, $line) = ('', '');
			for my $i (0..$#line) {
				$line .= ' ' if $i % 8 == 0;
				my $v = $line[$i];
				$line .= sprintf ' %02x', $v;

				my $chr = $v > 31 ? ($v > 127 ? '?' : chr($v)) : '.';
				$text .= $chr;
			}
			printf "%8x%-*s  |%-*s|\n", $offset, $linelen, $line, $perline,
				$text;
		}
		$offset += $perline;
	}
}


1;
