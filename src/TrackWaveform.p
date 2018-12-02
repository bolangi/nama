package ::TrackWaveform;
use ::Globals qw($project $config $gui %ti);
use Modern::Perl;
use Role::Tiny;
use Try::Tiny;

# files are of the form # sax_1.wav.1200x200-10.png 
# where the numbers correspond to width and height in pixels of the audio
# waveform image, and the x-scaling in pixels per second (default 10)

sub waveform {
	my $self = shift;
	::Waveform->new( 	project => $self->project, 
						wav     => $self->current_wav,
						start   => $self->region_start_time,
						end     => $self->region_end_time,
	);
}


1 # obligatory
	
__END__
