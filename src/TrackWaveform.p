package ::TrackWaveform;
use ::Globals qw($project);
use Modern::Perl;
use Role::Tiny;
use Try::Tiny;
sub gen_waveform {
	my $self = shift;
	my ($width, $height) = @_;
	my $name = waveform_name($self->full_path, $width, $height);
	my $cmd = join ' ', 'waveform', "-W $width -H $height", $self->full_path, $name;
	say $cmd;
	system($cmd);
	$project->{waveform}->{$self->full_path} = $name;
}
sub waveform_name {
	my($path, $width, $height) = @_;
			$path . '.' . $width .'x' . "$height.png"
}


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

