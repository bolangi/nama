
# ----------- Mark ------------
{
package ::Mark;
use v5.36;
our $VERSION = 1.0;
use Carp qw(croak carp);
use warnings;
our(%by_name, @all);
use ::Globals qw($setup $project);
use ::Object qw( 
					name 
					time
			   );

sub initialize {
	map{ $_->remove} ::Mark::all();
	@all = ();	
	%by_name = ();	# return ref to Mark by name
	$by_name{Here} = bless {}, '::HereMark';
	@::marks_data = (); # for save/restore
}
sub new {
	my $class = shift;	
	my %vals = @_;
	my @undeclared = grep { !$class->is_legal_key($_) } keys %vals;
	croak 'undeclared field: ' . join(', ', sort @undeclared) if @undeclared;

	# to support set_edit_points, we now allow marks to be overwritten
	#
	#croak  "name already in use: $vals{name}\n"
	#	 if $by_name{$vals{name}}; # null name returns false
	
	my $self = bless \%vals, $class;

	#print "self class: $class, self type: ", ref $self, $/;
	if ($self->name) {
		if ( my $old = delete $by_name{$self->name} ) {
			::notify("replacing previous mark at " .  $old->time);
			@all = grep{ $_->name ne $self->name } @all;
		}
		$by_name{ $self->name } = $self;
	}
	push @all, $self;
	$::this_mark = $self;
	
	$self;
	
}

sub set_name ($mark, $name) {
	::notify("name: $name\n");
	if ( defined $by_name{ $name } ){
	carp "you attempted to assign to name already in use\n";
	}
	else {
		$mark->set(name => $name);
		$by_name{ $name } = $mark;
	}
}

sub jump_here ($mark) {
	::set_position($mark->adjusted_time);
	$::this_mark = $mark;
}
sub adjusted_time ($mark) {
	my $time = ::adjusted_time_from_timeline_position($mark->time);
	$time > 0 ? $time : 0
}
sub remove ($mark) {
	::throw('Fades depend on this mark. Remove failed.'), return	
		if ::fade_uses_mark($mark->name);
	if ( $mark->name ) {
		delete $by_name{$mark->name};
	}
	@all = grep { $_ != $mark } @all;
}
sub next ($mark) {
	::next_mark();
}
sub previous ($mark) {
	::previous_mark();
}

# -- Class Methods

sub all { sort { $a->{time} <=> $b->{time} }@all }

sub loop_timeline_interval {
	my @points = sort { $a <=> $b }
		grep { defined }
		map { time_from_tag($_) }
		$setup->{loop_endpoints}->@[0,1];
	return unless @points == 2 and $points[0] < $points[1];
	@points
}
sub loop_timeline_start {
	my @points = loop_timeline_interval();
	$points[0]
}
sub loop_timeline_end {
	my @points = loop_timeline_interval();
	$points[1]
}
sub adjusted_loop_interval {
	my @points = loop_timeline_interval();
	return unless @points == 2;
	return @points unless ::timeline_adjustment_active();

	my $start = $points[0] > ::timeline_play_start_position()
		? $points[0] : ::timeline_play_start_position();
	my $end = $points[1] < ::timeline_play_end_position()
		? $points[1] : ::timeline_play_end_position();
	return unless $start < $end;

	map { ::adjusted_time_from_timeline_position($_) } ($start, $end)
}
sub adjusted_loop_start {
	my @points = adjusted_loop_interval();
	$points[0]
}
sub adjusted_loop_end {
	my @points = adjusted_loop_interval();
	$points[1]
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
sub adjusted_time_from_tag {
	my $tag = shift;
	my $time = time_from_tag($tag);
	return unless defined $time;
	::adjusted_time_from_timeline_position($time)
}
} # end package Mark
# ---------- Mark and jump routines --------
{
package ::;
use v5.36;
use ::Globals qw(:all);

sub drop_mark {
	logsub((caller(0))[3]);
	my %arg = @_;
	my $name = $arg{name};
	my $here = defined $arg{time}
		? $arg{time}
		: timeline_position_from_adjusted_time(ecasound_iam("getpos"));
	my $mark = ::Mark->new( time => $here, 
							name => $name,
							);

	$ui->marker($mark); # for GUI
}
# Derive clip state -- last clip index and started/ended status -- from mark attributes

sub clip_state {
	my (%starts, %ends);
	my $last_index = 0;
	for my $mark (::Mark::all()) {
		my $index = $mark->clip_index;
		next unless defined $index and $index =~ /\A[1-9][0-9]*\z/;
		$last_index = $index if $index > $last_index;
		$starts{$index} = $mark if $mark->clip_start;
		$ends{$index} = $mark if $mark->clip_end;
	}
	my ($open_index) = sort { $b <=> $a } grep { not $ends{$_} } keys %starts;
	return ($last_index, defined $open_index ? $starts{$open_index} : undef);
}

sub register_clip_endpoint (%args) {
	my $mark = ::ClipMark->new( time => $args{time},
								name => "clip $args{index} $args{name} $args{endpoint}",
								clip_index => $args{index},
								clip_name     => $args{name},
								clip_endpoint => $args{endpoint});
	$ui->marker($mark);
	notify("Clip $args{index} $args{name} " . ($args{endpoint} eq 'start' ? 'started' : 'ended'));
	return $mark;
}

sub start_clip {
	return if ::ChainSetup::really_recording();
	my $time = current_timeline_position();
	stop_transport();
	set_timeline_position($time);
	my ($current_index, $opening_mark) = clip_state();
	end_clip($time) if defined $opening_mark;
	
	my $new_index = $current_index + 1;	
	my $name = prompt_for_text('Clip name?');
	register_clip_endpoint( time     => $time, 
							index    => $new_index, 
							name     => $name,
							endpoint => 'start' );
	start_transport();
}

sub end_clip ($time) {
	return if ::ChainSetup::really_recording();
	my ($last_index, $opening_mark) = clip_state();
	unless ($opening_mark) {
		throw('No clip started');
		return;
	}
	register_clip_endpoint( time  	 => $time,
							index 	 => $opening_mark->clip_index, 
							name  	 => $opening_mark->clip_name, 
							endpoint => 'end'); 
}

sub mark { # GUI_CODE
	logsub((caller(0))[3]);
	my $mark = shift;
	my $pos = $mark->time;
	if ($gui->{_markers_armed}){ 
			$ui->destroy_marker($mark);
			$mark->remove;
		    arm_mark_toggle(); # disarm
	}
	else{ 

		set_position($mark->adjusted_time);
	}
}

sub next_mark {
	logsub((caller(0))[3]);
	my $mark = next_mark_object();
	set_position($mark->adjusted_time);
	$this_mark = $mark;
}
sub next_mark_object {
	my @marks = ::Mark::all();
	my $here = timeline_position_from_adjusted_time(
		ecasound_iam("cs-get-position")
	);
	for my $i ( 0..$#marks ){
		if ($marks[$i]->time - $here > 0.001 ){
			logpkg('debug', "here: $here, future time: ", $marks[$i]->time);
			return $marks[$i];
		}
	}
}
sub previous_mark_object {
	my @marks = ::Mark::all();
	my $here = timeline_position_from_adjusted_time(
		ecasound_iam("cs-get-position")
	);
	for my $i ( reverse 0..$#marks ){
		if ($marks[$i]->time < $here ){
			return $marks[$i];
		}
	}
}
sub previous_mark {
	logsub((caller(0))[3]);
	my $mark = previous_mark_object();
	set_position($mark->adjusted_time);
	$this_mark = $mark;
}
	
sub modify_mark {
	my ($mark, $newtime, $quiet) = @_;
	$mark->set( time => $newtime );
	! $quiet && do {
	::notify($mark->name, ": set to ", d2( $newtime), "\n");
	::notify("adjusted to ",$mark->time, "\n") 
		if $mark->time != $newtime;
	};
	set_position($mark->adjusted_time);
	request_setup();
}
## jump playback head position

sub jump_to_start { 
	logsub((caller(0))[3]);
	return if ::ChainSetup::really_recording();
	set_position_with_fade( 0 );
}
sub jump_to_end { 
	logsub((caller(0))[3]);
	# ten seconds shy of end
	return if ::ChainSetup::really_recording();
	my $end = ecasound_iam('cs-get-length') - $config->{seek_end_margin} ;  
	$end = 0 if $end < 0;
	set_position_with_fade($end);
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
	set_position_with_fade( $new_pos );
}
sub set_position_with_fade { fade_around(\&set_position, @_) }

sub set_position {
	logsub((caller(0))[3]);

    return if ::ChainSetup::really_recording(); # don't allow seek while recording

    my $seconds = shift;
    my $coderef = sub{ ecasound_iam("setpos $seconds") };

	$jack->{jackd_running} 
		?  ::stop_do_start( $coderef, $jack->{seek_delay} )
		:  $coderef->();

	update_clock_display();
}

sub set_timeline_position {
	my $timeline_position = shift;
	set_position(
		adjusted_playback_position_from_timeline_position($timeline_position)
	)
}

# used by hotkeys

#sub previous_mark {}
#sub next_mark {}
sub delete_current_mark {}
#sub drop_mark {}
#sub jump_to_start {}
#sub jump_to_end {}
sub jump_replay {}

sub bump_mark ($multiplier = 1) {
	return unless $this_mark;
	modify_mark(
		$this_mark,
		$this_mark->time + $multiplier * ::stepsize(),
	);
}

sub forward {
	my $delta = shift;
	my $here = ecasound_iam('getpos');
	my $new = $here + $delta;
	set_position( $new );
}

sub rewind {
	my $delta = shift;
	forward( -$delta );
}
sub jump_forward ($multiplier = 1) {
	forward($multiplier * ::stepsize())
}

	
} # end package
{ package ::HereMark;
our $VERSION = 1.0;
our @ISA = '::Mark';
our $last_time;
sub name { 'Here' }
sub time {
	::ecasound_iam('cs-connected')
		? ($last_time = ::timeline_position_from_adjusted_time(
			::ecasound_iam('getpos')
		))
		: $last_time
}
}

{ package ::ClipMark;
use v5.36;
our $VERSION = 1.0;
our @ISA = '::Mark';
use ::Object qw( clip_index clip_name clip_endpoint );
sub clip_start ($self) { $self->clip_endpoint eq 'start' }
sub clip_end   ($self) { $self->clip_endpoint eq 'end'   }

}

{ package ::TempoMark;

	our $VERSION = 1.0;
	use v5.36;
	our @ISA = '::Mark';
	use ::Object qw( 
					 name 
					bar
					beat
					tick
					 );
	sub time ($self) { notation_to_time($self->bar, $self->beat, $self->tick)  }
}

1;
__END__
