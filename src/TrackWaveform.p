package ::TrackWaveform;
use ::Globals qw($project $config $gui %ti);
use v5.36;
our $VERSION = 1.0;
use Role::Tiny;
use Try::Tiny;

sub waveform {
	my $self = shift;
	::Waveform->new( 	project => $self->project, 
						wav     => $self->current_wav,
						start   => $self->startpoint,
						end     => $self->endpoint,
						track	=> $self,
	);
}


1 # obligatory
	
__END__
