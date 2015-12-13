use warnings;
use strict;

sub crons {
	my (@search) = @_;
	my $crons = resource('cron');
	my $govts = resource('govt');
	my $strs = resource('STR#');

	my @matches;
	if (@search) {
		my %matches;
		my @crons = values %$crons;
		while (my $s = shift @search) {
			my @ok;
			if ($s =~ /^\d+$/) {
				@ok = grep { $_->{ID} eq $s } @crons;
			} else {
				@ok = grep { $_->{Name} =~ /$s/i } @crons;
			}
			$matches{$_} = 1 for map { $_->{ID} } @ok;
		}
		@matches = @$crons{keys %matches};
	} else {
		@matches = values %$crons;
	}
	@matches = sort { $a->{ID} <=> $b->{ID} } @matches;

	my @times = map { my $r = $_; map { "$r$_" } qw(Day Month Year) }
		qw(First Last);
	my @defaults = (
		( map { $_ => undef } @times ),
		Random => 100,
		( map { $_ => 0	 } qw(Duration PreHoldoff PostHoldoff) ),
		( map { $_ => '' } qw(EnableOn OnStart OnEnd) ),
	);
	my @flags = ("Iterative entry", "Iterative exit");

	for my $c (@matches) {
		printf "%d: %s\n", $c->{ID}, $c->{Name};				# Name

		my @df = @defaults;
		while (@df) {										# Field with
			my ($f, $d);										# defaults
			($f, $d, @df) = @df;
			my $v = $c->{$f};
			if (defined $d) {
				next if $v eq $d;
			} else {
				next if $v == 0 || $v == -1;
			}
			print "$f: $v\n";
		}

		my $flags = $c->{Flags};								# Flags
		my @pflags;
		for my $i (0..$#flags) {
			my $mask = 1 << $i;
			push @pflags, $flags[$i] if $flags & $mask;
		}
		printf "Flags: %s\n", join ', ', @pflags if @pflags;

		for my $cr (qw(Contrib Require)) {						# Contrib/
			my @v = map { (int($_/(1<<16)), $_ % (1<<16)) }		# Require
				map { $c->{"$cr$_"} } (0, 1);
			next unless grep { $_ } @v;
			printf "$cr: 0x%s\n", join ' ', map { sprintf "%04x", $_ } @v;
		}

		my $printNews = sub {									# News
			my ($govtname, $strid) = @_;
			my $prefix = "News for $govtname:";
			my @strs = @{$strs->{$strid}{Strings}};
			if (scalar(@strs) == 1 && length($strs[0]) + length($prefix) < 80) {
				print "$prefix $strs[0]\n";
			} else {
				print "$prefix\n";
				print_breaking($_, 1, '  * ', '    ') for @strs;
			}
		};

		for my $i (1..4) {
			my $govtid = $c->{"NewsGovt0$i"};
			next if $govtid == 0 || $govtid == -1;
			$printNews->($govts->{$govtid}{Name}, $c->{"GovtNewsStr0$i"});
		}
		my $indie = $c->{"IndNewsStr"};
		$printNews->("Independent", $indie) unless $indie == 0 || $indie == -1;

		print "\n";
	}
}

1;
