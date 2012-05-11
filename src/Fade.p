# ----------- Fade ------------
package ::Fade;
use Modern::Perl;
use List::Util qw(min);
our $VERSION = 1.0;
use Carp;
use warnings;
no warnings qw(uninitialized);
our @ISA;
use vars qw($n %by_index);
use ::Globals qw(:singletons %tn @fade_data); 
use ::Log qw(logit);
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

# example
#
# if fade time is 10 for a fade out
# and fade start time is 0:
#
# from 0 to 9, fade from 0 (100%) to -64db
# from 9 to 10, fade from -64db to -256db

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

	logit('::Fade','debug',"object class: $class, object type: ", ref $object);

	my $id = add_fader($object->track);	# only when necessary
	
	my $track = $tn{$object->track};

	# add linear envelope controller -klg if needed
	
	refresh_fade_controller($track);
	$object
	
}

# helper routines

sub refresh_fade_controller {
	my $track = shift;
	my $operator  = type($track->fader);
	my $off_level = $config->{mute_level}->{$operator};
	my $on_level  = $config->{unity_level}->{$operator};
	my $controller; # effect ID
	($controller) = @{owns($track->fader)} if $track->fader;

	logit('::Fade','debug',"removing fade controller");
	::remove_effect($controller) if $controller;

	return unless
		my @pairs = fader_envelope_pairs($track); 

	# add fader if it is missing

	add_fader($track->name);	

	# add controller
	logit('::Fade','debug',"applying fade controller");
	::add_effect({
		cop_id		=> $controller,
		parent_id 	=> $track->fader,
		type		=> 'klg',	  		 # Ecasound controller
		values		=> [	1,				 # Ecasound parameter 1
					 		$off_level,
					 		$on_level,
					 		@pairs,
					 	]
	});

	# set fader to correct initial value
	# 	first fade is type 'in'  : 0
	# 	first fade is type 'out' : 100%
	
	 
	::effect_update_copp_set($track->fader,0, initial_level($track->name))
}


sub all_fades {
	my $track_name = shift;
	grep{ $_->track eq $track_name } values %by_index
}
sub fades {

	# get fades within playable region
	
	my $track_name = shift;
	my $track = $tn{$track_name};
	my @fades = all_fades($track_name);

	
	if($mode->{offset_run}){

		# get end time
		
		my $length = $track->wav_length;
		my $play_end = ::play_end_time();
		my $play_end_time = $play_end ?  min($play_end, $length) : $length;

		# get start time
	
		my $play_start_time = ::play_start_time();
	
		# throw away fades that are not in play region
	
		@fades = grep
			{ my $time = $::Mark::by_name{$_->mark1}->{time};
					$time >= $play_start_time
				and $time <= $play_end_time
			} @fades 
	}

	# sort remaining fades by unadjusted mark1 time
	sort{ $::Mark::by_name{$a->mark1}->{time} <=>
		  $::Mark::by_name{$b->mark1}->{time}
	} @fades;
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
# I'm using 0 and $track->adjusted_playat_time + track length

sub initial_level {
	# return 0, 1 or undef
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
		$track->adjusted_playat_time + $track->wav_length,
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
		logit('::Fade','debug',"marktime1: $marktime1, marktime2: $marktime2");
		push @specs, 
		[ 	$marktime1, 
			$marktime2, 
			$fade->type, 
			type($track->fader),
		];
}
	# sort fades -  may not need this
	@specs = sort{ $a->[0] <=> $b->[0] } @specs;
	logit('::Fade','debug',sub{::yaml_out( \@specs)});

	my @pairs = map{ spec_to_pairs($_) } @specs;

#   XXX results in bug via AUTOLOAD for EditTrack
#	@pairs = (initial_pair($track->name), @pairs, final_pair($track->name)); 

	# add flat segments 
	# - from start to first fade 
	# - from last fade to end


	# prepend number of pairs;
	unshift @pairs, (scalar @pairs / 2);
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
	logit('::Fade','debug',"from: $from, to: $to, type: $type");
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
		::remove_effect($track->fader);
		$tn{$fade->track}->set(fader => undef);
	}
	else { refresh_fade_controller($track) }
}
sub add_fader {
	my $name = shift;
	my $track = $tn{$name};

	my $id = $track->fader;

	# create a fader if necessary, place before first effect
	# if it exists
	
	if (! $id){	
		my $first_effect = $track->ops->[0];
		$id = ::add_effect({
				before 	=> $first_effect, 
				track	=> $track,
				type	=> $config->{fader_op}, 
				values	=> [0],
		});
		$track->set(fader => $id);
	}
	$id
}

package ::;

sub apply_fades { 
	# use info from Fade objects in %::Fade::by_name
	# applying to tracks that are part of current
	# chain setup
	map{ ::Fade::refresh_fade_controller($_) }
	grep{$_->{fader} }  # only if already exists
	::ChainSetup::engine_tracks();
}
	

1;

