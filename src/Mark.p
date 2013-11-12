
# ----------- Mark ------------

package ::Mark;
our $VERSION = 1.0;
use Carp;
use warnings;
no warnings qw(uninitialized);
our @ISA;
use vars qw($n %by_name @all);
use ::Log qw(logpkg);
use ::Globals qw(:all);
use ::Object qw( 
				 name 
                 time
				 active
				 );

sub initialize {
	map{ $_->remove} ::Mark::all();
	@all = ();	
	%by_name = ();	# return ref to Mark by name
	$by_name{Here} = bless {}, '::HereMark';
	@::marks_data = (); # for save/restore
}
sub next_sequence {
	$project->{mark_sequence_counter} ||= '0000';
	$project->{mark_sequence_counter}++
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
	::set_position($mark->time);
	$::this_mark = $mark;
}
sub shifted_time {  # for marks within current edit
	my $mark = shift;
	return $mark->time unless $mode->{offset_run};
	my $time = $mark->time - ::play_start_time();
	$time > 0 ? $time : 0
}
sub remove {
	my $mark = shift;
	::throw('Fades depend on this mark. Remove failed.'), return	
		if ::fade_uses_mark($mark->name);
	if ( $mark->name ) {
		delete $by_name{$mark->name};
	}
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
	grep{ $_ } map{ mark_time($_)} @{$setup->{loop_endpoints}}[0,1];
	#print "points @points\n";
	$points[0];
}
sub loop_end {
	my @points =sort { $a <=> $b } 
		grep{ $_ } map{ mark_time($_)} @{$setup->{loop_endpoints}}[0,1];
	$points[1];
}
sub unshifted_mark_time {
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
	my $time = unshifted_mark_time($tag);
	return unless defined $time;
	$time -= ::play_start_time() if $mode->{offset_run};
	$time
}



# ---------- Mark and jump routines --------
{
package ::;
use Modern::Perl;
use ::Globals qw(:all);

sub drop_mark {
	logsub("&drop_mark");
	my $name = shift;
	my $here = eval_iam("getpos");

	if( my $mark = $::Mark::by_name{$name}){
		pager2("$name: a mark with this name exists already at: ", 
			colonize($mark->time));
		return
	}
	if( my ($mark) = grep { $_->time == $here} ::Mark::all()){
		pager2( q(This position is already marked by "),$mark->name,q(") );
		 return 
	}

	my $mark = ::Mark->new( time => $here, 
							name => $name);

	$ui->marker($mark); # for GUI
}
sub mark { # GUI_CODE
	logsub("&mark");
	my $mark = shift;
	my $pos = $mark->time;
	if ($gui->{_markers_armed}){ 
			$ui->destroy_marker($pos);
			$mark->remove;
		    arm_mark_toggle(); # disarm
	}
	else{ 

		set_position($pos);
	}
}

sub next_mark {
	logsub("&next_mark");
	my $jumps = shift || 0;
	$jumps and $jumps--;
	my $here = eval_iam("cs-get-position");
	my @marks = ::Mark::all();
	for my $i ( 0..$#marks ){
		if ($marks[$i]->time - $here > 0.001 ){
			logpkg('debug', "here: $here, future time: ", $marks[$i]->time);
			set_position($marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
sub previous_mark {
	logsub("&previous_mark");
	my $jumps = shift || 0;
	$jumps and $jumps--;
	my $here = eval_iam("getpos");
	my @marks = ::Mark::all();
	for my $i ( reverse 0..$#marks ){
		if ($marks[$i]->time < $here ){
			set_position($marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
	

## jump recording head position

sub to_start { 
	logsub("&to_start");
	return if ::ChainSetup::really_recording();
	set_position( 0 );
}
sub to_end { 
	logsub("&to_end");
	# ten seconds shy of end
	return if ::ChainSetup::really_recording();
	my $end = eval_iam('cs-get-length') - 10 ;  
	set_position( $end);
} 
sub jump {
	return if ::ChainSetup::really_recording();
	my $delta = shift;
	logsub("&jump");
	my $here = eval_iam('getpos');
	logpkg('debug', "delta: $delta, here: $here, unit: $gui->{_seek_unit}");
	my $new_pos = $here + $delta * $gui->{_seek_unit};
	if ( $setup->{audio_length} )
	{
		$new_pos = $new_pos < $setup->{audio_length} 
			? $new_pos 
			: $setup->{audio_length} - 10
	}
	
	set_position( $new_pos );
	sleeper( 0.6) if engine_running();
}
sub set_position {
	logsub("&set_position");

    return if ::ChainSetup::really_recording(); # don't allow seek while recording

    my $seconds = shift;
    my $coderef = sub{ eval_iam("setpos $seconds") };

	$jack->{jackd_running} 
		?  ::stop_do_start( $coderef, $engine->{jack_seek_delay} )
		:  $coderef->();

	update_clock_display();
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
sub jump_forward {
	my $multiplier = shift;
	forward( $multiplier * $text->{hotkey_playback_jumpsize})
	}
sub jump_backward { jump_forward( - shift()) }

	
} # end package
{ package ::HereMark;
our @ISA = ::Mark;
our $last_time;
sub name { 'Here' }
sub time { ::eval_iam('cs-connected') ? ($last_time = ::eval_iam('getpos')) : $last_time } 
}


1;
__END__
