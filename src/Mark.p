
# ----------- Mark ------------

package ::Mark;
our $VERSION = 1.0;
use Carp;
use warnings;
no warnings qw(uninitialized);
our($n, %by_name, @all, @attributes, %is_attribute, $AUTOLOAD);
use ::Log qw(logpkg);
use ::Globals qw(:all);
use ::Object qw( 
				 name 
                 time
				 attrib
				 );
# attrib is a hash reference

sub initialize {
	map{ $_->remove} ::Mark::all();
	@all = ();	
	%by_name = ();	# return ref to Mark by name
	$by_name{Here} = bless {}, '::HereMark';
	@::marks_data = (); # for save/restore
}
sub next_id { # returns incremented 4-digit 
	$project->{mark_sequence_counter} //= '0000';
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
	
	my $self = bless { @_ }, $class;
	$self->{attrib} //= {}; # attributes hash

	#print "self class: $class, self type: ", ref $self, $/;
	if ($self->name) {
		if ( my $old = delete $by_name{$self->name} ) {
			::pager("replacing previous mark at " .  $old->time);
			@all = grep{ $_->name ne $self->name } @all;
		}
		$by_name{ $self->name } = $self;
	}
	push @all, $self;
	$::this_mark = $self;
	
	$self;
	
}

sub set_name {
	my $mark = shift;
	my $name = shift;
	pager("name: $name\n");
	if ( defined $by_name{ $name } ){
	carp "you attempted to assign to name already in use\n";
	}
	else {
		$mark->set(name => $name);
		$by_name{ $name } = $mark;
	}
}

no warnings 'redefine'; # replacing the default accessor
sub attrib { 
	my ($mark, $attr) = @_;
	$mark->{attrib}->{$attr}
}
use warnings 'redefine';
sub matches {
	my ($mark, %rules) = @_;
	while( my($k,$v) = each %rules){
		return 0 unless $mark->$k eq $v
	}
	return 1
}

sub set_attrib {
	my $mark = shift;
	my ($attr, $val) = @_;
	$val = 1 if not $val;
	pager("attr: $attr\n");
	if ( defined $mark->{attrib}->{$attr} ){
		pager("redefining attribute $attr from '$mark->{attrib}->{$attr}' to '$val'");
	}
	else {
		$mark->{attrib}->{$attr} = $val;
		pager("assigning attribute $attr: $val");
	}
}
sub delete_attrib {
	my ($mark, $attr) = @_;
	delete $mark->{attrib}->{$attr}
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
sub time_from_tag {
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
sub duration_from_tag {
	my $tag = shift;
	$tag or $tag = '';
	#print "tag: $tag\n";
	my $mark;
	if ($tag =~ /[\d.-]+/) { # we assume time 
		#print "mark time: ", $tag, $/;
		return $tag;
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
	my $time = time_from_tag($tag);
	return unless defined $time;
	$time -= ::play_start_time() if $mode->{offset_run};
	$time
}

sub AUTOLOAD {
	my $self = shift;
	my ($attr) = $AUTOLOAD =~ /([^:]+)$/;
	return $self->{attrib}->{$attr}
}

# ---------- Mark and jump routines --------
{
package ::;
use Modern::Perl '2020';
use ::Globals qw(:all);

sub get_marks {
	my @marks = all(); 	
	my %rules = @_;
	my @want;
MARK: for my $m (@marks){
		for my $k (keys %rules){
			next MARK if not $m->$k
		}
		push @want, $m
	}
	@want;
}
sub lint_snip_marks {
	# do i sstart with snip retain or snip discard
	# retain command
    # next toggle discards
    # snip discard

}
sub toggle_snip {
	my @clip = grep{$_->clip} ::Mark::all();
	retain(), return if (scalar @clip) == 0;
	$clip[-1]->start ? retain() : discard ();
}
sub discard {
	my $mark = drop_mark("clip-end-".::Mark::next_id());
	pager("discarding content from ".ecasound_iam('getpos'));
	$mark->set_attrib("clip");
	$mark->set_attrib("end");
	clip_end_beep();
}
sub retain {
	my $mark = drop_mark("clip-start-".::Mark::next_id());
	pager("retaining content from ".ecasound_iam('getpos'));
	$mark->set_attrib("clip");
	$mark->set_attrib("start");
	clip_start_beep();
}
sub drop_mark {
	logsub((caller(0))[3]);
	my $name = shift;
	my $here = ecasound_iam("getpos");

	if( my $mark = $::Mark::by_name{$name}){
		pager("$name: a mark with this name exists already at: ", 
			colonize($mark->time));
		return
	}
	if( my ($mark) = grep { $_->time == $here} ::Mark::all()){
		pager( q(This position is already marked by "),$mark->name,q(") );
		 return 
	}

	my $mark = ::Mark->new( time => $here, 
							name => $name);

	$ui->marker($mark); # for GUI
	$mark
}
sub mark { # GUI_CODE
	logsub((caller(0))[3]);
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
	logsub((caller(0))[3]);
	my $mark = next_mark_object();
	set_position($mark->time);
	$this_mark = $mark;
}
sub next_mark_object {
	my @marks = ::Mark::all();
	my $here = ecasound_iam("cs-get-position");
	for my $i ( 0..$#marks ){
		if ($marks[$i]->time - $here > 0.001 ){
			logpkg('debug', "here: $here, future time: ", $marks[$i]->time);
			return $marks[$i];
		}
	}
}
sub previous_mark_object {
	my @marks = ::Mark::all();
	my $here = ecasound_iam("cs-get-position");
	for my $i ( reverse 0..$#marks ){
		if ($marks[$i]->time < $here ){
			return $marks[$i];
		}
	}
}
sub previous_mark {
	logsub((caller(0))[3]);
	my $mark = previous_mark_object();
	set_position($mark->time);
	$this_mark = $mark;
}
	
sub modify_mark {
	my ($mark, $newtime, $quiet) = @_;
	$mark->set( time => $newtime );
	! $quiet && do {
	pager($mark->name, ": set to ", d2( $newtime), "\n");
	pager("adjusted to ",$mark->time, "\n") 
		if $mark->time != $newtime;
	};
	set_position($mark->time);
	request_setup();
}

## jump playback head position

sub jump_to_start { 
	logsub((caller(0))[3]);
	return if ::ChainSetup::really_recording();
	jump( 0 );
}
sub jump_to_end { 
	logsub((caller(0))[3]);
	# ten seconds shy of end
	return if ::ChainSetup::really_recording();
	my $end = ecasound_iam('cs-get-length') - $config->{seek_end_margin} ;  
	jump($end);
} 
sub jump {
	return if ::ChainSetup::really_recording();
	my $delta = shift;
	logsub((caller(0))[3]);
	my $here = ecasound_iam('getpos');
	logpkg('debug', "delta: $delta, here: $here");
	my $new_pos = $here + $delta;
	if ( $setup->{audio_length} )
	{
		$new_pos = $new_pos < $setup->{audio_length} 
			? $new_pos 
			: $setup->{audio_length} - 10
	}
	set_position( $new_pos );
}
sub set_position { fade_around(\&_set_position, @_) }

sub _set_position {
	logsub((caller(0))[3]);

    return if ::ChainSetup::really_recording(); # don't allow seek while recording

    my $seconds = shift;
    my $coderef = sub{ ecasound_iam("setpos $seconds") };

	$jack->{jackd_running} 
		?  ::stop_do_start( $coderef, $jack->{seek_delay} )
		:  $coderef->();

	update_clock_display();
}


sub delete_current_mark {}
sub bump_mark_forward  { 
	my $multiple = shift;
	# play mark_replay_seconds before mark, stop at mark
	$this_mark->{time} += $config->{mark_bump_seconds} * $multiple;
	my $rp = $config->{mark_replay_seconds};
	if ($rp) {
		stop_transport();
		::ecasound_iam("setpos ".$this_mark->time - $rp);
		limit_processing_time($rp);
		request_setup();		
		start_transport();
	}
}
sub bump_mark_forward_1  { bump_mark_forward(1)   }
sub bump_mark_forward_10 { bump_mark_forward(10)  }
sub bump_mark_back_1     { bump_mark_forward(-1)  }
sub bump_mark_back_10    { bump_mark_forward(-10) }


sub forward {
	my $delta = shift;
	my $here = ecasound_iam('getpos');
	return unless $here;
	my $new = $here + $delta;
	set_position( $new );
}

sub rewind {
	my $delta = shift;
	forward( -$delta );
}
sub jump_forward {
	my $multiplier = shift;
	forward( $multiplier * $config->{playback_jump_seconds})
	}

sub replay { foward($config->{mark_replay_seconds}) }
sub set_playback_jump { $config->{playback_jump_seconds} = shift }
sub set_mark_bump     { $config->{mark_bump_seconds}     = shift }
sub set_mark_replay   { $config->{mark_replay_seconds}   = shift }
sub jump_forward_1    { jump_forward(  1) }
sub jump_forward_10   { jump_forward( 10) }
sub jump_back_1   { jump_forward( -1) }
sub jump_back_10  { jump_forward(-10) }
	
} # end package
{ package ::HereMark;
our @ISA = '::Mark';
our $last_time;
sub name { 'Here' }
sub time { ::ecasound_iam('cs-connected') ? ($last_time = ::ecasound_iam('getpos')) : $last_time } 
}

{ package ::ClipMark;
use Modern::Perl '2020';
our @ISA = '::Mark';


}

{ package ::TempoMark;

	our $VERSION = 1.0;
	use Modern::Perl '2020';
	use ::Log qw(logpkg);
	use ::Globals qw(:all);
	our @ISA = '::Mark';
	use SUPER; 
	use ::Object qw( 
					 name 
					bars	
					beats
					ticks
					 );
}

1;
__END__
