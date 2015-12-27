use warnings;
use strict;

{
	my %cache;

	sub resource {
		my ($type, %opts) = @_;
		%opts = (cache => 1, %opts);
		$type = deaccent($type);

		delete $cache{$type} unless $opts{cache};
		unless (exists $cache{$type}) {
			my $dir = File::Spec->catdir(contextCache(), '.resource');
			my $cacheFile = File::Spec->catfile($dir, $type);
			if ($opts{cache} && -f $cacheFile && -M $cacheFile < -M getConText()) {
				$cache{$type} = retrieve $cacheFile;
			} else {
				my $ret = readContext(getConText(), $type)->{$type} || {};
				if ($opts{cache}) {
					mkdir_p($dir) unless -d $dir;
					nstore $ret, $cacheFile;
				}
				$cache{$type} = $ret;
			}
		}

		return $cache{$type};
	}
}

sub formatField {
	my ($type, $data) = @_;
	if ($type eq 'color') {
		return sprintf '#%06x', $data;
	} elsif ($type =~ /hex(\d+)/) {
		return sprintf "0x%0${1}x", $data;
	} elsif ($type eq 'list') {
		return "\n" . join('',
			map { sprintf "  %3d: %s\n", $_, $data->[$_] } (0..$#$data)
		);
	} else {
		return $data;
	}
}

sub resDump {
	my ($type, $find, @fields) = @_;
	my @filters = map { makeFilt($_) } @fields;

	my $res = findRes($type => $find);
	die "No such item '$find' of type '$type'\n" unless defined $res;
	extrasAdd($res);

	my $idx = 0;
	for my $k (@{$res->{_priv}->{order}}) {
		my $want = !@filters;
		for my $f (@filters) {
			local $_ = $k;
			$want = $f->();
			last if $want;
		}

		printf "%s: %s\n", $k,
			formatField($res->{_priv}->{types}->[$idx], $res->{$k}),
			if $want;
		++$idx;
	}
}

sub dumpMany {
	my ($type, $fields, @specs) = @_;
	my @res = findRes($type => \@specs);

	my $i = 0;
	for my $r (@res) {
		print "\n" if $i++;
		resDump($type, $r->{ID}, 'ID', $fields);
	}
}

sub govtName {
	my ($govt) = @_;
	return defined $govt ? $govt->{Name} : "independent";
}

sub resName {
	my ($res) = @_;
	my $name = $res->{Name};
	my $sub = $res->{SubTitle};
	if (deaccent($res->{Type}) eq 'ship' && $sub) {
		return "$name, $sub";
	} else {
		return $name;
	}
}

sub findRes {
	my ($type, $find) = @_;

	if (ref($find) eq 'ARRAY') {
		@$find = ('') unless @$find;
		my %res = map { $_->{ID} => $_ } map { findRes($type, $_) } @$find;
		return map { $res{$_} } sort { $a <=> $b } keys %res;
	}

	my $res = resource($type, cache => 1);
	if ($find =~ /^\d+$/) {
		my $r = $res->{$find};
		return wantarray ? ($r) : $r;
	}

    my @res = sort { $a->{ID} <=> $b->{ID} } values %$res;

    $find =~ s/\W//g; # strip punct
    return @res if $find eq '';

    $find = qr/$find/i;
	my $whole = qr/^$find$/i;
	my @found;
	for my $r (@res) {
		my $name = resName($r);
		$name =~ s/\W//g; # strip punct
		return $r if $name =~ /$whole/ && !wantarray;
		push @found, $r if $name =~ /$find/;
	}

	return wantarray ? @found : $found[0];
}

sub diff {
	my ($type, $f1, $f2) = @_;
	my ($r1, $r2) = map { findRes($type => $_) } ($f1, $f2);
	extrasAdd($r1, $r2);

	my $idx = 0;
	for my $k (@{$r1->{_priv}->{order}}) {
		my ($v1, $v2) = map { $_->{$k} } ($r1, $r2);

		if ($v1 ne $v2) {
			my $type = $r1->{_priv}->{types}->[$idx];
			printf "%15s: %-31s %-31s\n", $k,
				map { formatField($type, $_) } ($v1, $v2);
		}
		++$idx;
	}
}

sub multiProps {
	my ($obj, $prefix, $ignore) = @_;
	$ignore = -1 unless defined $ignore;

	my @keys = grep /^$prefix\d*$/, keys %$obj;
	my @vals = @$obj{@keys};
	@vals = grep { $_ ne $ignore} @vals;
	return @vals;
}

sub multiPropsHash {
	my ($obj, $prefix, $valpref, $ignore) = @_;
	$ignore = -1 unless defined $ignore;

	my %ret;
	for my $kk (sort keys %$obj) {
		(my $vk = $kk) =~ s/^$prefix(\d*)$/$valpref$1/ or next;
		next if $obj->{$kk} eq $ignore;
		push @{$ret{$obj->{$kk}}}, $obj->{$vk};
	}
	return %ret;
}

1;
