
# ----------- Mark ------------
package ::Mark;
<<<<<<< HEAD:Audio-Multitrack/pre/Mark.p
=======
our $VERSION = 1.0;
>>>>>>> v_95:Audio-Multitrack/pre/Mark.p
use Carp;
our @ISA;
use vars qw($n %by_name @all  %used_names);
use ::Object qw( 
				 name 
                 time
				 active
				 );
@all = ();	
%by_name = ();	# return ref to Mark by name
%used_names = (); 

sub new {
	my $class = shift;	
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak  "name already in use: $vals{name}\n"
		 if $used_names{$vals{name}}; # null name returns false
<<<<<<< HEAD:Audio-Multitrack/pre/Mark.p
=======
	
>>>>>>> v_95:Audio-Multitrack/pre/Mark.p
	my $object = bless { 

		## 		defaults ##

					active  => 1,
					name => "",

					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	if ($object->name) {
		$used_names{$vals{name}}++;
		$by_name{ $object->name } = $object;
	}
	push @all, $object;
	$::this_mark = $object;
	
	$object;
	
}

sub set_name {
	my $mark = shift;
	carp("you attempted to futz $mark, which is not a Mark\n"),
		return unless (ref $mark) =~ /Mark/;
	my $name = shift;
	print "name: $name\n";
	if ( defined $by_name{ $name } ){
	carp "you attempted to assign to name already in use\n";
	}
	else {
		$mark->set(name => $name);
		$used_names{$name}++;
		$by_name{ $name } = $mark;
	}
}

sub jump_here {
	my $mark = shift;
	carp("you attempted to futz $mark, which is not a Mark\n"),
		return unless (ref $mark) =~ /Mark/;
	::eval_iam( "setpos " . $mark->time);
	$::this_mark = $mark;
}
sub remove {
	my $mark = shift;
<<<<<<< HEAD:Audio-Multitrack/pre/Mark.p
	carp("you attempted to futz $mark, which is not a Mark\n"),
=======
	carp("you attempted to futz $mark, which is [", ref
	$mark, " ] not a Mark\n"),
>>>>>>> v_95:Audio-Multitrack/pre/Mark.p
		return unless (ref $mark) =~ /Mark/;
	if ( $mark->name ) {
		delete $by_name{$mark->name};
		delete $used_names{$mark->name};
	}
	$::debug and warn "marks found: ",scalar @all, $/;
	# @all = (), return if scalar @all
	@all = grep { $_->time != $mark->time } @all;

}
sub next { 
	my $mark = shift;
	carp("you attempted to futz $mark, which is not a Mark\n"),
		return unless (ref $mark) =~ /Mark/;
	::next_mark();
}
sub previous {
	my $mark = shift; 
	carp("you attempted to futz $mark, which is not a Mark\n"),
		return unless (ref $mark) =~ /Mark/;
	::previous_mark();
}

# -- Class Methods

sub all { sort { $a->time <=> $b->time }@all }

sub loop_start { 
<<<<<<< HEAD:Audio-Multitrack/pre/Mark.p
	my @points =sort { $a->time <=> $b->time } 
	grep{ $_ } 	map{ mark_object($_)} @::loop_endpoints[0,1];
=======
	my @points = sort { $a <=> $b } 
	grep{ $_ } map{ mark_time($_)} @::loop_endpoints[0,1];
	#print "points @points\n";
>>>>>>> v_95:Audio-Multitrack/pre/Mark.p
	$points[0];
}
sub loop_end {
<<<<<<< HEAD:Audio-Multitrack/pre/Mark.p
	my @points =sort { $a->time <=> $b->time } 
		grep{ $_ } map{ mark_object($_)} @::loop_endpoints[0,1];
=======
	my @points =sort { $a <=> $b } 
		grep{ $_ } map{ mark_time($_)} @::loop_endpoints[0,1];
>>>>>>> v_95:Audio-Multitrack/pre/Mark.p
	$points[1];
}
<<<<<<< HEAD:Audio-Multitrack/pre/Mark.p
sub mark_object {
=======
sub mark_time {
>>>>>>> v_95:Audio-Multitrack/pre/Mark.p
	my $tag = shift;
<<<<<<< HEAD:Audio-Multitrack/pre/Mark.p
	my @marks = ::Mark::all();
=======
	$tag or $tag = '';
	#print "tag: $tag\n";
>>>>>>> v_95:Audio-Multitrack/pre/Mark.p
	my $mark;
<<<<<<< HEAD:Audio-Multitrack/pre/Mark.p
	if ($tag =~ /\d+/){
		$mark = $marks[$tag];
=======
	if ($tag =~ /\./) { # we assume raw time if decimal
		#print "mark time: ", $tag, $/;
		return $tag;
	} elsif ($tag =~ /^\d+$/){
		#print "mark index found\n";
		$mark = $::Mark::all[$tag];
>>>>>>> v_95:Audio-Multitrack/pre/Mark.p
	} else {
<<<<<<< HEAD:Audio-Multitrack/pre/Mark.p
=======
		#print "mark name found\n";
>>>>>>> v_95:Audio-Multitrack/pre/Mark.p
		$mark = $::Mark::by_name{$tag};
	}
<<<<<<< HEAD:Audio-Multitrack/pre/Mark.p
	$mark if defined $mark; 
=======
	return undef if ! defined $mark;
	#print "mark time: ", $mark->time, $/;
	return $mark->time;
		
>>>>>>> v_95:Audio-Multitrack/pre/Mark.p
}

	
1;

