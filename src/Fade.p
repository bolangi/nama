# ----------- Fade ------------
package ::Fade;
use v5.36;
use List::Util qw(min max);
our $VERSION = 1.0;
use Carp;
use warnings;
no warnings qw(uninitialized);
our @ISA;
our($n, %by_index);
use ::Globals qw(:singletons %tn @fade_data); 
use ::Log qw(logsub logpkg);
use ::Effect  qw(remove_effect add_effect update_effect);
use ::FadeEnvelope qw(clip_envelope_to_window envelope_level_at_time);
# we don't import 'type' as it would clobber our $fade->type attribute
use ::Object qw( 
				 n
				 type
				 mark1
				 mark2
				 duration
				 relation
				 track
				 class
				 );
initialize();

sub initialize { 
	%by_index = (); 
	@fade_data = (); # for save/restore
}
sub next_n {
	my $n = 1;
	while( $by_index{$n} ){ $n++}
	$n
}
sub new {
	my $class = shift;	
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	
	my $object = bless 
	{ 
#		class => $class,  # not needed yet
		n => next_n(),    
		relation => 'fade_from_mark',
		@_	
	}, $class;

	$by_index{$object->n} = $object;

	logpkg('debug',"object class: $class, object type: ", ref $object);

	my $id = add_fader($object->track);
	
	my $track = $tn{$object->track};

	::request_setup(); # fades take effect after next engine stop
	$object
	
}

# helper routines

sub refresh_fade_controller {
	my $track = shift;
	my $envelope = fader_envelope($track);
	my @pairs = @{$envelope->{pairs}};
	add_fader($track->name);	
	my $operator  = $track->fader_effect->type;
	my $off_level = $config->{mute_level}->{$operator};
	my $on_level  = $config->{unity_level}->{$operator};
	my @controllers = @{$track->fader_effect->owned_ids};
	logpkg('debug',$track->name, ": existing controllers: @controllers");
	for my $controller (@controllers)
	{
		logpkg('debug',"removing fade controller $controller");
		remove_effect($controller);
	}

	if (@pairs){
		# add controller
		my $reuseid = pop @controllers; # we expect only one
		logpkg('debug',"applying fade controller");
		add_effect({
			track		=> $track,
			id			=> $reuseid,
			parent	 	=> $track->fader,
			type		=> 'klg',	  		 # Ecasound controller
			params => [	1,				 # modify first parameter of fader op
							$off_level,
							$on_level,
							@pairs,
						]
		});
	}

	# Set the fader to the level established at the window start, including
	# the result of any fades completed earlier in the track or region.
	
	update_effect($track->fader, 0, $envelope->{initial_level} * 100)
}


sub all_fades {
	my $track_name = shift;
	sort { 
		$::Mark::by_name{$a->mark1}->{time} <=> $::Mark::by_name{$b->mark1}->{time}
	} grep { $_->track eq $track_name } values %by_index
}

sub fade_timeline_interval {
	my $fade = shift;
	my $time1 = ::Mark::time_from_tag($fade->mark1);
	my $time2 = ::Mark::time_from_tag($fade->mark2);

	if (! defined $time2){
		if ($fade->relation eq 'fade_from_mark'){
			$time2 = $time1 + $fade->duration;
		} elsif ($fade->relation eq 'fade_to_mark'){
			$time2 = $time1;
			$time1 -= $fade->duration;
		} else {
			$fade->dumpp;
			die "fade processing failed";
		}
	}
	(min($time1, $time2), max($time1, $time2))
}

sub track_timeline_interval {
	my $track = shift;
	my $track_duration = $track->is_region
		? $track->endpoint - $track->startpoint
		: $track->wav_length;
	my $track_timeline_endpoint = $track->timeline_position + $track_duration;
	($track->timeline_position, $track_timeline_endpoint)
}

sub fade_window_timeline_interval {
	my $track = shift;
	my ($track_start, $track_end) = track_timeline_interval($track);
	return ($track_start, $track_end) unless ::timeline_adjustment_active();
	(
		max(::timeline_play_start_position(), $track_start),
		min(::timeline_play_end_position(), $track_end),
	)
}

sub fades {

	# get fades within playable region
	
	my $track_name = shift;
	my $track = $tn{$track_name};
	my @fades = all_fades($track_name);

	# Fade marks and bounds are permanent timeline positions. Exclude only a
	# fade wholly outside its track or region. Fades before an adjusted run
	# window may still determine the level at which that window begins.
	my @in_bounds;
	my ($track_start, $track_end) = track_timeline_interval($track);
	for my $fade (@fades){
		my ($fade_start, $fade_end) = fade_timeline_interval($fade);
		push @in_bounds, $fade
			if $fade_end >= $track_start
			and $fade_start <= $track_end;
	}
	@in_bounds
}

sub fader_envelope {
	# Return the initial fader level and Ecasound envelope pairs.
	my $track = shift;
	my @fades = fades($track->name);

	my @specs;
	for my $fade ( @fades ){

		# calculate fades
		my $adjusted_time1 = ::Mark::adjusted_time_from_tag($fade->mark1);
		my $adjusted_time2 = ::Mark::adjusted_time_from_tag($fade->mark2);
		if (defined $adjusted_time2) {}  # nothing to do
		elsif( $fade->relation eq 'fade_from_mark')
			{ $adjusted_time2 = $adjusted_time1 + $fade->duration }
		elsif( $fade->relation eq 'fade_to_mark')
			{
				$adjusted_time2 = $adjusted_time1;
				$adjusted_time1 -= $fade->duration
			} 
		else { $fade->dumpp; die "fade processing failed" }
		logpkg('debug',
			"adjusted_time1: $adjusted_time1, adjusted_time2: $adjusted_time2");
		push @specs, 
		[ 	$adjusted_time1,
			$adjusted_time2,
			$fade->type, 
			::fxn($track->fader)->type,
		];
}
	# sort fades -  may not need this
	@specs = sort{ $a->[0] <=> $b->[0] } @specs;
	logpkg('debug',sub{::json_out( \@specs)});

	my @complete_pairs = map{ spec_to_pairs($_) } @specs;
	my ($timeline_start, $timeline_end) =
		fade_window_timeline_interval($track);
	my $adjusted_start =
		::adjusted_time_from_timeline_position($timeline_start);
	my $adjusted_end =
		::adjusted_time_from_timeline_position($timeline_end);
	my $initial_level = envelope_level_at_time(
		$adjusted_start,
		@complete_pairs,
	);
	my @pairs = clip_envelope_to_window(
		$adjusted_start,
		$adjusted_end,
		@complete_pairs,
	);

	# prepend number of pairs;
	unshift @pairs, (scalar @pairs / 2) if @pairs;
	{
		initial_level => $initial_level,
		pairs => \@pairs,
	}
}
		
# each 'spec' is an array reference of the form [ $from, $to, $type, $op ]
#
# $from: time (in seconds)
# $to:   time (in seconds)
# $type: 'in' or 'out'     
# $op:   'ea' or 'eadb'

sub spec_to_pairs {
	my ($from, $to, $type, $op) = @{$_[0]};
	logpkg('debug',"from: $from, to: $to, type: $type");
	my $cutpos;
	my @pairs;

	# op 'eadb' uses two-stage fade
	
	
	if ($op eq 'eadb'){
		if ( $type eq 'out' ){
			$cutpos = $from + $config->{fade_time1_fraction} * ($to - $from);
			push @pairs, ($from, 1, $cutpos, $config->{fade_down_fraction}, $to, 0);
		} elsif( $type eq 'in' ){
			$cutpos = $from + $config->{fade_time2_fraction} * ($to - $from);
			push @pairs, ($from, 0, $cutpos, $config->{fade_down_fraction}, $to, 1);
		}
	}

	# op 'ea' uses one-stage fade
	
	elsif ($op eq 'ea'){
		if ( $type eq 'out' ){
			push @pairs, ($from, 1, $to, 0);
		} elsif( $type eq 'in' ){
			push @pairs, ($from, 0, $to, 1);
		}
	}
	else { die "missing or illegal fader op: $op" }

	@pairs
}
	

# the following routine makes it possible to
# remove an edit fade by the name of the edit mark
	
# ???? does it even work?
sub remove_by_mark_name {
	my $mark1 = shift;
	my ($i) = map{ $_->n} grep{ $_->mark1 eq $mark1 } values %by_index; 
	remove($i) if $i;
}
sub remove_by_index {
	my $i = shift;
	my $fade = $by_index{$i};
	$fade->remove;
}

sub remove { 
	my $fade = shift;
	my $track = $tn{$fade->track};
	my $i = $fade->n;
	
	# remove object from index
	delete $by_index{$i};

	# remove fader entirely if this is the last fade on the track
	
	my @track_fades = all_fades($fade->track);
	if ( ! @track_fades ){ 
		remove_effect($track->fader);
		$tn{$fade->track}->set(fader => undef);
	}
	else { refresh_fade_controller($track) }
}
sub add_fader {
	# if it is missing

	my $name = shift;
	my $track = $tn{$name};

	my $id = $track->fader;

	# create a fader if necessary, place before first effect
	# if it exists
	
	if (! $id or ! ::fxn($id)){	
		my $first_effect = $track->ops->[0];
		$id = add_effect({
				before 	=> $first_effect, 
				track	=> $track,
				type	=> $config->{fader_op}, 
				params 	=> [0], # XX hardcoded for -ea chain operator
		});
		$track->set(fader => $id);
	}
	$id
}
package ::;

sub fade_uses_mark {
	my $mark_name = shift;
	grep{ $_->mark1 eq $mark_name or $_->mark2 eq $mark_name } values %::Fade::by_index;
}
	
sub setup_fades { 
	# + data from Fade objects residing in %::Fade::by_name
	# + apply to tracks 
	#     * that are part of current chain setup
	#     * that have a fade operator (i.e. most user tracks)
	map{ ::Fade::refresh_fade_controller($_) }
	grep{$_->{fader} }
	::ChainSetup::engine_tracks();
}
	

1;
