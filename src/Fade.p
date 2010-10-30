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
	@::fade_data = (); # for save/restore
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

	#print "object class: $class, object type: ", ref $object, $/;

	my $id = add_fader($object->track);	# only when necessary
	
	my $track = $::tn{$object->track};

	# add linear envelope controller -klg if needed
	
	refresh_fade_controller($track);
	$object
	
}

# helper routines

sub refresh_fade_controller {
	my $track = shift;

	# remove controller if present
	if( $track->fader and my ($old) = @{$::cops{$track->fader}{owns}})
		{ ::remove_effect($old) }

	return unless
		my @pairs = fader_envelope_pairs($track); 

	# add fader if it is missing

	add_fader($track->name);	

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
	
	my $initial_level = first_fade_is_type_in($track->name) 
		? $off_level 
		: $on_level;
	::effect_update_copp_set($track->fader,0,$initial_level);
}


sub all_fades {
	my $track_name = shift;
	grep{ $_->track eq $track_name } values %by_index
}
sub fades {
	my $track_name = shift;
	my @fades = all_fades($track_name);

	# throw away fades that are not in edit play region (if active)
	@fades = grep
		{ my $time = $::Mark::by_name{$_->mark1}->{time};
		  		$time >= $::this_edit->play_start_time
			and $time <= $::this_edit->play_end_time
		} @fades if ::edit_mode() ;

	# sort remaining fades by unadjusted mark1 time
	sort{ $::Mark::by_name{$a->mark1}->{time} <=>
		  $::Mark::by_name{$b->mark1}->{time}
	} @fades;
}

sub first_fade_is_type_in {
	my $track_name = shift;
	my @fades = fades($track_name);
	! scalar @fades or $fades[0]->type eq 'in'
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
		#say "marktime1: $marktime1";
		#say "marktime2: $marktime2";
		push @specs, [$marktime1, $marktime2, $fade->type];
}
	# sort fades # already done! XXX
	@specs = sort{ $a->[0] <=> $b->[0] } @specs;
	#say( ::yaml_out( \@specs));

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
	my $track = $::tn{$fade->track};
	my $i = $fade->n;
	
	# remove object from index
	delete $by_index{$i};

	# remove fader entirely if this is the last fade on the track
	
	my @track_fades = all_fades($fade->track);
	if ( ! @track_fades ){ 
		::remove_effect($track->fader);
		$::tn{$fade->track}->set(fader => undef);
	}
	else { refresh_fade_controller($track) }
}
sub add_fader {
	my $name = shift;
	my $track = $::tn{$name};

	my $id = $track->fader;

	# create a fader if necessary
	
	if (! $id){	
		
		my $first_effect = $track->ops->[0];
		if ( $first_effect ){
			$id = ::Text::t_insert_effect($first_effect, 'eadb', [0]);
		} else { 
			$id = ::Text::t_add_effect('eadb', [0]) 
		}
		$track->set(fader => $id);
	}
	$id
}

1;

