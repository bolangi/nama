
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
sub adjusted_time {  # for marks within current edit
	my $mark = shift;
	return $mark->time unless $::offset_run_flag;
	my $time = $mark->time - ::play_start_time();
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
	return $mark->time;
}
sub mark_time {
	my $tag = shift;
	my $time = unadjusted_mark_time($tag);
	return unless defined $time;
	$time -= ::play_start_time() if ::edit_mode();
	$time
}



# ---------- Mark and jump routines --------
{
package ::;
use Modern::Perl;
our (
	$debug,
	$debug2,
	$ui,
	$this_mark,
	$unit,
	$length,
	$jack_running,
	$seek_delay,
	$markers_armed,
);


sub drop_mark {
	$debug2 and print "drop_mark()\n";
	my $name = shift;
	my $here = eval_iam("getpos");

	if( my $mark = $::Mark::by_name{$name}){
		say "$name: a mark with this name exists already at: ", 
			colonize($mark->time);
		return
	}
	if( my ($mark) = grep { $_->time == $here} ::Mark::all()){
		say q(This position is already marked by "),$mark->name,q(");
		 return 
	}

	my $mark = ::Mark->new( time => $here, 
							name => $name);

	$ui->marker($mark); # for GUI
}
sub mark { # GUI_CODE
	$debug2 and print "mark()\n";
	my $mark = shift;
	my $pos = $mark->time;
	if ($markers_armed){ 
			$ui->destroy_marker($pos);
			$mark->remove;
		    arm_mark_toggle(); # disarm
	}
	else{ 

		set_position($pos);
	}
}

sub next_mark {
	my $jumps = shift;
	$jumps and $jumps--;
	my $here = eval_iam("cs-get-position");
	my @marks = ::Mark::all();
	for my $i ( 0..$#marks ){
		if ($marks[$i]->time - $here > 0.001 ){
			$debug and print "here: $here, future time: ",
			$marks[$i]->time, $/;
			eval_iam("setpos " .  $marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
sub previous_mark {
	my $jumps = shift;
	$jumps and $jumps--;
	my $here = eval_iam("getpos");
	my @marks = ::Mark::all();
	for my $i ( reverse 0..$#marks ){
		if ($marks[$i]->time < $here ){
			eval_iam("setpos " .  $marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
	

## jump recording head position

sub to_start { 
	return if ::ChainSetup::really_recording();
	set_position( 0 );
}
sub to_end { 
	# ten seconds shy of end
	return if ::ChainSetup::really_recording();
	my $end = eval_iam('cs-get-length') - 10 ;  
	set_position( $end);
} 
sub jump {
	return if ::ChainSetup::really_recording();
	my $delta = shift;
	$debug2 and print "&jump\n";
	my $here = eval_iam('getpos');
	$debug and print "delta: $delta\nhere: $here\nunit: $unit\n\n";
	my $new_pos = $here + $delta * $unit;
	$new_pos = $new_pos < $length ? $new_pos : $length - 10;
	set_position( $new_pos );
	sleeper( 0.6) if engine_running();
}
sub set_position {

    return if ::ChainSetup::really_recording(); # don't allow seek while recording

    my $seconds = shift;
    my $coderef = sub{ eval_iam("setpos $seconds") };

    if( $jack_running and eval_iam('engine-status') eq 'running')
			{ engine_stop_seek_start( $coderef ) }
	else 	{ $coderef->() }
	update_clock_display();
}

sub engine_stop_seek_start {
	my $coderef = shift;
	eval_iam('stop');
	$coderef->();
	sleeper($seek_delay);
	eval_iam('start');
}

sub forward {
	my $delta = shift;
	my $here = eval_iam('getpos');
	my $new = $here + $delta;
	set_position( $new );
}

sub rewind {
	my $delta = shift;
	forward( -$delta );
}
	
}	
1;
__END__
