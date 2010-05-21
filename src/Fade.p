# ----------- Fade ------------
=comment
mark1: markname
mark2: markname
duration: seconds
relation: fade_to_mark | fade_from_mark
type: fadein | fadeout
curve: log
effect_id: AD
track: sax

add_fade
+ fade data structure
+ fade operator



fade in to|from mark1 [seconds] fade_profile
fade in mark1 mark2 fade_profile
fade in mark1 seconds

remove_fade

klg param low high pairs pos1 val1 pos2 val2

=cut
package ::Fade;
our $VERSION = 1.0;
use Carp;
use warnings;
no warnings qw(uninitialized);
our @ISA;
use vars qw($n %by_index);
use ::Object qw( 
				 n
				 mark1
				 mark2
				 duration
				 relation
				 type
				 curve
				 effect_id
				 track
				 );
%by_index = ();	# return ref to Mark by name
%faders = (); # track_name => effect_id

sub new {
	my $class = shift;	
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	
	my $object = bless { @_	}, $class;

	#print "object class: $class, object type: ", ref $object, $/;

	
	# add fader effect at the beginning if needed
	my $track = $::tn{$object->track};
	my $id = $track->fader;
	if( ! $id ){
		$first_effect_id = $this_track->ops->[0];
		$id = ::Text::t_insert_effect($first_effect_id, 'eadb', [0]);
		$object->{effect_id} = $id;
		$track->set(fader => $id);
	}

	
	# add linear envelope controller -klg if needed
	
	refresh_fade_controller($track);
	$object
	
}

sub refresh_fade_controller {
	my $track = shift;
	if( $track->fader and my ($old) = @{$cops{$track->fader}{owns}})
		{ remove_effect($old) }
	::Text::add_ctrl($id, 'klg',1,-256,0,fader_envelope_pairs($track->name));
}

sub fades {
	my $track_name = shift;
	(grep{ $_->track eq $track_name } values %by_index)
}

sub fader_envelope_pairs {
	# return number_of_pairs, pos1, val1, pos2, val2,...
	my $track_name = shift;
	my @fades = fades($track_name);

	my @pairs;
	for my $fade ( @fades ){

		# calculate fades
		my $marktime1 = ::marktime($fade->mark1);
		my $marktime2 = ::marktime($fade->mark2);
		if ($marktime2){  # nothing to do
		} elsif( $fade->relation eq 'fade_from_mark'){
			$marktime2 = $marktime1 + $fade->duration
		} elsif( $fade->relation eq 'fade_to_mark'){
			$marktime2 = $marktime1;
			$marktime1 -= $fade->duration
		} else { $fade->dumpp; die "fade processing failed" }
		push @pairs, [$marktime1, $marktime2];
	}
	# sort fades
	@pairs = sort{ $a->[0] <=> $b->[0] } @pairs;

	# prepend number of pairs, flatten list
	(scalar @pairs, map{ @$_ } @pairs)
}
		
sub remove {
	my $i = shift;
	my $fade = $by_index{$i};
	delete $by_index{$i};
	my @track_fades = fades($fade->track);
	if ( ! @track_fades ){ 
		remove_effect($fade->effect_id);
		$::tn{$fade->track}->set(fade => undef);
	}
}
1;

