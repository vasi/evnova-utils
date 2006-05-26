# Copyright (c) 2006 Dave Vasilevsky
package Nova::Runner::ConText;
use strict;
use warnings;

use base qw(Nova::Runner);
use Nova::Runner::Command;

=head1 NAME

Nova::Command::ConText - commands related to ConText files

=cut

command {
	my ($config, $val) = @_;
	$config->persist('ConText', $val) if defined $val;
	printf "%s\n", $config->conText;
} 'context' => 'get/set the ConText file';


=head1 NAME

Nova::Command::ConText::Using - commands that use the contents of the
default ConText file

=cut

package Nova::Runner::ConText::Using;
use base 'Nova::Runner::ConText';
__PACKAGE__->fields(qw(resources));

use Nova::ConText;
use Nova::Runner::Command;

use Nova::Util qw(printIter regexFilter makeFilter indent);
use Nova::Columns;

sub init {
	my ($self) = @_;
	$self->SUPER::init;
	$self->resources({ });
}

sub run {
	my ($self, $cmd, $config, @args) = @_;
	
	# Get the resources
	my $ctf = $config->conText;
	unless (exists $self->resources->{$ctf}) {
		my $ct = Nova::ConText->new($ctf);
		my $res = $ct->read;
		if (defined $config->option('mem')) {
			$res->noCache;
		} elsif (!defined $config->option('rw')) {
			$res->readOnly;
		}
		$self->resources->{$ctf} = $res;
	}
	my $res = $self->resources->{$ctf};
	
	$self->SUPER::run($cmd, $config, $res, @args);
	
	# Special case: remove the cache if we're reloading
	delete $self->resources->{$ctf} if $cmd->name eq 'reload';
}

command {
	my ($conf, $res) = @_;
	$res->deleteCache;
} reload => 'reload the ConText';

command {
	my ($conf, $res, $type, $spec, @fields) = @_;
	print $res->find($type => $spec)->dump(@fields);
} 'dump' => 'dump a resource';

command {
	my ($conf, $res, $type, @specs) = @_;
	my $verb = $conf->verbose;
	printIter { $_->show($verb) } $res->findIter($type => @specs), $verb;
} show => 'display a resource nicely';

command {
	my ($conf, $res, @types) = @_;
	columns('%s %d: %-s', [ $res->type(@types) ],
		sub { $_->type, $_->ID, $_->fullName });
} listAll => 'list all known resources of the given types';

command {
	my ($conf, $res, $type, @specs) = @_;
	Nova::Resource->list($res->find($type => @specs));
} list => 'list resources matching a specification';

command {
	my ($conf, $res, $spec) = @_;
	my $ship = $res->find(ship => $spec);
	$ship->mass(1);
} mass => 'show the total mass available on a ship';

command {
	my ($conf, $res, $type, $prop) = @_;
	($type, $prop) = ('ship', $type) unless defined $prop;
	
	columns('%s - %d: %-<s  %?s', [ $res->type($type) ],
		sub { $_->format($prop), $_->ID, $_->fullName, $_->rankInfo($prop) },
		rank => sub { $_->$prop }
	);
} rank => 'rank resources by a property';

command {
	my ($conf, $res, $bit, @types) = @_;
	my $verb = $conf->verbose;
	printIter { $_->showBitFields($bit, $verb) } $res->typeIter(@types), $verb;
} bit => 'find items which use a given bit';

command {
	my ($conf, $res, $type, $prop, $filt) = @_;
	my @rs = $res->type($type);
	
	# Filter
	my $filtCode = defined $filt ? makeFilter($filt) : sub { 1 };
	
	# How to get the fields
	my $fieldsRegexCode = regexFilter($prop);
	my $fieldsCode = defined $fieldsRegexCode
		? sub { grep { $fieldsRegexCode->() } $_[0]->fieldNames }
		: sub { $prop };
	
	# Check the fields
	my @match;
	for my $r (@rs) {
		my @fields = $fieldsCode->($r);
		for my $field (@fields) {
			local $_ = $r->$field;
			next unless $filtCode->();
			push @match, { res => $r, fld => $field };
		}
	}
		
	columns('%d: %-<s  %-s: %?s', \@match, sub {
		$_->{res}->ID, $_->{res}->fullName, $_->{fld},
			$_->{res}->field($_->{fld})
	});
} 'map' => 'show a single property of each resource'; 

command {
	my ($conf, $res, @search) = @_;
	printIter { $_->showCommodities } $res->findIter(spob => @search),
		$conf->verbose;
} comm => 'display the commodities at a stellar';

command {
	my ($conf, $res) = @_;
	Nova::Resource->list(grep { $_->persistent } $res->type('outf'));
} persistent => 'display persistent outfits';

command {
	my ($conf, $res) = @_;
	printIter { indent($_->showPersons($conf->verbose)) }
		$res->typeIter('misn'), 0;
} pers => 'display pers missions';

command {
} misc => 'testing';

1;
