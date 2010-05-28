# ----------- Fade ------------
package ::Fade;
use Modern::Perl;
our $VERSION = 1.0;
use Carp;
use warnings;
no warnings qw(uninitialized);
our @ISA;
use vars qw($n %by_index $off_level $on_level $down_level $down_fraction);
use ::Object qw( 
				 n
				 type
				 mark1
				 mark2
				 duration
				 relation
				 track
				 );
%by_index = ();	# return ref to Mark by name
$off_level = -256;
$on_level = 0;
$down_level = -64;
$down_fraction = 0.75;
sub next_n {
	my $n = 1;
	while( $by_index{$n} ){ $n++}
	$n
}
sub new {
	my $class = shift;	
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	
	my $object = bless { n => next_n(), @_	}, $class;
	$by_index{$object->n} = $object;

	#print "object class: $class, object type: ", ref $object, $/;

	
	# add fader effect at the beginning if needed
	my $track = $::tn{$object->track};
	my $id = $track->fader;
	if( ! $id ){
		my $first_effect_id = $::this_track->ops->[0];
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

	# add controller
	::Text::t_add_ctrl($track->fader,  # parent
					 'klg',	  		 # Ecasound controller
					 [1,				 # Ecasound parameter 1
					 $off_level,
					 $on_level,
					 fader_envelope_pairs($track)]
	);
}

# class subroutines

sub fades {
	my $track_name = shift;
	(grep{ $_->track eq $track_name } values %by_index)
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
	# sort fades
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
		$cutpos = $from + 0.95 * ($to - $from);
		push @pairs, ($from, 1, $cutpos, $down_fraction, $to, 0);
	} elsif( $type eq 'in' ){
		$cutpos = $from + 0.05 * ($to - $from);
		push @pairs, ($from, 0, $cutpos, $down_fraction, $to, 1);
	}
	@pairs
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

