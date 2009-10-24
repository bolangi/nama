package Audio::Nama::Data::Rmap;
our $VERSION = 0.62;

=head1 NAME

Data::Rmap - recursive map, apply a block to a data structure

=head1 SYNOPSIS

 $ perl -MData::Rmap -e 'print rmap { $_ } 1, [2,3], \\4, "\n"'
 1234

 $ perl -MData::Rmap=:all
 rmap_all { print (ref($_) || "?") ,"\n" } \@array, \%hash, \*glob;

 # OUTPUT (Note: a GLOB always has a SCALAR, hence the last two items)
 # ARRAY
 # HASH
 # GLOB
 # SCALAR
 # ?


 # Upper-case your leaves in-place
 $array = [ "a", "b", "c" ];
 $hash  = { key => "a value" };
 rmap { $_ = uc $_; } $array, $hash;

 use Data::Dumper; $Data::Dumper::Terse=1; $Data::Dumper::Indent=0;
 print Dumper($array), " ", Dumper($hash), "\n";

 # OUTPUT
 # ['A','B','C'] {'key' => 'A VALUE'}


 # Simple array dumper.  
 # Uses $self->recurse method to alter traversal order 
 ($dump) = rmap_to {

    return "'$_'" unless ref($_); # scalars are quoted and returned

    my $self = shift;
    # use $self->recurse to grab results and wrap them
    return '[ ' . join(', ', $self->recurse() ) . ' ]';

  } ARRAY|VALUE,  [ 1, [ 2, [ [ 3 ], 4 ] ], 5 ];  

 print "$dump\n";
 # OUTPUT
 # [ '1', [ '2', [ [ '3' ], '4' ] ], '5' ]


=head1 DESCRIPTION

 rmap BLOCK LIST

Recursively evaluate a BLOCK over a list of data structures 
(locally setting $_ to each element) and return the list composed
of the results of such evaluations.  $_ can be used to modify
the elements.

Data::Rmap currently traverses HASH, ARRAY, SCALAR and GLOB reference
types and ignores others.  Depending on which rmap_* wrapper is used,
the BLOCK is called for only scalar values, arrays, hashes, references, 
all elements or a customizable combination.

The list of data structures is traversed pre-order in a depth-first fashion.
That is, the BLOCK is called for the container reference before is it called
for it's elements (although see "recurse" below for post-order).
The values of a hash are traversed in the usual "values" order which
may affect some applications.

If the "cut" subroutine is called in the BLOCK then the traversal
stops for that branch, say if you "cut" an array then the code is
never called for it's elements (or their sub-elements).
To simultaneously return values and cut, simply pass the return list
to cut:  C<cut('add','to','returned');>

The first parameter to the BLOCK is an object which maintains the
state of the traversal.  Methods available on this object are 
described in L<State Object> below.

=head1 EXPORTS

By default:

 rmap, rmap_all, cut

Optionally:

 rmap_scalar rmap_hash rmap_array rmap_ref rmap_to
 :types => [ qw(NONE VALUE HASH ARRAY SCALAR REF OBJECT ALL) ],
 :all => ... # everything

=head1 Functions

The various names are just wrappers which select when to call
the code BLOCK.  rmap_all always calls it, the others are more
selective while rmap_to takes an extra parameter permitting you
to provide selection criteria.  Furthermore, you can always
just rmap_all and skip nodes which are not of interest.

=over 4 

=item rmap_to { ... } $want, @data_structures;

Most general first.

Recurse the @data_structures and apply the BLOCK to 
elements selected by $want.  The $want parameter is the
bitwise "or" of whatever types you choose (imported with :types):

 VALUE  - non-reference scalar, eg. 1
 HASH   - hash reference
 ARRAY  - array reference
 SCALAR - scalar refernce, eg. \1
 REF    - higher-level reference, eg. \\1, \\{}
          B<NOT> any reference type, see <Scalar::Util>'s reftype:
          perl -MScalar::Util=reftype -le 'print map reftype($_), \1, \\1'
 GLOB   - glob reference, eg. \*x  
          (scalar, hash and array recursed)
 ALL    - all of the above
 NONE   - none of the above

So to call the block for arrays and scalar values do:

 use Data::Rmap ':all';         # or qw(:types rmap_to)
 rmap { ... } ARRAY|VALUE, @data_structures;

(ALL & !GLOB) might also be handy.

The remainder of the wrappers are given in terms of the $want for rmap_to.

=item rmap { ... } @list;

Recurse and call the BLOCK on non-reference scalar values.  $want = VALUE

=item rmap_all BLOCK LIST

Recurse and call the BLOCK on everything.  $want = ALL

=item rmap_scalar { ... }  @list

Recurse and call the BLOCK on non-collection scalars.  
$want = VALUE|SCALAR|REF

=item rmap_hash 

Recurse and call the BLOCK on hash refs.  $want = HASH

=item rmap_array 

Recurse and call the BLOCK on array refs.  $want = ARRAY

=item rmap_ref 

Recurse and call the BLOCK on all references (not GLOBS).  
$want = HASH|ARRAY|SCALAR|REF

Note: rmap_ref isn't the same as rmap_to {} REF

=item cut(@list)

Don't traverse sub-elements and return the @list immediately.
For example, if $_ is an ARRAY reference, then the array's elements 
are not traversed.  

If there's two paths to an element, both will need to be cut.

=back

=head1 State Object

The first parameter to the BLOCK is an object which maintains
most of the traversal state (except current node, which is $_).
I<You will ignore it most of the time>.
The "recurse" method may be useful.  
Other methods should only be used in throw away tools, see L<TODO>

Methods:

=over 4

=item recurse

Process child nodes of $_ now and return the result.

This makes it easier to perform post-order and in-order
processing of a structure.  Note that since the same "seen list"
is used, the child nodes aren't reprocessed.

=item code

The code reference of the BLOCK itself.  Possible useful in
some situations.

=item seen

(Warning: I'm undecided whether this method should be public)

Reference to the HASH used to track where we have visited.
You may want to modify it in some situations (though I haven't yet).
Beware circular references.  The (current) convention used for the key
is in the source.

=item want

(Warning: I'm undecided whether this method should be public)

The $want state described in L<rmap_to>.

=back

=head1 EXAMPLES

 # command-line play
 $ perl -MData::Rmap -le 'print join ":", rmap { $_ } 1,2,[3..5],\\6'
 1:2:3:4:5:6


 # Linearly number questions on a set of pages
 my $qnum = 1;
 rmap_hash {
     $_->{qnum} = $qnum++ if($_->{qn});
 } @pages;


 # Grep recursively, finding ALL objects
 use Scalar::Util qw(blessed);
 my @objects = rmap_ref {
     blessed($_) ? $_ : ();
 } $data_structure;


 # Grep recursively, finding public objects (note the cut)
 use Scalar::Util qw(blessed);
 my @objects = rmap_ref {
     blessed($_) ?  cut($_) : ();
 } $data_structure;


 # Return a modified structure
 # (result flattening means we must cheat by cloning then modifying)
 use Storable qw(dclone);
 use Lingua::EN::Numbers::Easy;

 $words = [ 1, \2, { key => 3 } ];
 $nums = dclone $words;
 rmap { $_ = $N{$_} || $_ } $nums; 


 # Make an assertion about a structure
 use Data::Dump;
 rmap_ref {
    blessed($_) && $_->isa('Question') && defined($_->name)
        or die "Question doesn't have a name:", dump($_);
 } @pages;


 # Traverse a tree using localize state
 $tree = [
     one =>
     two =>
     [   
         three_one =>
         three_two =>
         [   
             three_three_one =>
         ],
         three_four =>
     ],
     four =>
     [   
         [   
             five_one_one =>
         ],
     ],
 ];

 @path = ('q');
 rmap_to {
     if(ref $_) {
         local(@path) = (@path, 1); # ARRAY adds a new level to the path
         $_[0]->recurse(); # does stuff within local(@path)'s scope
     } else {
         print join('.', @path), " = $_ \n"; # show the scalar's path
     }
     $path[-1]++; # bump last element (even when it was an aref)
 } ARRAY|VALUE, $tree;

 # OUTPUT
 # q.1 = one 
 # q.2 = two 
 # q.3.1 = three_one 
 # q.3.2 = three_two 
 # q.3.3.1 = three_three_one 
 # q.3.4 = three_four 
 # q.4 = four 
 # q.5.1.1 = five_one_one 

=head1 Troubleshooting 

Beware comma after block:

 rmap { print }, 1..3;
               ^-------- bad news, you get and empty list:
 rmap(sub { print $_; }), 1..3;

If you don't import a function, perl's confusion may produce:

 $ perl -MData::Rmap -le 'rmap_scalar { print } 1'
 Can't call method "rmap_scalar" without a package or object reference...

 $ perl -MData::Rmap -le 'rmap_scalar { $_++ } 1'
 Can't call method "rmap_scalar" without a package or object reference...

If there's two paths to an element, both will need to be cut.

If there's two paths to an element, one will be taken randomly when
there is an intervening hash.

Autovivification can lead to "Deep recursion" warnings if you test
C<exists $_->{this}{that}> instead of 
C<exists $_->{this} && exists $_->{this}{that}>
as you may follow a long chain of "this"s


=head1 TODO

put for @_ iin wrapper to allow parameters in a different wrapper,
solve localizing problem.

Note that the package/class name of the L<State Object>
is subject to change.

The want and seen accessors may change or become useful
dynamic mutators.

Store custom localized data about the traversal.
Seems too difficult and ugly when compare to doing it at the call site.
Should support multiple reentrancy so avoid the symbol table.

C<rmap_args { } $data_structure, @args> form to pass parameters.
Could potentially help localizing needs.  (Maybe only recurse last item)

Benchmark.  Use array based object and/or direct access internally.

rmap_objects shortcut for Scalar::Utils::blessed
(Let me know of other useful rmap_??? wrappers)

Think about permitting different callback for different types.
The prototype syntax is a bit too flaky....

Ensure that no memory leaks are possible, leaking the closure.

Read http://www.cs.vu.nl/boilerplate/

=head1 SEE ALSO

map, grep, L<Storable>'s dclone, L<Scalar::Util>'s reftype and blessed

Faint traces of treemap:

 http://www.perlmonks.org/index.pl?node_id=60829

=head1 AUTHOR

Brad Bowman E<lt>rmap@bereft.netE<gt>

=head1 LICENCE AND COPYRIGHT
       
Copyright (c) 2004-2008 Brad Bowman (E<lt>rmap@bereft.netE<gt>). 
All rights reserved.
       
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. 
See L<perlartistic> and L<perlgpl>.
       
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut

# Early design discussion:
# http://www.perlmonks.org/index.pl?node_id=295642
# wantarray
# http://www.class-dbi.com/cgi-bin/wiki/index.cgi?AtomicUpdates

use warnings;
use strict;
use Carp qw(croak);
use Scalar::Util qw(blessed refaddr reftype);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(rmap rmap_all cut);
our %EXPORT_TAGS = (
	types => [ qw(NONE VALUE HASH ARRAY SCALAR REF GLOB ALL) ],
);
our @EXPORT_OK = ( qw(rmap_scalar rmap_hash rmap_array rmap_ref rmap_to),
				@{ $EXPORT_TAGS{types} } );

$EXPORT_TAGS{all} = [ @EXPORT, @EXPORT_OK ];


# Uses stringifying instead of S::U::ref* b/c it's under control
my $cut = \do { my $thing }; # my = out of symbol table
sub cut { 
	die $cut = [@_]; # cut can return
} 

sub NONE()   { 0 }
sub VALUE()  { 1 }
sub HASH()   { 2 }
sub ARRAY()  { 4 }
sub SCALAR() { 8 }
sub REF()    { 16 }
sub GLOB()   { 32 }
sub ALL()    { VALUE|HASH|ARRAY|SCALAR|REF|GLOB }
# Others like CODE, Regex, etc are ignored

my %type_bits = (
	HASH => HASH,
	ARRAY => ARRAY,
	SCALAR => SCALAR,
	REF => REF,
	GLOB => GLOB,
	# reftype actually returns undef for:
	VALUE => VALUE,
);

sub new {
	bless { code => $_[1], want => $_[2], seen => $_[3] }, $_[0];
}
sub code { $_[0]->{code} }
sub want { $_[0]->{want} }
sub seen { $_[0]->{seen} }
sub call { $_[0]->{code}->($_[0]) }

sub recurse { 
	# needs to deref $_ and *then* run the code, enter _recurse directly
	$_[0]->_recurse(); # cut not needed as seen remembers
}

sub rmap (&@) { 
	__PACKAGE__->new(shift, VALUE, {})->_rmap(@_);
}

sub rmap_all (&@) { 
	__PACKAGE__->new(shift, ALL, {})->_rmap(@_);
}

sub rmap_scalar (&@) { 
	__PACKAGE__->new(shift, VALUE|SCALAR|REF, {})->_rmap(@_);
}

sub rmap_hash (&@) { 
	__PACKAGE__->new(shift, HASH, {})->_rmap(@_);
}

sub rmap_array (&@) { 
	__PACKAGE__->new(shift, ARRAY, {})->_rmap(@_);
}

sub rmap_ref (&@) { 
	__PACKAGE__->new(shift, HASH|ARRAY|SCALAR|REF, {})->_rmap(@_);
}

sub rmap_to (&@) {
	__PACKAGE__->new(shift, shift, {})->_rmap(@_);
}

sub _rmap {
	my $self = shift;
	my @return;

	for (@_) { # just one after the wrapper call
		my ($key, $type);

		if($type = reftype($_)) {
			$key = refaddr $_;
			$type = $type_bits{$type} or next;
		} else {
			$key = "V:".refaddr(\$_); # prefix to distinguish from \$_
			$type = VALUE;
		}

		next if ( exists $self->seen->{$key} );
		$self->seen->{$key} = undef; 

		# Call the $code
		if($self->want & $type) {
			my $e; # local($@) and rethrow caused problems
			my @got;
			{
				local ($@); # don't trample, cut impl. should be transparent
				# call in array context.  pass block for reentrancy
				@got = eval { $self->call() };
				$e = $@;
			}

			if($e) {
				if(ref($e) && $e == $cut) {
					push @return, @$cut; # cut can add to return list
					next; # they're cutting, don't recurse
				} else { 
					die $e; 
				}
			}
			push @return, @got;
		}

		push @return, $self->_recurse(); # process $_ node
	}
	return @return;
}

sub _recurse {
	my $self = shift;
	my $type = $type_bits{reftype($_) || 'VALUE'} or return;
	my @return;

	# Recurse appropriately, keeping $_ alias
	if ($type & HASH) {
		push @return, $self->_rmap($_) for values %$_;
	} elsif ($type & ARRAY) {
		# Does this change cut behaviour? No, cut is one scalar ref
		#push @return, _rmap($code, $want, $seen, $_) for @$_;
		push @return, $self->_rmap(@$_);
	} elsif ($type & (SCALAR|REF) ) {
		push @return, $self->_rmap($$_);
	} elsif ($type & GLOB) {
		# SCALAR is always there, undef may be unused or set to undef
		push @return, $self->_rmap(*$_{SCALAR});
		defined *$_{ARRAY} and
			push @return, $self->_rmap(*$_{ARRAY});
		defined *$_{HASH} and
			push @return, $self->_rmap(*$_{HASH});
		# Is it always: *f{GLOB} == \*f ?
		# Also CODE PACKAGE NAME GLOB
	}
	return @return;
}

1;
