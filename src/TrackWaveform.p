package ::TrackWaveform;
use ::Globals qw($project $config $gui %ti);
use Modern::Perl '2020';
our $VERSION = 1.0;
use Role::Tiny;
use Try::Tiny;

sub waveform {
	my $self = shift;
	::Waveform->new( 	project => $self->project, 
						wav     => $self->current_wav,
						start   => $self->region_start_time,
						end     => $self->region_end_time,
						track	=> $self,
	);
}


1 # obligatory
	
__END__
