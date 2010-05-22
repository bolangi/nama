# ----------- Fade ------------
=comment
mark1: markname
mark2: markname
duration: seconds
relation: fade_to_mark | fade_from_mark
type: fadein | fadeout
curve: log # not used
effect_id: AD # not used, use $track->fader
track: sax

add_fade
+ fade data structure
+ fade operator

fade in mark1 # 0.5s 
fade out mark1 # 0.5s
fade in seconds mark1
fade in mark1 mark2 
fade in mark1 seconds

remove_fade

klg param low high pairs pos1 val1 pos2 val2

=cut
package ::Fade;
use Modern::Perl;
our $VERSION = 1.0;
use Carp;
use warnings;
no warnings qw(uninitialized);
our @ISA;
use vars qw($n %by_index $off_level $down_level $down_fraction);
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
		$id = ::Text::t_insert_effect($first_effect_id, 'eadb', [0]);
		$track->set(fader => $id);
	}

	
	# add linear envelope controller -klg if needed
	
	refresh_fade_controller($track);
	$object
	
}

sub refresh_fade_controller {
	my $track = shift;
	if( $track->fader and my ($old) = @{$::cops{$track->fader}{owns}})
		{ remove_effect($old) }
	::Text::add_ctrl($track->fader, 'klg',1,$off_level,0,fader_envelope_pairs($track->name));
}

sub fades {
	my $track_name = shift;
	(grep{ $_->track eq $track_name } values %by_index)
}



sub fader_envelope_pairs {
	# return number_of_pairs, pos1, val1, pos2, val2,...
	my $track_name = shift;
	my @fades = fades($track_name);

	my @specs;
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
		push @specs, [$marktime1, $marktime2, $fade->type];
	}
	# sort fades
	@specs = sort{ $a->[0] <=> $b->[0] } @specs;

	# prepend number of pairs, flatten list
	my @pairs = map{ spec_to_pairs($_) } @specs;
	unshift @pairs, scalar @pairs;
	@pairs;
}
		
sub spec_to_pairs {
	my ($from, $to, $type) = @{$_[0]};
	say "from: $from, to: $to, type: $type";
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

