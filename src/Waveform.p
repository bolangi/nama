package ::Waveform;
use ::Globals qw($project $config $gui $ui %ti);
use ::Util qw(join_path);
use v5.36;
use Image::Size qw(imgsize);
our $VERSION = 1.0;
use Try::Tiny;
use vars qw(%by_name);
use ::Object qw(wav track project start end);

# Each WAV has one waveform image, named by appending .png to its path.
# WAV files are immutable in Nama, so an existing image is reused unless
# its dimensions differ from the current waveform configuration.

sub new {
	my $class = shift;
	my %args = @_;
	bless \%args, $class	
}

sub waveform_name { "$_[0].png" }

sub waveforms_enabled {
	$config->{display_waveform}
		&& ref($ui)
		&& $ui->isa('::Graphical');
}

sub desired_dimensions {
	my ($wav, $options) = @_;
	my $pixels_per_second = $options->{pixels_per_second}
		// $config->{waveform_pixels_per_second};
	my $height = $options->{height} // $config->{waveform_height};
	my $width = int(::wav_length($wav) * $pixels_per_second);
	($width, $height);
}

sub image_has_dimensions {
	my ($png, $wanted_width, $wanted_height) = @_;
	return unless -f $png;
	my ($width, $height) = imgsize($png);
	defined $width && defined $height
		&& $width == $wanted_width && $height == $wanted_height;
}

sub generate_waveforms {
	return unless waveforms_enabled();
	my $options = ref $_[0] eq 'HASH' ? shift : {};
	my %seen;
	for my $wav (grep { defined && -f && !$seen{$_}++ } @_){
		my ($width, $height) = desired_dimensions($wav, $options);
		next unless $width > 0 && $height > 0;
		my $png = waveform_name($wav);
		next if !$options->{force}
			&& image_has_dimensions($png, $width, $height);

		my @cmd = ('waveform', '-F', '-b', '#ffffff', '-c', '#ff0000',
			'-W', $width, '-H', $height, $wav, $png);
		::terminal_say(join ' ', @cmd);
		system @cmd;
		my $status = $?;
		next if image_has_dimensions($png, $width, $height);

		my ($actual_width, $actual_height) = -f $png
			? imgsize($png)
			: ();
		my $actual = defined $actual_width
			? "$actual_width x $actual_height"
			: 'no readable PNG';
		::throw("waveform generation failed (status $status; ",
			"expected $width x $height; got $actual): @cmd");
	}
}

sub get_waveform {
	my $self = shift;
	my $wav = $self->track->full_path;
	generate_waveforms($wav);
	my $png = waveform_name($wav);
	my ($width, $height) = desired_dimensions($wav, {});
	image_has_dimensions($png, $width, $height) ? $png : undef;
}
sub display {
	my $self = shift;
	my $waveform = $self->get_waveform or return;
	my $widget = $gui->{ww}->Photo(-format => 'png', -file => $waveform);
	# Keep the Photo object alive for as long as the canvas uses the image.
	$gui->{waveform}{$self->track->name} = $widget;
	$gui->{wwcanvas}->createImage(	0,
												$self->y_offset_multiplier * $config->{waveform_height}, 
												-anchor => 'nw', 
												-tags => ['waveform', $self->track->name],
												-image => $widget);
	my ($width, $height) = ::wh($gui->{ww});
	my $name_x = $width - 150;
	my $name_y = $config->{waveform_height} * $self->y_offset_multiplier  + 20;
	$gui->{wwcanvas}->createText( $name_x, $name_y, -font =>
'lucidasanstypewriter-bold-14', -text => uc($self->track->name) . ' - '.$self->track->current_wav);
}
sub width  {
	my $self = shift;
	my $waveform = $self->get_waveform or return;
	my ($width) = imgsize($waveform);
	$width
}
sub height  {
	my $self = shift;
	my $waveform = $self->get_waveform or return;
	my (undef, $height) = imgsize($waveform);
	$height
}
sub pixels_per_second  {
	$config->{waveform_pixels_per_second}
}
sub y_offset_multiplier {
	my $self = shift;
	my $before_me;
	for (2 .. $self->track->n - 1){
		$before_me++ if $ti{$_} and $ti{$_}->candidate_play;
	}
	$before_me
}

1 # obligatory
	
__END__
=begin comment
Usage: waveform [options] source_audio [ouput.png]
    -W, --width WIDTH                Width (in pixels) of generated waveform image -- Default 1800.
    -H, --height HEIGHT              Height (in pixels) of generated waveform image -- Default 280.
    -c, --color COLOR                Color (hex code) to draw the waveform. Can also pass 'transparent' to cut it out of the background -- Default #00ccff.
    -b, --background COLOR           Background color (hex code) to draw waveform on -- Default #666666.
    -m, --method METHOD              Wave analyzation method (can be 'peak' or 'rms') -- Default 'peak'.
    -q, --quiet                      Don't print anything out when generating waveform
    -F, --force                      Force generationg of waveform if file exists
    -h, --help                       Display this screen

=end comment
	
=cut
