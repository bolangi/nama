package ::TrackWaveform;
use ::Globals qw($project $config $gui %ti);
use Modern::Perl;
use Role::Tiny;
use Try::Tiny;

# files are of the form # sax_1.wav.1200x200-10.png 
# where the numbers correspond to width and height in pixels of the audio
# waveform image, and the x-scaling in pixels per second (default 10)

sub generate_waveform {
	my $self = shift;
	my ($width, $height, $pixels_per_second) = @_;
	$pixels_per_second //= $config->{waveform_pixels_per_second};
	$height //= $config->{waveform_height};
	$width //= int( $self->wav_length * $pixels_per_second);
	my $name = waveform_name($self->full_path, $width, $height, $pixels_per_second);
	my $cmd = join ' ', 'waveform', "-b #c2d6d6 -c #0080ff -W $width -H $height", $self->full_path, $name;
	say $cmd;
	system($cmd);
	$name;
}
sub waveform_name {
	my($path, $width, $height, $pixels) = @_;
			"$path."  . $width . 'x' . "$height-$pixels.png"
}

sub find_waveform {

	my $self = shift;
	my $match = shift() // '*';
	my @files = File::Find::Rule->file()
	 ->name( $self->current_wav . ".$match.png"  )
	 ->in(   ::this_wav_dir()      );
	@files;
}
sub get_waveform {
	my $self = shift;
	my ($waveform) = $self->find_waveform; 
	$waveform or $self->generate_waveform; 
}
sub display_waveform {
	my $self = shift;
	my ($waveform) = $self->get_waveform; 
	my $widget = $gui->{ww}->Photo(-format => 'png', -file => $waveform);
	$gui->{waveform}{$self->name} = [];
	$gui->{wwcanvas}->createImage(	0,
												$self->y_offset_multiplier * $config->{waveform_height}, 
												-anchor => 'nw', 
												-tags => ['waveform', $self->name],
												-image => $widget);
	my ($width, $height) = ::wh($gui->{ww});
	my $name_x = $width - 150;
	my $name_y = $config->{waveform_height} * ($self->y_offset_multiplier + 1) - 10;
	say "x pos $name_x, y pox $name_y";
	#$gui->{wwcanvas}->createText( $name_x, $name_y, -text => $waveform);
}
=comment
sub waveform_width  {
	my $self = shift;
	my ($waveform) = $self->find_waveform; 
	my ($width, $height, $pixels_per_second) = $waveform =~ /(\d+)x(\d+)-(\d+)/
		or ::throw("cannot parse waveform filename: $waveform");
	say "wdith $width, height $height, pixels: $pixels_per_second";
	$width
}
sub waveform_height  {
	my $self = shift;
	my ($waveform) = $self->find_waveform; 
	my ($width, $height, $pixels_per_second) = $waveform =~ /(\d+)x(\d+)-(\d+)/
		or ::throw("cannot parse waveform filename: $waveform");

	say "wdith $width, height $height, pixels: $pixels_per_second";
	$height
}
sub waveform_pixels_per_second  {
	my $self = shift;
	my ($waveform) = $self->find_waveform; 
	my ($width, $height, $pixels_per_second) = $waveform =~ /(\d+)x(\d+)-(\d+)/
		or ::throw("cannot parse waveform filename: $waveform");
	say "wdith $width, height $height, pixels: $pixels_per_second";
	$pixels_per_second
}
=cut
sub y_offset_multiplier {
	my $self = shift;
	my $before_me;
	for (2 .. $self->n - 1){
		$before_me++ if $ti{$_} and $ti{$_}->find_waveform
	}
	$before_me
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

