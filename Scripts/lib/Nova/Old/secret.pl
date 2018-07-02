use warnings;
use strict;

use List::Util qw(max);
use Math::BigInt;

sub secretSalt {
  my ($type) = @_;
  my $str = join(',', getConText(), $type);
  my $crypted = substr(crypt($str, $str), -4);
  return unpack('N', $crypted);
}

{
  my @primes = (2);

  sub findNextPrime {
    for (my $i = $primes[-1] + 1; ; $i++) {
      for my $j (@primes) {
        if ($j * $j > $i) {
          # Found a prime!
          push @primes, $i;
          return;
        }
        last if $i % $j == 0;
      }
    }
  }

  sub primeAtLeast {
    my ($i) = @_;
    findNextPrime() while $primes[-1] < $i;
    my ($ret) = grep { $_ >= $i } @primes;
    return $ret;
  }
}

sub secretSize {
  my ($type) = @_;
  my $max = max map { $_->{ID} } values %{resource($type)};
  return primeAtLeast($max);
}

sub secretInvert {
  my ($size, $i) = @_;
  return Math::BigInt->new($i)->bmodinv($size)->numify();
}

sub secretEncode {
  my ($type, $id) = @_;
  my $salt = secretSalt($type);
  my $size = secretSize($type);
  return '#' . secretInvert($size, $salt + $id);
}

sub secretDecode {
  my ($type, $i) = @_;
  if ($i =~ /^#(\d+)$/) {
    my $salt = secretSalt($type);
    my $size = secretSize($type);
    $i = (secretInvert($size, $1) - $salt) % $size;
  }
  return $i;
}

1;
