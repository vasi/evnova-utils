use warnings;
use strict;

sub tieHash {
	my ($file) = @_;
	my %hash;
	tie %hash, 'BerkeleyDB::Hash', -Filename => $file, -Flags => DB_CREATE
		or die "Can't tie cache $file: $!\n";
	return \%hash;
}

{
	my %memory;

	sub memory {
		my ($name) = @_;
		unless (defined $memory{$name}) {
			my $dir = File::Spec->catfile(contextCache(), '.memoize');
			mkdir_p($dir) unless -d $dir;
			my $file = File::Spec->catfile($dir, $name);

			$memory{$name} = tieHash($file);
		}
		return $memory{$name};
	}
}

sub memoize {
	memoize_internal(
		args => \@_,
		encode => sub { join(',', @_) },
		decode => sub { $_[0] },
	);
}

sub memoize_complex {
	memoize_internal(
		args => \@_,
		encode => sub { freeze \@_ },
		decode => sub { (thaw $_[0])->[0] },
	);
}

sub memoize_internal {
	my %opts = @_;
	my @args = @{$opts{args}};

	my $code = pop @args;
	my $name = (caller(2))[3];
	my $memory = memory($name);
	my $key = $opts{encode}->($name, @args);

	my $ret;
	if (exists $memory->{$key}) {
		$ret = $opts{decode}->($memory->{$key});
	} else {
		my $memo = sub {
			my $ret = pop @_;
			my $key = $opts{encode}->($name, @_);
			$memory->{$key} = $opts{encode}->($ret);
		};
		unshift @args, $memo;
		$ret = wantarray ? [ $code->(@args) ] : scalar( $code->(@args) );
		$memory->{$key} = $opts{encode}->($ret);
	}
	return wantarray ? @$ret : $ret;
}

1;
