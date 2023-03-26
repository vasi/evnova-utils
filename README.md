evnova-utils
============

Perl utilities for examining the internals of the [Escape Velocity](https://en.wikipedia.org/wiki/Escape_Velocity_(video_game)) series of games.

Use this to:
* Understand what are the different pieces that make up a game
* Resolve confusing situations, without gross cheating
* Cheat, by modifying your pilot files
* Debug any plugins you're making

__Spoiler alert! Don't look things up unless you want to know about them.__

# Quickstart

Assuming you're on Ubuntu 22.04:

* Install dependencies: `sudo apt install libyaml-syck-perl libmldbm-perl libberkelydb-perl libdate-manip-perl libterm-readkey-perl libperlio-eol-perl`
* Go to the directory where scripts live: `cd ./Scripts`
* Configure which game to use with the `setcontext` command. Eg, for EV Override: `./old.pl setcontext ../Context/EVOConText.txt`
* Get a list of all weapons in the game: `./old.pl list weap`
* Get a list of all available subcommands: `./old.pl help`
* Get help for a subcommand: `./old.pl help list`

# What's here?

* __Context__: Data files describing the content of various EV games. These can be generated from any EV game or plugin using the "ConText/ResStore" tool, available from the [EVN addons page](http://www.cytheraguides.com/archives/ambrosia_addons/evn/). Currently included:
    * EV Classic: `EVCConText`
    * EV Override: `EVOConText`
    * EV Nova: `NovaConText`
    * Frozen Heart, a popular plugin: `FHConText`
    * Miners, a tiny world useful for testing: `MinersConText`
* __Docs__: Documentation for the EV games' pilot file format, reverse engineered.
* __Progress__: Notebooks for manually tracking one's progress though the core EV games.
* __Scripts__: Scripts to examine the internals of EV games.
    * `fixpicts.pl`: A script to repair the [PICT](https://en.wikipedia.org/wiki/PICT) image files that ConText can extract from an EV game.
    * `nova.pl`: An attempted rewrite of old.pl in more modern perl. Works, but much less functionality.
    * `old.pl`: __You probably want this!__ A script with dozens of commands relevant to EV games. See more below!
* __Tables__: Some simple spreadsheets of spobs (planets) and ships.

# Using old.pl

## Concept: Resources

Escape Velocity (and its plugins) are implemented using old MacOS [resource forks](https://en.wikipedia.org/wiki/Resource_fork). The game's data consists of resources of various types, eg: `weap` for weapons or `spob` for planets. Resources are identified by their four-character type, and their ID (starting from 128). Resources all have a Name, but Names may not be unique.

Within old.pl, each resource can be thought of as a dictionary of key-value pairs, where the keys are preset for a given resource type.

To understand what's in each resource, consider reading the [Nova Bible](https://andrews05.github.io/evstuff/#guides).

## Concept: Identifying resources

Many commands take parameters which identify resources. In most cases, you can pass in one of:

* A numeric ID, to match an exact resource, or
* A string, which will match resources whose name contains that string, or 
* A `/regex/`, which will match against resource names

Note all matching is case-insensitive.

Some commands may also take a small perl program to be evaluated, eg: `$_->{Armor} == 100` would match ships with 100 armor.

## Commands

There's a lot of tools available in old.pl! Some examples are given here, but see also the `help` command for a full list. Many commands come with extra options, which you can find by running `help COMMAND`, or by looking in `cli.pl`.

Generic tools for listing/finding resources with given properties:
* `list ship Carrier` lists all ships whose name contains "Carrier"
* `dump ship 128` dumps the keys/values of ship ID 128
* `dumps ship /WType/ Fighter` dumps all the weapon-type fields of all ships whose name contains "Fighter"
* `find misn AvailStel 128` to find missions available at planet 128
* `rank ship Armor` prints all ships ranked by amount of armor
* `map ship Armor` prints the armor of each ship, in ID order
* `diff ship 128 129` shows differences between two ship resources 

Ranking and examining ships, by various properties:
* `mass 128`: Show what outfits are using up the space on a ship
* `mymass PILOTFILE`: Show what outfits a pilot has, and the space they use
* `masstable`: Rank ships by how much space they have for outfits
* `defense`: Rank ships by defensive shields and armor
* `agility`: Rank ships by how well they maneuver
* `shiptech`: Group ships by tech-level, which controls where in the galaxy they're sold
* `capture --pilot PILOTFILE Lazira`: Show the odds of capturing a Lazira ship, given the ship currently being piloted
* `dude 128`: Identify which ship types may show up when a mission specifies a ship of dude-type 128
* `shieldre RESOURCEFILE`: For pre-Nova games, show how fast shields will regenerate
* `guns`: Show how many guns each ship supports
* `strength`: Rate ships by heuristic strength

Classifying outfits that can be bought:
* `persistent`: List outfits that stay with you when you buy a new ship
* `cantsell`: List outfits that can't be sold, once bought
* `outftech`: Classify outfiles by tech-level
* `sellable PILOTFILE`: Show which outfits of the current pilot can be sold, and how much money will be recovered
* `dps`: Rank weapon outfits by damage-per-second

Finding missions and their effects:
* `misn -v 128`: Shows detailed info on the mission, including where to find it, what requirements must be met for it to show up, what tasks it involves, and what flavour text it uses. __Consider running with --secret, to not reveal spoilers.__
* `pers`: List all missions that can be started by contacting a special ship, rather than landing on a planet
* `limit`: List important missions with aggressive time limits
* `bit 100`: Display every mission or other resource that uses bit number 100. EV uses these numbered bits to allow the universe to change over time, and track the pilot's progress through missions.
* `avail PILOTFILE`: Show all available missions, and where to find them. Super useful if you can't figure out what your next step might be! This command has many options to filter the missions, or change how they're presented.
* `avail --unique --secret --random`: Show where to get one randomly-selected important mission, but hide all other spoilers.

Navigating the galaxy:
* `spobsyst Earth`: Show what system contains the planet ("spob") Earth
* `dist Earth Huron`: Show the fastest path from Earth to Huron
* `placedist spob Earth govt Voinian`: Show the fastest path between categories of planets, in this case Earth to any planet governed by the Voinians.
* `spobtech --outfit 20`: Show where to buy outfits of tech-level 20
* `closetech Sol 20`: Show the closes place to buy outfits of tech-level 20
* `closeoutf --syst Sol "Needle Missile"`: Show the closest places to Sol where you can buy the Needle Missile outfit
* `where "UE Fighter"`: Show which systems are most likely to have UE Fighter ships in them
* `wheregovt Renegade`: Show which systems are most likely to have renegade ships in them
* `hiddenspobs`: Show planets that don't have a navigation preset, such as wormholes

Improving one's legal record with a government:
* `records`: Print the names of legal records
* `legal PILOTFILE Sol`: Show the current numeric legal record in Sol
* `legalgovt PILOTFILE Voinian`: Show what systems the Voinians like me in the most, to help find where to attempt to gain their favour
* `suckup Voinian`: Show what missions will curry the most favour with the Voinians

Trading:
* `comm Earth`: Show the commodities sold by Earth, and their price levels
* `junk`: List the unique tradeable items, and where they're bought/sold
* `trade`: Search for the best trade routes

Finding special "pers" ships:
* `killable`: List all special ships that can be killed
* `systpers PILOTFILE Sol`: List the special ships that could appear in the Sol system
* `wherepers PILOTFILE 128`: List systems where special ship 128 is most likely to be found

Reading flavour text:
* `desc spob,bar 128`: Show the descriptions for planet 128, and its bar
* `grep raider`: Show any descriptions that contain the string "raider"

Reading and writing pilot files, aka cheating. Note that after changing a pilot file, you must re-open it in EV for changes to take effect!
* `pilot PILOTFILE`: Dump all know fields from the pilot file
* `pilot PILOTFILE Missions`: Show just the current missions, and their statuses
* `rating PILOTFILE`: Show the current combat rating
* `revive PILOTFILE 128`: Revive special ship 128, if they've died
* `cash PILOTFILE 1000000`: Give the pilot a million bucks
* `setbits PILOTFILE 100`: Set bit 100 in the current pilot file. Beware that a mission string usually involves a number of bits, setting just one may confuse the game!
* `setoutf PILOTFILE "Blaze Cannon" 3`: Give the pilot three Blaze Cannon outfits
* `setship PILOTFILE Lazira`: Put the pilot in a Lazira ship
* `teleport PILOTFILE Iothe`: Put the pilot in the Iothe system
* `explore PILOTFILE Iothe`: Make Iothe show on the map as explored
* `escort PILOTFILE "UE Fighter" 3`: Give the pilot 3 fighter escorts
* `setrating PILOTFILE 42`: Give the pilot a combat rating of 42
* `setrecord PILOTFILE 42 Sol`: Give the pilot a legal record of 42 in the Sol system

Misc:
* `crons`: Show news items that can occur
* `dominate`: Show which planets are hardest/easiest to dominate

## Technical details and troubleshooting

### Handling files with resource forks

These scripts operate mostly on ConText files, but a few commands must use old-style resource fork data. This is especially true for pilot files!

There's a few approaches to using this data on modern systems:
* On a Mac, you might still have resource forks. If they're there, these scripts can see them.
* Sometimes, resource forks will be exposed as a file in a special directory. For example, on export from the Basilisk II emulator, a file Foo will have its resource fork in .rsrc/Foo, which you can pass to these scripts.
* Some programs encode files in [MacBinary](https://en.wikipedia.org/wiki/MacBinary) format. For example, Netatalk will create a file ._Foo, which you can just pass to these scripts.
* You can also use the `macunpack` command from the `macutils` package to extract resource forks from MacBinary files.

### Resource type names

Apple reserves all ASCII resource types, so programs like Escape Velocity have to choose weird names with extended MacRoman characters. For example, weapons don't really have the type `weap`, but instead `weäp`. These scripts should allow you to just specify the ASCII equivalents.

### Version differences

Most of the time, EV Nova and ConText are fully backwards compatible with previous EV games. But not always, so be careful not to expect exact numbers.

For example:
* Ship `Strength` didn't exist in pre-Nova, so the values may not make sense for earlier games.
* Shield recharge rates worked very differently in pre-Nova, see the `shieldre` command.
