package ::TrackWaveform;
use ::Globals qw($project);
use Modern::Perl;
use Role::Tiny;
use Try::Tiny;

# files are assumed to be of the form # sax_1.wav.1200x200.10.png 
# where the numbers correspond to width and height in pixels of the audio
# waveform image, and the x-scaling in pixels per second (default 10)

sub generate_waveform {
	my $self = shift;
	my ($width, $height, $pixels_per_second) = @_;
	$width //= $self->wav_length * $project->{current_waveform_timescale};
	my $name = waveform_name($self->full_path, $width, $height, $pixels_per_second);
	my $cmd = join ' ', 'waveform', "-W $width -H $height", $self->full_path, $name;
	say $cmd;
	system($cmd);
	$project->{waveform}->{$self->full_path} = $name;
}
sub waveform_name {
	my($path, $width, $height, $pixels) = @_;
			"$path."  . $width . 'x' . "$height.$pixels.png"
}

sub find_waveform {

	my $self = shift;
	my $match = shift() // '*';
	my @files = File::Find::Rule->file()
	 ->name( $self->current_wav . ".$match.png"  )
	 ->in(   ::this_wav_dir()      );
	@files;
}
sub refresh_waveform {
	my $self = shift;
	my ($waveform) = $self->find_waveform() || $self->generate_waveform; 
	$project->{$self->name}->{waveform}->{current} = $waveform;
	# remove Tk::Photo widget with waveform image
    # load    " 	
}

#3m song, 2400 pixels
#new_version_length_pixels = $length *  $project->{current_waveform_timescale}
#allow user to choose timescale
#$project->{current_waveform_timescale}
#$project->{available_timescales}



1 # obligatory
	
__END__
=comment
Usage: waveform [options] source_audio [ouput.png]
    -W, --width WIDTH                Width (in pixels) of generated waveform image -- Default 1800.
    -H, --height HEIGHT              Height (in pixels) of generated waveform image -- Default 280.
    -c, --color COLOR                Color (hex code) to draw the waveform. Can also pass 'transparent' to cut it out of the background -- Default #00ccff.
    -b, --background COLOR           Background color (hex code) to draw waveform on -- Default #666666.
    -m, --method METHOD              Wave analyzation method (can be 'peak' or 'rms') -- Default 'peak'.
    -q, --quiet                      Don't print anything out when generating waveform
    -F, --force                      Force generationg of waveform if file exists
    -h, --help                       Display this screen
	
=cut

