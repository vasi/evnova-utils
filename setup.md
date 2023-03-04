To get nova.pl and old.pl working on Ubuntu 22.04 Jammy, install:

libyaml-syck-perl libmldbm-perl libberkelydb-perl libdate-manip-perl libterm-readkey-perl libperlio-eol-perl

Use tools from the macutils package to handle resource files, eg: `macunpack -3f Pilot.bin` should give you a Pilot.rsrc file. You don't always need resource files though, mostly for pilot manipulation.

Finally cd into Scripts, and run:

```
./old.pl setcontext $PWD/../Context/EVOContext.txt
./old.pl help
```
