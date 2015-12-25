use warnings;
use strict;

use List::Util qw(max);

sub list {
	my ($type, @finds) = @_;

	for my $res (findRes($type => \@finds)) {
		printf "%4d: %s\n", $res->{ID}, resName($res);
	}
}

sub rankCmp {
	my ($a, $b) = @_;
	return $a <=> $b if looks_like_number($a) && looks_like_number($b);
	return $a cmp $b;
}

sub rank {
    listBuild(1, @_);
}

sub mapOver {
    listBuild(0, @_);
}

sub listBuild {
	my ($sort, $type, $field, $filt) = @_;
	($type, $field) = ('ship', $type) unless defined $field;
    $filt = defined $filt ? eval "no strict 'vars'; sub { $filt }": sub { 1 };

	my $fieldMatch = qr/(\p{Letter}\w{2,})/;
	my $isField = ($field =~ /^$fieldMatch$/);
	my ($fieldSub, $xtra);
	if ($isField) {
		$fieldSub = sub { $::r{$field} };
		$xtra = sub { $::r{Cost} ? commaNum($::r{Cost}) : () };
	} else {
		$fieldSub = eval "no strict 'vars'; sub { $field }";

        my $rez = resource($type);
        my ($i1, $r1) = each %$rez;
		my @used = grep { $_ ne 'Type' && defined $r1->{$_} }
            ($field =~ /$fieldMatch/g);

		$xtra = sub { map {
            defined($::r{$_}) ? formatField(fieldType(\%::r, $_), $::r{$_}) : ()
        } @used };
        rankHeaders(@used);
	}

    listBuildSub(type => $type, value => $fieldSub, filter => $filt,
        print => $xtra, sort => $sort);
}

sub rankHeaders {
    my (@headers) = @_;
    printf "%s%s\n", (' ' x 46), join '  ', map { sprintf '%10s', $_ } @headers;
}

sub listBuildSub {
    my %opts = @_;

    my $type = $opts{type};
    my $value = $opts{value};
    my $filter = $opts{filter} // sub { 1 };
    my $sort = $opts{sort} // 1;
    my $print = $opts{print} // sub { () };

	my $res = resource($type);
    $sort = $sort ? sub { -rankCmp($a->[1], $b->[1]) }
        : sub { $a->[0]{ID} <=> $b->[0]{ID} };
    my @items = sort $sort map {
        local %::r = %$_;
        $filter->() ? [$_, $value->()] : ();
    } values %$res;

	my $size = max (6, map { length($$_[1]) } @items);
	for my $item (@items) {
		my ($r, $v) = @$item;
		local %::r = %$r;
		my @xtra = $print->();
		printf "%${size}s: %-30s %3d    %s\n", $v, resName($r),
			$r->{ID}, join "  ", map { sprintf "%10s", $_ } @xtra;
	}
}

sub makeFilt {
	my ($spec) = @_;
	return sub { 1 } unless defined $spec;

	if ($spec !~ m,[<>=!/&|^()],) {
		if ($spec =~ m,[^-\d\.],) {
			return sub { $_ eq $spec }; # string
		} else {
			my $num = +$spec;
			return sub { $_ == $num }; # num
		}
	}
	my $filt = eval "sub { $spec }";
	die $@ if $@;
	return $filt;
}

sub find {
	my ($idonly) = (0);
	moreOpts(\@_, 'idonly|i+' => \$idonly);

	my $type = shift;
	my ($fldfilt, $filt) = map { makeFilt($_) } (@_, undef, undef);
	my $res = resource($type);

	my (%fields, $fcnt);
	for my $id (sort keys %$res) {
		my $r = $res->{$id};
		unless (%fields) {
			my @names = grep &$fldfilt, grep { $_ ne '_priv' } keys %$r;
			@fields{@names} = map { fieldType($r, $_) } @names;
			$fcnt = scalar(@names) or die "No fields matched";
		}

		for my $field (keys %fields) {
			my $val = $r->{$field};
			local $_ = $val;
			next unless $filt->();

			if ($idonly) {
				printf "%d\n", $id;
			} else {
				my $name = sprintf "%s (%d)", resName($r), $id;
				printf "%6s: %-50s%s\n", formatField($fields{$field}, $val),
					$name, ($fcnt == 1 ? '' : " $field");
			}
			last if $idonly;
		}
	}
}

sub fieldType {
	my ($res, $field) = @_;

	my @order = @{$res->{_priv}{order}};
	my ($idx) = grep { $order[$_] eq $field } (0..$#order);
	return $res->{_priv}{types}[$idx];
}

1;
