# ----------- Fade ------------
package ::Fade;
use Modern::Perl '2020';
use List::Util qw(min);
our $VERSION = 1.0;
use Carp;
use warnings;
no warnings qw(uninitialized);
our @ISA;
our($n, %by_index);
use ::Globals qw(:singletons %tn @fade_data); 
use ::Log qw(logsub logpkg);
use ::Effect  qw(remove_effect add_effect update_effect);
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
	my @pairs = fader_envelope_pairs($track);
	add_fader($track->name);	
	my $operator  = ::fxn($track->fader)->type;
	my $off_level = $config->{mute_level}->{$operator};
	my $on_level  = $config->{unity_level}->{$operator};
	my @controllers = @{::fxn($track->fader)->owns};
	logpkg('debug',$track->name, ": existing controllers: @controllers");
	for my $controller (@controllers)
	{
		logpkg('debug',"removing fade controller $controller");
		remove_effect($controller);
	}

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

	# set fader to correct initial value
	# 	first fade is type 'in'  : 0
	# 	first fade is type 'out' : 100%
	
	update_effect($track->fader,0, initial_level($track->name) * 100)
}


sub all_fades {
	my $track_name = shift;
	sort { 
		$::Mark::by_name{$a->mark1}->{time} <=> $::Mark::by_name{$b->mark1}->{time}
	} grep { $_->track eq $track_name } values %by_index
}
sub fades {

	# get fades within playable region
	
	my $track_name = shift;
	my $track = $tn{$track_name};
	my @fades = all_fades($track_name);
	return @fades if ! $mode->{offset_run};

	# handle offset run mode
	my @in_bounds;
	my $play_end = ::play_end_time();
	my $play_start_time = ::play_start_time();
	my $length = $track->wav_length;
	for my $fade (@fades){
		my $play_end_time = $play_end ?  min($play_end, $length) : $length;
		my $time = $::Mark::by_name{$fade->mark1}->{time};
		push @in_bounds, $fade if $time >= $play_start_time and $time <= $play_end_time;
	}
	@in_bounds
}

# our envelope must include a straight segment from the
# beginning of the track (or region) to the fade
# start. Similarly, we need a straight segment
# from the last fade to the track (or region) end

# - If the first fade is a fade-in, the straight
#   segment will be at zero-percent level
#   (otherwise 100%)
#
# - If the last fade is fade-out, the straight
#   segment will be at zero-percent level
#   (otherwise 100%)

# although we can get the precise start and endpoints,
# I'm using 0 and $track->shifted_playat_time + track length

sub initial_level {
	# return 0, 1 or undef
	# 0: track starts silent
	# 1: track starts at full volume
	my $track_name = shift;
	my @fades = fades($track_name) or return undef;
	# if we fade in we'll hold level zero from beginning
	(scalar @fades and $fades[0]->type eq 'in') ? 0 : 1
}
sub exit_level {
	my $track_name = shift;
	my @fades = fades($track_name) or return undef;
	# if we fade out we'll hold level zero from end
	(scalar @fades and $fades[-1]->type eq 'out') ? 0 : 1
}
sub initial_pair { # duration: zero to... 
	my $track_name = shift;
	my $init_level = initial_level($track_name);
	defined $init_level or return ();
	(0,  $init_level )
	
}
sub final_pair {   # duration: .... to length
	my $track_name = shift;
	my $exit_level = exit_level($track_name);
	defined $exit_level or return ();
	my $track = $tn{$track_name};
	(
		$track->shifted_playat_time + $track->wav_length,
		$exit_level
	);
}

sub fader_envelope_pairs {
	# return number_of_pairs, pos1, val1, pos2, val2,...
	my $track = shift;
	my @fades = fades($track->name);

	my @specs;
	for my $fade ( @fades ){

		# calculate fades
		my $marktime1 = ::Mark::mark_time($fade->mark1);
		my $marktime2 = ::Mark::mark_time($fade->mark2);
		if ($marktime2) {}  # nothing to do
		elsif( $fade->relation eq 'fade_from_mark')
			{ $marktime2 = $marktime1 + $fade->duration } 
		elsif( $fade->relation eq 'fade_to_mark')
			{
				$marktime2 = $marktime1;
				$marktime1 -= $fade->duration
			} 
		else { $fade->dumpp; die "fade processing failed" }
		logpkg('debug',"marktime1: $marktime1, marktime2: $marktime2");
		push @specs, 
		[ 	$marktime1, 
			$marktime2, 
			$fade->type, 
			::fxn($track->fader)->type,
		];
}
	# sort fades -  may not need this
	@specs = sort{ $a->[0] <=> $b->[0] } @specs;
	logpkg('debug',sub{::json_out( \@specs)});

	my @pairs = map{ spec_to_pairs($_) } @specs;

#   WEIRD message - try to figure this out
#   XXX results in bug via AUTOLOAD for Edit
#	@pairs = (initial_pair($track->name), @pairs, final_pair($track->name)); 

	# add flat segments 
	# - from start to first fade 
	# - from last fade to end


	# prepend number of pairs;
	unshift @pairs, (scalar @pairs / 2) if @pairs;
	@pairs;
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

