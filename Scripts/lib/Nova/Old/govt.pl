use warnings;
use strict;

sub scanGovts {
  my ($mask) = @_;
  my @ret;
  my $govts = resource('govt');

  for my $id (sort keys %$govts) {
    my $govt = $govts->{$id};
    push @ret, $govt if ($govt->{ScanMask} & $mask);
  }
  return @ret;
}

1;
