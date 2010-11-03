
# ----------- Mark ------------
package ::Mark;
our $VERSION = 1.0;
use Carp;
use warnings;
no warnings qw(uninitialized);
our @ISA;
use vars qw($n %by_name @all);
use ::Object qw( 
				 name 
                 time
				 active
				 );

sub initialize {
	map{ $_->remove} ::Mark::all();
	@all = ();	
	%by_name = ();	# return ref to Mark by name
	@::marks_data = (); # for save/restore
}
sub new {
	my $class = shift;	
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;

	# to support set_edit_points, we now allow marks to be overwritten
	#
	#croak  "name already in use: $vals{name}\n"
	#	 if $by_name{$vals{name}}; # null name returns false
	
	my $object = bless { 

		## 		defaults ##

					active  => 1,
					name => "",

					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	if ($object->name) {
		$by_name{ $object->name } = $object;
	}
	push @all, $object;
	$::this_mark = $object;
	
	$object;
	
}

sub set_name {
	my $mark = shift;
	my $name = shift;
	print "name: $name\n";
	if ( defined $by_name{ $name } ){
	carp "you attempted to assign to name already in use\n";
	}
	else {
		$mark->set(name => $name);
		$by_name{ $name } = $mark;
	}
}

sub jump_here {
	my $mark = shift;
	::eval_iam( "setpos " . $mark->time);
	$::this_mark = $mark;
}
{
no warnings 'redefine';
#sub time { $_[0]->adjusted_time }
#sub time { $_[0]->{time} }
}
sub adjusted_time {  # for marks within current edit
	my $mark = shift;
	return $mark->{time} unless ::edit_mode();
	my $time = $mark->{time} - $::this_edit->play_start_mark->{time};
	$time > 0 ? $time : 0
}
sub remove {
	my $mark = shift;
	if ( $mark->name ) {
		delete $by_name{$mark->name};
	}
	$::debug and warn "marks found: ",scalar @all, $/;
	# @all = (), return if scalar @all
	@all = grep { $_->time != $mark->time } @all;

}
sub next { 
	my $mark = shift;
	::next_mark();
}
sub previous {
	my $mark = shift; 
	::previous_mark();
}

# -- Class Methods

sub all { sort { $a->{time} <=> $b->{time} }@all }

sub loop_start { 
	my @points = sort { $a <=> $b } 
	grep{ $_ } map{ mark_time($_)} @::loop_endpoints[0,1];
	#print "points @points\n";
	$points[0];
}
sub loop_end {
	my @points =sort { $a <=> $b } 
		grep{ $_ } map{ mark_time($_)} @::loop_endpoints[0,1];
	$points[1];
}
sub unadjusted_mark_time {
	my $tag = shift;
	$tag or $tag = '';
	#print "tag: $tag\n";
	my $mark;
	if ($tag =~ /\./) { # we assume raw time if decimal
		#print "mark time: ", $tag, $/;
		return $tag;
	} elsif ($tag =~ /^\d+$/){
		#print "mark index found\n";
		$mark = $::Mark::all[$tag];
	} else {
		#print "mark name found\n";
		$mark = $::Mark::by_name{$tag};
	}
	return undef if ! defined $mark;
	#print "mark time: ", $mark->time, $/;
	return $mark->{time};
}
sub mark_time {
	my $tag = shift;
	my $time = unadjusted_mark_time($tag);
	return unless defined $time;
	$time -= ::play_start_time() if ::edit_mode();
	$time
}
sub subtract_edit_start_offset {
	return $_[0] unless ::edit_mode();
	#$_[0] - 
}

	
1;
