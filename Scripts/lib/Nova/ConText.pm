# Copyright (c) 2006 Dave Vasilevsky
package Nova::ConText;
use strict;
use warnings;

use base 'Nova::Base';
Nova::ConText->fields(qw(fh file line_sep type collection));

use Nova::ConText::Type;
use Nova::Resource;
use Nova::Resource::Value;
use Nova::Resources;

use English qw($INPUT_RECORD_SEPARATOR);
use Encode;
use utf8;	# Inline utf8 characters

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
	my @fields = map { Nova::Resource::Value->fromString($_) } @items;
	return @fields;
}

# Read a line of input
sub _readLine {
	my ($self) = @_;
	local $INPUT_RECORD_SEPARATOR = $self->line_sep;
	my $line = <$self->fh>;
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
	$self->_open_file($self->$file);
	$self->collection(Nova::Resources->new($self->file));
	$self->type(undef);
	
	while (defined(my $line = $self->_readLine)) {
		if ($line =~ /^• Begin (\S{4})$/) {
			$self->_readType($1);
		} elsif (defined $self->type) {
			$self->type(undef) unless $self->_readResource($line);
		}
	}
	
	close $self->fh;
	return $self->collection;
}

# my $fh = $self->_open_file($file);
#
# Detect the type of file we're reading, and return a filehandle for reading
# it.
sub _open_file {
	my ($class, $file) = @_;
	
	open my $dec, '<:bytes', $file or die "Can't open '$file': $!\n";
	local $INPUT_RECORD_SEPARATOR = \1024; # Read a block
	my $block = <$dec>;
	close $dec;
	
	# Use first line-ending
	my ($rs) = ($block =~ /([\r\n])/);
	die "No line-ending found\n" unless defined $rs;
	$self->line_sep($rs);
	
	# Look for letter-umlaut to indicate utf8
	my $enc;
	my $dec = eval { decode_utf8($block, $Encode::FB_CROAK) };
	if (defined $dec && $dec =~ /[äëïöüÿ]/) {
		$enc = ':utf8';
	} else {
		$enc = ':encoding(MacRoman)'; # assume MacRoman if not unicode
	}
	
	open my $fh, "<$enc", $file or die "Can't open '$file': $!\n";
	$self->fh($fh);
}

=back

=cut

1;
