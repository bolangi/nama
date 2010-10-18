# ----------- Fade ------------
package ::Fade;
use Modern::Perl;
our $VERSION = 1.0;
use Carp;
use warnings;
no warnings qw(uninitialized);
our @ISA;
use vars qw($n %by_index $off_level $on_level $fade_down_level $fade_down_fraction
$fade_time1_fraction $fade_time2_fraction);
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
%by_index = ();	# return ref to Mark by name
$off_level = -256;
$on_level = 0;
$fade_down_level = -64;
$fade_down_fraction = 0.75;
$fade_time1_fraction = 0.9;
$fade_time2_fraction = 0.1;

# example
#
# if fade time is 10 for a fade out
# and fade start time is 0:
#
# from 0 to 9, fade from 0 (100%) to -64db
# from 9 to 10, fade from -64db to -256db


# 



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

	#print "object class: $class, object type: ", ref $object, $/;

	
	# add fader effect at the beginning if needed
	my $track = $::tn{$object->track};
	my $id = $track->fader;
	if( ! $id ){
		my $first_effect_id = $track->ops->[0];
		if ( $first_effect_id ){
			$id = ::Text::t_insert_effect($first_effect_id, 'eadb', [0]);
		} else { 
			$id = ::Text::t_add_effect('eadb', [0]) 
		}
		$track->set(fader => $id);
	}
	# add linear envelope controller -klg if needed
	
	refresh_fade_controller($track);
	$object
	
}

sub refresh_fade_controller {
	my $track = shift;

	# remove controller if present
	if( $track->fader and my ($old) = @{$::cops{$track->fader}{owns}})
		{ ::remove_effect($old) }

	return unless
		my @pairs = fader_envelope_pairs($track); 

	# add controller
	::Text::t_add_ctrl($track->fader,  # parent
					 'klg',	  		 # Ecasound controller
					 [1,				 # Ecasound parameter 1
					 $off_level,
					 $on_level,
					 @pairs,
					 ]
	);

	# set fader to correct initial value
	# 	first fade is type 'in'  : 0
	# 	first fade is type 'out' : 100%
	
	my $initial_level = first_fader_is_type_in($track->name) 
		? $off_level 
		: $on_level;
	::effect_update_copp_set($track->fader,0,$initial_level);
}

# class subroutines

sub fades {
	my $track_name = shift;
	# sort by unadjusted mark1 time
	sort{ $::Mark::by_name{$a->mark1}->{time} <=>
		  $::Mark::by_name{$b->mark1}->{time}
		}
	grep{ $_->track eq $track_name } values %by_index
}

sub first_fade_is_type_in {
	my $track_name = shift;
	my @fades = fades($track_name);
	$fades[0]->type eq 'in'
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
		if ($marktime2){  # nothing to do
		} elsif( $fade->relation eq 'fade_from_mark'){
			$marktime2 = $marktime1 + $fade->duration
		} elsif( $fade->relation eq 'fade_to_mark'){
			$marktime2 = $marktime1;
			$marktime1 -= $fade->duration
		} else { $fade->dumpp; die "fade processing failed" }
		push @specs, [$marktime1, $marktime2, $fade->type];
	}
	# sort fades # already done! XXX
	@specs = sort{ $a->[0] <=> $b->[0] } @specs;

	# prepend number of pairs, flatten list
	my @pairs = map{ spec_to_pairs($_) } @specs;
	unshift @pairs, (scalar @pairs / 2);
	@pairs;
}
		
sub spec_to_pairs {
	my ($from, $to, $type) = @{$_[0]};
	$::debug and say "from: $from, to: $to, type: $type";
	my $cutpos;
	my @pairs;
	if ( $type eq 'out' ){
		$cutpos = $from + $fade_time1_fraction * ($to - $from);
		push @pairs, ($from, 1, $cutpos, $fade_down_fraction, $to, 0);
	} elsif( $type eq 'in' ){
		$cutpos = $from + $fade_time2_fraction * ($to - $from);
		push @pairs, ($from, 0, $cutpos, $fade_down_fraction, $to, 1);
	}
	@pairs
}
	

# utility routines

	# the following routine makes it possible to
	# remove an edit fade by the name of the edit mark
	
sub remove_by_mark_name {
	my $mark1 = shift;
	my ($i) = map{ $_->n} grep{ $_->mark1 eq $mark1 } values %by_index; 
	remove($i) if $i;
}

sub remove { # supply index
	my $i = shift;
	my $fade = $by_index{$i};
	my $track = $::tn{$fade->track};
	
	# remove object from index
	delete $by_index{$i};

	# if this is the last fade on the track
	
	my @track_fades = fades($fade->track);
	if ( ! @track_fades ){ 

		# make sure the fader operator is _on_
		#::effect_update_copp_set( $track->fader, 0, $on_level );

		# remove fader entirely
		::remove_effect($track->fader);
		$::tn{$fade->track}->set(fader => undef);
	}
	else { refresh_fade_controller($track) }
}

1;

