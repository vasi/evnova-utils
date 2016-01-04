use warnings;
use strict;

use utf8;
binmode STDOUT, ":utf8";

our $conTextOpt;

our @cmds;
@cmds = (
	0 => 'Configuration',
	getcontext	=> [\&printConText, '', "show default ConText file"],
	setcontext	=> [\&setConText, 'FILE', "set default ConText file"],

	0 => 'Generic tools',
	list		=> [\&list, 'TYPE [SPEC]', 'list resources'],
	'dump'		=> [\&resDump, 'TYPE SPEC [FIELDS..]',
		'dump fields of a resource'],
	'dumps'		=> [\&dumpMany, 'TYPE FIELDS SPECS...',
		'dump fields of several resources'],
	find		=> [\&find, '[-i] TYPE FIELDSPEC VALSPEC',
		'find resources which match criteria',
		'Flag --idonly only displays resource ID',
		'Specs can be regexps, strings, numbers, or code'],
	rank		=> [\&rank, 'TYPE FIELD [FILT]',
        'sort resources by field value'],
	'map'		=> [\&mapOver, 'TYPE FIELD [FILT]',
		'show all values of a given field'],
	diff		=> [\&diff, 'TYPE SPEC1 SPEC2',
		'show differences between two resources'],

	0 => 'Ships',
	mass		=> [\&showShipMass, 'SHIP', 'show space usage of a ship'],
	mymass		=> [\&myMass, 'PILOT', 'show space usage of pilot'],
	masstable	=> [\&massTable, '[--tsv] [--removable]',
        'rank ships by total space'],
	defense		=> [\&defense, '[ARMOR_WEIGHT]',
		'rank ships by shield and armor'],
	agility		=> [\&agility, '[ACCEL_WEIGHT] [MANEUVER_WEIGHT]',
		'rank ships by speed and agility'],
	shiptech	=> [\&shiptech, '', 'show tech level of each ship'],
	capture		=> [\&capture, '[--pilot PILOT | --log PILOTLOG] [-v] SHIP',
		'calculate odds of capturing a ship'],
	dude		=> [\&dude, 'DUDE', 'show ships and strength of a fleet'],
	shieldre	=> [\&shieldRegen, 'RSRC [REGEN_MOD] [SHIELD_MOD]',
		'show old EV shield regen rates',
		'Use "Override Data 2" as the resource file for EVO'],

	0 => 'Outfits',
	persistent	=> [\&persistent, '', 'list persistent outfits'],
	cantsell	=> [\&cantSell, '', 'list unsellable outfits'],
	outftech	=> [\&outftech, '', 'show tech level of each outfit'],
    sellable    => [\&sellable, 'PILOT', 'show outfits that can be sold'],
    dps         => [\&showDPS, '[--armor | --shield | --shield=%]',
        'rank primary weapons by damage output'],

	0 => 'Missions',
	misn		=> [\&misn, '[-v] SPECSET', 'show mission details'],
	pers		=> [\&persMisns, '', 'list pers missions'],
	limit		=> [\&limitMisns, '', 'list time-limited missions'],
	bit			=> [\&bit, 'BIT', 'show where a bit is used'],
	avail		=> [\&availMisns, '[-vufrlip] PILOT [PROGRESS]',
		'show currently available missions',
		'Flag --unique only lists non-repeatable missions',
		'Flag --fieldcheck only lists missions that set bits',
		'Flag --idonly only shows ID of available missions',
		'Flag --rating filters missions that need higher combat rating',
		'Flag --legal filters missions that need better legal record',
		'Flag --nopers filters out pers missions',
		'A progress file can list missions to be ignored, eg:',
		'  128: Include this mission',
		'  -129: Ignore this one'],

	0 => 'Finding systems and stellar objects',
	spobsyst	=> [\&printSpobSyst, 'SPOB',
		'find which system contains a planet'],
	dist		=> [\&showDist, 'SYST1 SYSY2',
		'find shortest path between systems'],
    placedist => [\&showPlaceDist, '[TYPE1] SPEC1 [TYPE2] SPEC2',
        'find shortest distance between two place specs',
        'Types include: syst spob adjacent govt ngovt ally enemy'],
	spobtech	=> [\&spobtech, '[--outfit | --ship] [govt GOVT | TECH]',
		'find where to buy items of a tech level',
		'Can limit to spobs of one govt, or to one tech level'],
	closetech	=> [\&closestTech, 'SYST TECH',
		'find the closest planet that sells items of a tech level'],
	closeoutf	=> [\&closestOutfit, '[PILOT | --syst SYST] OUTFIT',
		'find the closest place to buy an outfit'],
	where		=> [\&whereShip, 'SHIP [MAXPLACES]',
		'show where a ship type is likely to be found'],
	wherepers	=> [\&wherePers, 'PILOT PERS',
		'show where a pers ship is likely to be found'],
	hiddenspobs	=> [\&hiddenSpobs, '',
		'list stellar objects without a nav preset'],

	0 => 'Other resource types',
	'grep'		=> [\&grepDescs, 'REGEXP',
		'search for a string in descriptions'],
	desc		=> [\&desc, 'TYPE SPEC', 'show description resources',
		'TYPE is one of spob, outf, misn, ship, hire'],
	crons		=> [\&crons, '[SPECS..]', 'show cron details'],
	comm		=> [\&commodities, 'SPOB',
		"show what commodities a planet has"],
	junk		=> [\&listJunk, '[SPECS..]', 'show weird trade items'],
	killable	=> [\&killable, '', 'list all killable pers ships'],
    systpers    => [\&systPers, 'PILOT SYST',
        'list pers ships that could appear in a system'],

	0 => 'Legal records',
	records		=> [\&records, '', 'list legal record names'],
	legal		=> [\&legalFromPilot, 'PILOT SYSTS..',
		'show legal record in systems'],
	legalgovt	=> [\&legalGovt, 'PILOT GOVT [COUNT]',
		'show where a government likes you most'],
	suckup		=> [\&suckUp, '[--pilot PILOT] GOVT',
		'show missions that affect your record with a government'],

	0 => 'Pilot files',
	pilot		=> [\&pilotShow, 'FILE [FIELDS..]', 'show pilot details'],
	rating		=> [\&rating, 'PILOT', 'show current combat rating'],
	revive		=> [\&revivePers, '[--kill] [--syst] FILE PERS...',
		'revive a killable pers'],
	cash		=> [\&setCash, 'FILE CREDITS', 'set pilot credit count'],
	setbits		=> [\&setBits, 'PILOT BITS..', 'set or unset pilot bits',
		'Start a bit with ! to unset it'],
	setoutf => [\&setOutf, 'PILOT OUTFIT [COUNT]', 'give or remove outfits'],
	setship => [\&setShip, 'PILOT SHIP', 'change the ship type'],
	teleport => [\&setSpob, 'PILOT SPOD', "change the pilot's location"],
	explore => [\&addExplore, 'PILOT [SYSTS...]', "add to the pilot's map"],
	escort => [\&addEscort, 'PILOT SHIP [COUNT]', "add escorts"],
	setrating => [\&setRating, 'PILOT RATING', "set rating"],
	setrecord => [\&setRecord, 'PILOT RECORD [--govt] SPECS...', "set legal record"],

	0 => 'Miscellaneous',
	trade		=> [\&trade, '[ITERATIONS]',
		'search for the best trade routes'],
	dominate	=> [\&dominate, '[-p PILOT]',
		'rank planetary defense fleet strength'],
	help		=> [\&help, '[COMMAND]', 'show command usage'],

	0 => 'Raw resources',
	rsrc		=> [\&rsrcList, '[-v] FILES..', 'list raw resources'],
	resdump		=> [\&resForkDump, 'FILE TYPE ID',
		'hex dump raw resource'],

	0 => 'Debugging',
	pilotdump	=> [\&pilotDump, 'FILE RESOURCE_ID OUTPUT',
		'export decrypted pilot resource'],
	pilothex	=> [\&pilotHex, 'FILE', 'hex dump decrypted pilot file'],
	legs		=> [\&printLegs, '',
		'list the best trade legs (partial routes)'],
	bittest		=> [\&bitTestPrint, 'NCB [BITS..]',
		'evaluate a control bit expression', 'Given a set of bits'],
	misc        => [\&misc, '', 'scratch pad'],
);

sub help {
	my ($cmd) = @_;
	print <<USAGE unless $cmd;
Usage: $0 [-c CONTEXT] COMMAND [ARGUMENTS..]

Examine Escape Velocity data files, resources and pilot files. Works on EV Classic, Override, and Nova.

To get the ConText files needed by this program, use the w00tWare utilities available here:
http://davidarthur.evula.net/resedit/ResEdit/ResEdit_and_NovaTools.html

Available sub-commands:
USAGE
	my $maxlen = 0;
	for my $c (keys %{{@cmds}}) {
		$maxlen = length($c) if $c && length($c) > $maxlen;
	}

	my @cs = @cmds;
	while (my ($c, $v) = splice(@cs, 0, 2)) {
		my ($sub, $args, $short, @long) = @$v if $c;
		if (!$cmd) {
			if ($c) {
				printf "  %-${maxlen}s  %s\n", $c, $short;
			} else {
				printf "\n$v:\n";
			}
		} elsif ($c eq $cmd) {
			print "$0 $cmd $args\n\n$short\n";
			print map { "$_\n" } ('', @long) if @long;
			return;
		}
	}
	die "Command '$cmd' unknown\n" if $cmd;
}

sub run {
	Getopt::Long::Configure(qw(pass_through bundling));
	GetOptions(
		'context|c=s'	=> \$conTextOpt,
	);

	my %cmdh = @cmds;
	my $cmd = lc(shift(@ARGV) || 'help');
	die "No such command \"$cmd\"\n" unless exists $cmdh{$cmd};
	&{$cmdh{$cmd}[0]}(@ARGV);
}

1;
