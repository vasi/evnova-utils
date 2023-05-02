use warnings;
use strict;

use Math::BigInt;

our @misnNCBset;

# 0 => no bit, + => positive, - => negative
sub hasBit {
	my ($fld, $bit) = @_;

	return 0 unless $fld =~ /(.?)\b$bit\b/;
	return $1 eq '!' ? -1 : 1;
}

sub bit {
	my ($bit) = @_;
	$bit =~ s/^(\d+)$/b$1/;

	my $bitInResource = sub {
	    my ($type, @fields) = @_;
	    @fields = sort @fields;
	    my $resources = resource($type);
	    for my $id (sort keys %$resources) {
					my $r = $resources->{$id};
	        my @has;
	        for my $f (@fields) {
	            push @has, $f if hasBit($r->{$f}, $bit);
	        }

	        if (@has) {
	          printf "%s %4d: %s\n", $type, $r->{ID}, resName($r);
						printf "     %s: %s\n", $_, $r->{$_} foreach @has;
	        }
	    }
	};

	$bitInResource->('misn', @misnNCBset, 'AvailBits');
	$bitInResource->('cron', qw(EnableOn OnStart OnEnd));
	$bitInResource->('outf', qw(Availability OnPurchase OnSell));
	$bitInResource->('ship', qw(Availability AppearOn OnPurchase
	        OnCapture OnRetire));
    $bitInResource->('syst', qw(Visibility));

	$bitInResource->('char', qw(onStart));
	$bitInResource->('pers', qw(ActivateOn));
	$bitInResource->('flet', qw(ActivateOn));
	$bitInResource->('spob', qw(OnDominate OnRelease OnDestroy OnRegen));
	$bitInResource->('junk', qw(BuyOn SellOn));
	$bitInResource->('oops', qw(ActivateOn));
	$bitInResource->('desc', qw(Description));
}

{
	my %single = map { $_ => 1 } qw(! g | &);
	my %num = map { $_ => 1 } qw (b p o e);
	my %plevel = ( '(' => 1, ')' => -1 );

	sub bitTestTokenize {
		my (@chars) = @_;

		# Tokenize
		my @toks;
		while (defined(my $c = shift @chars)) {
			if ($single{$c}) {
				push @toks, { type => $c };
			} elsif ($num{$c}) {
				my $n = '';
				$n .= shift @chars while @chars && $chars[0] =~ /\d/;
				die "Incomplete bit term\n" if $n eq '';
				push @toks, { type => $c, num => $n };
			} elsif ($c =~ /\d/) {
				$c .= shift @chars while @chars && $chars[0] =~ /\d/;
				push @toks, { type => '1', num => $c };
			} elsif ($c eq '(') {
			    my $count = 1;
			    my @s;
			    while (1) {
			        defined(my $s = shift @chars) or croak "Incomplete parens\n";
			        $count += $plevel{$s} || 0;
			        last unless $count;
			        push @s, $s;
			    }
				push @toks, { type => $c, expr => bitTestParseInner(@s) };
			} else {
				die "Unknown character $c\n";
			}
		}

		return @toks;
	}
}

sub bitTestResolveToks {
	my (@toks) = @_;
	die "No tokens\n" unless @toks;

	# and, or
	for my $op (qw(& |)) {
		if (grep { $_->{type} eq $op } @toks) {
			my $etype = $op eq '&' ? 'and' : 'or';

			my (@subs, @cur);
			while (defined (my $t = shift @toks)) {
				if ($t->{type} eq $op) {
					push @subs, bitTestResolveToks(@cur);
					@cur = ();
				} else {
					push @cur, $t;
				}
			}
			push @subs, bitTestResolveToks(@cur);
			return [ $etype => \@subs ];
		}
	}

	# not
	if ($toks[0]{type} eq '!') {
		shift @toks;
		return [ 'not' => bitTestResolveToks(@toks) ];
	}

	die "Too many tokens\n" if scalar(@toks) != 1;
	my $tok = $toks[0];

	# parens
	if ($tok->{type} eq '(') {
		return $tok->{expr};
	}

	my %terms = ( b => 'bit', p => 'paid', g => 'gender', o => 'outfit',
		e => 'explored', '1' => 'constant' );
	die "Bad token $tok->{type}\n" unless $terms{$tok->{type}};
	my $etype = $terms{$tok->{type}};
	my $val = $tok->{num}; # possibly undef
	return [ $etype => $val ];
}

sub bitTestParseInner {
	my (@chars) = @_;
	my @toks = bitTestTokenize(@chars);
	return bitTestResolveToks(@toks);
}

sub bitTestParse {
	my ($expr) = @_;
	$expr =~ s/\s//g;
	$expr = lc $expr;
	return [ constant => 1 ] unless $expr; # empty means true
	return bitTestParseInner(split //, $expr);
}

sub bitTestEvalParsed {
	my ($termSub, $parsed) = @_;
	my ($etype, $val) = @$parsed;
	if ($etype eq 'and') {
		return !grep { !bitTestEvalParsed($termSub, $_) } @$val;
	} elsif ($etype eq 'or') {
		return grep { bitTestEvalParsed($termSub, $_) } @$val;
	} elsif ($etype eq 'not') {
		return !bitTestEvalParsed($termSub, $val);
	} elsif ($etype eq 'constant') {
		return $val;
	} else {
		return $termSub->($etype, $val);
	}
}

sub bitTestEval {
	my ($termSub, $expr) = @_;
	return bitTestEvalParsed($termSub, bitTestParse($expr));
}

sub bitTestEvalSimple {
	my ($expr, @bits) = @_;
	my %bits = map { $_ => 1 } @bits;

	my $termSub = sub {
		my ($type, $val) = @_;
		return exists $bits{$val} if $type eq 'bit';
		return 1;
	};
	return bitTestEval($termSub, $expr);
}

sub bitTestEvalPilot {
	my ($expr, $pilot) = @_;
	my $termSub = sub {
		my ($type, $val) = @_;
		return $pilot->{bit}[$val] if $type eq 'bit';
		return 1;
	};
	return bitTestEval($termSub, $expr);
}

sub bitTestPrint {
	my $ret = bitTestEvalSimple(@_);
	print($ret ? "True" : "False", "\n");
}

sub initiallyTrue {
	my ($val) = @_;
	return bitTestEvalSimple($val);
}

my %contribRequires = (
	Contribute => [qw[cron outf rank ship]],
	Require => [qw[cron govt misn outf ship]],
);

my %contribRequireVariants = (
  Contribute => [qw[Contribute Contributes Contrib]],
  Require => [qw[Require]],
);

sub stringifyContribRequire {
	my ($x) = @_;
	my ($q, $r) = $x->copy()->bdiv(Math::BigInt->new(1)->blsft(32));
	return sprintf("0x%08x %08x", $q->numify(), $r->numify());
}

sub getContribRequire {
	my ($res, $name) = @_;
  my @vals;
  for my $field (@{$contribRequireVariants{$name}}) {
    @vals = multiProps($res, $field);
    last if @vals;
  }
	my ($a, $b) = map { Math::BigInt->new($_) } @vals;
	return $a->badd($b->blsft(32));
}

sub contribRequire {
	my ($idx) = @_;
	my $bit = Math::BigInt->new(1)->blsft($idx);

  my %resFields = ();
  while (my ($field, $types) = each %contribRequires) {
    for my $type (@$types) {
      push @{$resFields{$type}}, $field;
    }
  }

  for my $type (sort keys %resFields) {
    my @fields = sort @{$resFields{$type}};
    my $resources = resource($type);
    for my $id (sort keys %$resources) {
      my $res = $resources->{$id};
      my $foundRes;
      for my $field (@fields) {
        my $val = getContribRequire($res, $field);
        if (!$bit->copy()->band($val)->is_zero()) {
          if (!$foundRes) {
            printf("%s %5d: %s\n", $type, $res->{ID}, resName($res));
            $foundRes = 1;
          }
          printf("  %s: %s\n", $field, stringifyContribRequire($val));
        }
      }
    }
  }
}

1;
