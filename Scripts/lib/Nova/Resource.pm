# Copyright (c) 2006 Dave Vasilevsky

package Nova::Resource;
use strict;
use warnings;

use base qw(Nova::Base Exporter);
__PACKAGE__->fields(qw(collection readOnly));

our @EXPORT = qw(flagInfo);

use Nova::Util qw(deaccent);
use Scalar::Util qw(blessed);
use NEXT;

=head1 NAME

Nova::Resource - a resource from a Nova data file

=head1 SYNOPSIS

  # Get a resource from a Nova::Resources object
  my $res = $collection->get($type => $id);
  my $res2 = $res->duplicate($newID);


  # Properties
  my $collection = $res->collection;
  my $isReadOnly = $res->readOnly;
  
  # Get fields by string or by method. Set as well.
  my $value = $res->field("Flags");
  my $value = $res->flags;
  $res->flags(0xBEEF);
  
  # Get info about the fields
  my $bool = $res->hasField($field);
  my $hashref = $res->fieldHash;
  my @fields = $res->fieldNames;


  # Subclasses should implement at least:
  - Constructor
  - _rawField
  - fieldNames

=cut

our %TYPES = (
	(map { $_ => ucfirst $_ }
		qw(cron dude govt junk misn outf pers ship spob syst weap)),
	'STR#'	=> 'StrNum',
);
our %LOADED;

# Should call at *end* of subclass init.
sub init {
	my ($self) = @_;
	
	# Rebless, if necessary
	my $t = deaccent($self->type);
	my $subclass = $TYPES{$t};
	if (defined $subclass) {
		my $class = __PACKAGE__ . "::Type::$subclass";
		unless ($LOADED{$class}++) {
			eval "require $class";
		}
		$self->mixin($class);
	}
	return $self;
}


#### Interface
#
# Get/set the value of a field (without doing the AUTOLOAD messiness)
# sub _rawField { }
#
# Get the field names
# sub fieldNames { }

# Do we have the given field?
sub hasField {
	my ($self, $field) = @_;
	
	# Inefficient default
	return grep { lc $_ eq lc $field } $self->fieldNames;
}

# Get a hash of field names to values. Keys should be in lower-case.
sub fieldHash {
	my ($self) = @_;
	
	# Inefficient default
	my %hash;
	for my $field ($self->fieldNames) {
		$hash{lc $field} = $self->$field;
	}
	return %hash;
}

# Dump a given field's value
sub dumpField {
	my ($self, $field) = @_;
	
	# Imperfect default
	return $self->$field;
}

sub can {
	my ($self, $meth) = @_;
	my $code = $self->caseInsensitiveMethod($meth);
	return $code if defined $code;
	
	# Can't test for field presence without a blessed object!
	return undef unless blessed $self;
	return undef unless $self->hasField($meth);
	return sub {
		my ($self, @args) = @_;
		$self->_rawField($meth, @args);
	};
}

sub AUTOLOAD {
	unshift @_, our $AUTOLOAD;
	goto &Nova::Base::autoloadCan;
}

# Get/set a field
sub field {
	my ($self, $field, $val) = @_;
	return defined $val ? $self->$field($val) : $self->$field;
}

# Create a clone of this resource, at a different ID
sub duplicate {
	my ($self, $id) = @_;
	$id = $self->collection->nextUnused($self->type) unless defined $id;
	
	my %fields = $self->fieldHash;
	$fields{id} = $id;
	return $self->collection->addResource(\%fields);
}


# Load the categories
eval "require Nova::Resource::Category::$_" for qw(Common Fields Formatting);

1;
