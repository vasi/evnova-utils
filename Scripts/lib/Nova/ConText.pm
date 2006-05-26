# Copyright (c) 2006 Dave Vasilevsky
package Nova::ConText;
use strict;
use warnings;

use base 'Nova::Base';
__PACKAGE__->fields(qw(fh file line_sep type collection));

use Nova::Util qw(printable);
use Nova::ConText::Type;
use Nova::ConText::Resource;
use Nova::ConText::Value;
use Nova::ConText::Resources;

use Data::Dumper;
use English qw($INPUT_RECORD_SEPARATOR);
use Encode;

=head1 NAME

Nova::ConText - parse resources from ConText files

=head1 SYNOPSIS

  my $context = Nova::ConText->new($file);
  my $resources = $context->read;
  $context->write($resources);

=cut

sub init {
	my ($self, $file) = @_;
	$self->file($file);
}

# my @fields = $class->_parseLine($line);
#
# Parse a line into values
sub _parseLine {
	my ($class, $line) = @_;
	my @items = split /\t/, $line;
	my @fields = map { Nova::ConText::Value->fromConText($_) } @items;
	return @fields;
}

# Read a line of input
sub _readLine {
	my ($self) = @_;
	local $INPUT_RECORD_SEPARATOR = $self->line_sep;
	my $fh = $self->fh;
	my $line = <$fh>;
	return $line unless defined $line;
	
	chop $line; # may be \r, so not chomp
	return $line;
}

# Read a type header from a ConText file
sub _readType {
	my ($self, $type) = @_;
	$self->type(Nova::ConText::Type->new($type));
	
	my @vals = $self->_parseLine($self->_readLine);
	my @fields = map { $_->value } @vals;
	pop @fields; # end of record
	
	@fields = $self->type->inFieldNames(@fields);
	$self->collection->addType($type, @fields);
}

# Read a resource from a ConText file. Return true on success.
sub _readResource {
	my ($self, $line) = @_;
	my @vals = $self->_parseLine($line);
	return 0 if $vals[0]->value ne $self->type->type;
	
	pop @vals; # end of record
	my %fields = $self->type->inFields(@vals);
	$self->collection->addResource(\%fields);
	return 1;
}

# Read a Nova::Resources from a ConText file
sub read {
	my ($self) = @_;
	$self->_open_file;
	$self->collection(Nova::ConText::Resources->new($self->file));
	$self->type(undef);
	
	return $self->collection if $self->collection->isFilled;
	while (defined(my $line = $self->_readLine)) {
		if ($line =~ /^\x{2022} Begin (\S{4})$/) { # utf bullet
			$self->_readType($1);
		} elsif (defined $self->type) {
			$self->type(undef) unless $self->_readResource($line);
		}
	}
	
	close $self->fh;
	return $self->collection;
}

# my $fh = $self->_open_file();
#
# Detect the type of file we're reading, and return a filehandle for reading
# it.
sub _open_file {
	my ($self) = @_;
	my $file = $self->file;
	
	open my $guess, '<:bytes', $file or die "Can't open '$file': $!\n";
	local $INPUT_RECORD_SEPARATOR = \1024; # Read a block
	my $block = <$guess>;
	close $guess;
	
	# Use first line-ending
	my ($rs) = ($block =~ /([\r\n])/);
	die "No line-ending found\n" unless defined $rs;
	$self->line_sep($rs);
	
	# Look for letter-umlaut to indicate utf8
	my $enc;
	my $dec = eval { decode_utf8($block, $Encode::FB_CROAK) };
	if (defined $dec && $dec =~ /[\x{e4}\x{eb}\x{ef}\x{f6}\x{fc}\x{ff}]/) {
		$enc = ':utf8';
	} else {
		$enc = ':encoding(MacRoman)'; # assume MacRoman if not unicode
	}
	
	open my $fh, "<$enc", $file or die "Can't open '$file': $!\n";
	$self->fh($fh);
}

# Print a line
sub _writeLine {
	my ($self, @vals) = @_;
	my $fh = $self->fh;
	printf $fh "%s\r", join "\t", map { $_->toConText } @vals;
}

# Write a single type to a ConText file
sub _writeType {
	my ($self, $type) = @_;
	my @ris = $self->collection->type($type);
	return unless @ris;
	
	# Header
	my $fh = $self->fh;
	print $fh "\x{2022} Begin $type\r";
	
	# Field names
	my $typeObj = Nova::ConText::Type->new($type);
	my @fields = $ris[0]->fieldNames;	# $ris[0] must exist since we checked
	@fields = $typeObj->outFieldNames(@fields);
	push @fields, 'EOR';
	@fields = map { Nova::ConText::Value::String->new($_) } @fields;
	$self->_writeLine(@fields);
	
	# Resources
	for my $r (@ris) {
		my %fields;
		eval { %fields = $r->typedFieldHash };
		if ($@) {				# Try to figure out the values heuristically
			%fields = $r->fieldHash;
			for my $k (keys %fields) {
				$fields{$k} = Nova::ConText::Value->fromScalar($fields{$k});
			}
		}
		
		my @vals = $typeObj->outFields(%fields);
		push @vals, Nova::ConText::Value::String->new("\x{2022}");
		
		# ResStore requires that the initial res-type not have quotes
		$vals[0] = Nova::ConText::Value->new($vals[0]->value);
		$self->_writeLine(@vals);
	}
}

# Write a Nova::Resources to a ConText file
sub write {
	my ($self, $rs) = @_;
	$self->collection($rs);
	
	my $file = $self->file;
	open my $fh, '>:encoding(MacRoman)', $file
		or die "Can't open '$file': $!\n";
	$self->fh($fh);
	
	for my $type ($rs->types) {
		$self->_writeType($type);
	}
	
	print $fh "\x{2022} End Output\r";
	close $fh;
}

# Characters that are non-ASCII, but are ok to print
our %OK_CHARS = map { $_ => 1 } split //,
	"\x{e4}\x{eb}\x{ef}\x{f6}\x{fc}\x{ff}" .	# aeiouy with diaresis
	"\x{dc}" .									# U with diaresis
	"\x{e9}" .									# e with acute accent
	"\x{e7}\x{c7}" .							# cC with cedilla
	"\x{e0}\x{e8}" .							# ae with grave accent
	"\x{0}\x{1}\x{3}\x{4}";						# control chars? wtf?

sub _checkNonprintables {
	my ($self, $field, $verb) = @_;
	my $p = printable($field);
	print "$p\n\n" if $verb && $p ne $field;
	
	my @chars = split //, $p;
	my @bad = grep { !$OK_CHARS{$_} && (ord($_) < 32 || ord($_) > 127) }
		@chars;
	if (@bad) {
		print "Line: $.\n\n$p\n\n", Dumper($p), "\n";
		if ($verb) {
			for my $l (\@chars, \@bad) {
				print join(',', map { sprintf("%x", ord($_)) } @$l), "\n";
			}
		}
		exit 0;
	}
}

# Find bad characters
sub findNonprintables {
	my $self = shift;
	
	if (ref($self)) {	# Called as object method
		my ($verb) = @_;
		printf "********** %s *********\n\n", $self->file if $verb;
		$self->_open_file;
		while (defined (my $line = $self->_readLine)) {
			next unless $line =~ /\t/;	# non-robust way to restrict to data
			my @fields = split /\t/, $line;
			pop @fields;
			$self->_checkNonprintables($_, $verb) for @fields;
		}
		close $self->fh;
	} else {			# Called as a class method
		my ($verb, @files) = @_;
		for my $f (@files) {
			my $ct = $self->new($f);
			$ct->findNonprintables($verb);
		}
	}
}

1;
