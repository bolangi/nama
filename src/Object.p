package ::Object;
use Modern::Perl;
use Carp;
use ::Assign qw(json_out); 
use Storable qw(dclone);
use Data::Dumper::Concise;

no strict; # Enable during dev and testing
BEGIN {
	require 5.004;
	$::Object::VERSION = '1.04';
}

sub import {
	return unless shift eq '::Object';
	my $pkg   = caller;
	my $child = 0+@{"${pkg}::ISA"};
	eval join '',
		"package $pkg;\n",
		' use vars qw(%_is_field);   ',
		' map{ $_is_field{$_}++ } @_;',
		($child ? () : "\@${pkg}::ISA = ::Object;\n"),
		map {
			defined and ! ref and /^[^\W\d]\w*$/s
			or die "Invalid accessor name '$_'";
			"sub $_ { \$_[0]->{$_} }"
		} @_;
	die "Failed to generate $pkg" if $@;
	return 1;
}

sub new {
	my $class = shift;
	bless { @_ }, $class;
}

sub is_legal_key { 

	# The behavior I want here is:
	#
	# Example class hierachy: ::Object, ::Wav, ::Track, ::SimpleTrack
	
	# By inheriting from Track, SimpleTrack gets all the
	# attributes of Track and Wav, without having to include
	# them in the Track class definition
	
	my ($class, $key) = @_;
	$class = ref $class if ref $class;  # support objects
	return 1 if ${"$class\::_is_field"}{$key};
	my ($parent_class) = @{"$class\::ISA"};

	return unless $parent_class and $parent_class !~ /Object::Tiny/;

	# this should be:
	# return unless $parent_class and $parent_class !~ /Object/;
	
	is_legal_key($parent_class,$key);
}
sub set {
	my $self = shift;
	my $class = ref $self;
	#print "class: $class, args: @_\n";
 	croak "odd number of arguments ",join "\n--\n" ,@_ if @_ % 2;
	my %new_vals = @_;
	map{ 
		$self->{$_} = $new_vals{$_} ;
			my $key = $_;
			is_legal_key(ref $self, $key) or croak "illegal key: $_ for object of type ", ref $self;
	} keys %new_vals;
}
sub dumpp  {
	my $self = shift;
	print $self->dump
}
sub dump {
	my $self = shift;
	my $output = Dumper($self);
	return $output;
}
sub as_hash {
	my $self = shift;
	my $class = ref $self;
	bless $self, 'HASH'; # easy magic
	my $guts = dclone $self; 
	bless $self, $class; # restore
	$guts->{class} = $class if $self->is_legal_key('class');
	return \%guts;
}

1;

__END__

=pod

=head1 NAME

::Object - Class builder

=head1 SYNOPSIS

  # Define a class
  package Foo;
  
  use ::Object qw{ bux baz };
  
  1;
  
  
  # Use the class
  my $object = Foo->new( bux => 1 );

  $object->set( bux => 2);
  
  print "bux is " . $object->bux . "\n";


  # Define a subclass (automatically inherits parent attributes)

  package Bar;

  our @ISA = 'Foo';

  my $lonely_bar = Bar->new();
  
  $lonely_bar->set(bux => 3); 


