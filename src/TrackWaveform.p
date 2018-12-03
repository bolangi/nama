package ::TrackWaveform;
use ::Globals qw($project $config $gui %ti);
use Modern::Perl;
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
