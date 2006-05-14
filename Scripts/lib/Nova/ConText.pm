# Copyright (c) 2006 Dave Vasilevsky
package Nova::ConText;
use strict;
use warnings;

use base 'Nova::Base';

use Nova::ConText::Type;

use English qw($INPUT_RECORD_SEPARATOR);

use utf8;	# Inline utf8 characters
use Encode;

=head1 NAME

Nova::ConText - parse resources from ConText files

=head1 SYNOPSIS

  my $context = Nova::ConText->new($file);
  my @resources = $context->read;

=head1 DESCRIPTION

Reads ConText files, producing Nova::Resource objects. Can accept either Mac
or Unix line endings, as well as either MacRoman or UTF-8 encoding.

=head1 METHODS

=over 4

=item new

  my $context = Nova::ConText->new($file);

Construct a new ConText object, which will extract resource descriptions from
the given file.

=cut

sub _init {
	my ($self, $file) = @_;
	$self->{file} = $file;
}


sub getline {
	my ($self, $fh) = @_;
	local $INPUT_RECORD_SEPARATOR = $self->{rs};
	my $line = <$fh>;
	return $line unless defined $line;
	
	chop $line; # may be \r, so not chomp
	return $line;
}

=item read

  my @resources = $context->read;

Return a list of Resource objects read from the given file.

=cut

sub read {
	my ($self) = @_;
	my $file = $self->{file};
	my (@resources, %headers);
	
	my $enc;
	($self->{rs}, $enc) = $self->_file_type($file);
	open my $fh, "<:$enc", $file or die "Can't open '$file': $!\n";
	
	my (@types, $type);
	while (defined(my $line = $self->getline($fh))) {
		if ($line =~ /^• Begin (\S{4})$/) {
			$type = Nova::ConText::Type->new($1);
			push @types, $type;
			
			my $headers = $self->getline($fh) or die "No headers!\n";
			$type->readHeaders($headers);
			
		} elsif (defined $type) {
			my $ret = $type->readResource($line);
			undef $type unless defined $ret; # stop when we hit a bad line
		}
	}
	
	close $fh;
	return @types;
}

# my ($recordSeparator, $encoding) = $class->_file_type($file);
#
# Detect the type of file we're reading
sub _file_type {
	my ($class, $file) = @_;
	
	open my $fh, '<:bytes', $file or die "Can't open '$file': $!\n";
	local $INPUT_RECORD_SEPARATOR = \1024; # Read a block
	my $block = <$fh>;
	close $fh;
	
	# Use first line-ending
	my ($rs) = ($block =~ /([\r\n])/);
	die "No line-ending found\n" unless defined $rs;
	
	# Look for letter-umlaut to indicate utf8
	my $enc;
	my $dec = eval { decode_utf8($block, $Encode::FB_CROAK) };
	if (defined $dec && $dec =~ /[äëïöüÿ]/) {
		$enc = ':utf8';
	} else {
		$enc = ':encoding(MacRoman)'; # assume MacRoman if not unicode
	}
	
	return ($rs, $enc);
}

sub dump {

}

=back

=cut

1;
