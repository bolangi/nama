## Note on object model
# 
# All graphic method are defined in the base class :: .
# These are overridden in the ::Text class with no-op stubs.
# 
# So all the routines in Graphical_methods.pl can consider
# themselves to be in the base class, with access to all
# variables and subs that are imported.

package ::;
use 5.008;
use Carp;
use Cwd;
use Storable; 
use Getopt::Std;
use Audio::Ecasound;
use Parse::RecDescent;
use Term::ReadLine;
use Data::YAML;
use File::Find::Rule;
use File::Spec;
use File::Spec::Link;
use File::Temp;
use File::Path;
use IO::All;
use Event;
use Module::Load::Conditional qw(can_load); 
# use Timer::HiRes; # select
# use Tk;           # loaded conditionally
use strict;
use warnings;
no warnings qw(uninitialized syntax);

BEGIN{ 

our $VERSION = '0.997';

[% qx(cat ./banner.pl) %]

}

# use Tk    # loaded conditionally in GUI mode

#use Tk::FontDialog;


$| = 1;     # flush STDOUT buffer on every write

## Definitions ##


# 'our' declaration: all packages in the file will see the following
# variables. 

[% qx(cat ./declarations.pl) %] 

[% qx(cat ./var_types.pl) %]

# instances needed for yaml_out and yaml_in

$yw = Data::YAML::Writer->new; 
$yr = Data::YAML::Reader->new;

$debug2 = 0; # subroutine names
$debug = 0; # debug statements

## The names of helper loopback devices:

$loopa = 'loop,111';
$loopb = 'loop,222';
$loop_crossover = 'loop,120';
$loop_boost = 'loop,130';

# other initializations
$unit = 1;
$effects_cache_file = '.effects_cache';
$palette_file = 'palette.yml';
$state_store_file = 'State.yml';
$chain_setup_file = 'Setup.ecs'; # For loading by Ecasound
$tk_input_channels = 10;
$use_monitor_version_for_mixdown = 1; # not implemented yet
$project_root = join_path( $ENV{HOME}, "nama");
$seek_delay = 0.1; # seconds
$prompt = "nama ('h' for help)> ";
$use_pager = 1;
$use_placeholders = 1;
$save_id = "State";
$fade_time = 0.3;
#$SIG{INT} = sub{ mute{$tn{Master}} if engine_running(); die "\nAborting.\n" };
$old_snapshot = {};

jack_update(); # to be polled by Event
$memoize = 0;


## Load my modules

use ::Assign qw(:all);
use ::Track;
use ::Bus;    
use ::Mark;

package ::Wav;
memoize('candidates') if $::memoize;
package ::;

# aliases for concise access

*tn = \%::Track::by_name;
*ti = \%::Track::by_index;

# $ti{3}->rw

# print remove_spaces("bulwinkle is a...");

## Class and Object definitions for package '::'

our @ISA; # no anscestors
use ::Object qw(mode);

## The following methods belong to the root class

sub hello {"superclass hello"}

sub new { my $class = shift; return bless {@_}, $class }

[% qx(cat ./Core_subs.pl ) %]

[% qx(cat ./Graphical_subs.pl ) %]

[% qx(cat ./Refresh_subs.pl ) %]

## The following code loads the object core of the system 
## and initiates the chain templates (rules)

use ::Track;   

package ::Graphical;  ## gui routines

our @ISA = '::';      ## default to root class

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub install_handlers{};
sub loop {
    package ::;
    #MainLoop;
    $term = new Term::ReadLine("Ecasound/Nama");
	my $attribs = $term->Attribs;
	$attribs->{attempted_completion_function} = \&complete;
	$term->tkRunning(1);
    $OUT = $term->OUT || \*STDOUT;
	while (1) {
    my ($user_input) = $term->readline($prompt) ;
	next if $user_input =~ /^\s*$/;
     $term->addhistory($user_input) ;
	command_process( $user_input );
	}
}

## The following methods belong to the Text interface class

package ::Text;
our @ISA = '::';
use Carp;

sub hello {"hello world!";}

[% qx(cat ./Text_methods.pl ) %]

## NO-OP GRAPHIC METHODS 

no warnings qw(redefine);
sub init_gui {}
sub transport_gui {}
sub group_gui {}
sub track_gui {}
sub preview_button {}
sub create_master_and_mix_tracks {}
sub time_gui {}
sub refresh {}
sub refresh_group {}
sub refresh_track {}
sub flash_ready {}
sub update_master_version_button {}
sub update_version_button {}
sub paint_button {}
sub refresh_oids {}
sub project_label_configure{}
sub length_display{}
sub clock_display {}
sub clock_config {}
sub manifest {}
sub global_version_buttons {}
sub destroy_widgets {}
sub destroy_marker {}
sub restore_time_marks {}
sub show_unit {}
sub add_effect_gui {}
sub remove_effect_gui {}
sub marker {}
sub initialize_palette {}
sub save_palette {}
sub paint_mute_buttons {}
sub remove_track_gui {}

package ::;

### COMMAND LINE PARSER 

$debug2 and print "Reading grammar\n";

$commands_yml = <<'YML';
[% qx(./strip_all  ./commands.yml) %]
YML

$cop_hints_yml = <<'YML';
[% qx(cat ./ecasound_chain_operator_hints.yml) %];
YML

%commands = %{ ::yaml_in( $::commands_yml) };

$::AUTOSTUB = 1;
$::RD_TRACE = 1;
$::RD_ERRORS = 1; # Make sure the parser dies when it encounters an error
$::RD_WARN   = 1; # Enable warnings. This will warn on unused rules &c.
$::RD_HINT   = 1; # Give out hints to help fix problems.

$grammar = q(

[% qx(./strip_all  ./grammar_body.pl) %]

[% qx(./emit_command_headers headers) %]
);

$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";

[% qx(cat ./help_topic.pl) %]

# we use the following settings if we can't find config files

$default = <<'FALLBACK_CONFIG';
[% qx(cat ./namarc) %]
FALLBACK_CONFIG

1;
__END__

=head1 NAME

B<Audio::Ecasound::Multitrack> - Perl extensions for multitrack audio processing

B<Nama> - Lightweight multitrack recorder/mixer

=head1 SYNOPSIS

B<nama> [I<options>] [I<project_name>]

=head1 DESCRIPTION

B<Audio::Ecasound::Multitrack> provides class libraries for
tracks and buses, and a track oriented user interface for managing 
runs of the Ecasound audio-processing engine.

B<Nama> is a lightweight recorder/mixer application that
configures Ecasound as a single mixer bus.

By default, Nama starts up a GUI interface with a command
line interface running in the terminal window. The B<-t>
option provides a text-only interface for console users.

=head1 OPTIONS

=over 12

=item B<-d> F<project_root>

Use F<project_root> as Nama's top-level directory.

=item B<-f> F<config_file>

Use F<config_file> instead of default F<.namarc>

=item B<-g>

GUI/text mode (default)

=item B<-t>

Text-only mode

=item B<-c>

Create the named project

=item B<-a>

Save and reload ALSA mixer state using alsactl

=item B<-m>

Don't load saved state

=back

=head1 CONTROLLING ECASOUND

Ecasound is configured through use of I<chain setups>.
Chain setups are central to controlling Ecasound.  
Nama generates appropriate chain setups for 
recording, playback, and mixing covering a 
large portion of Ecasound's functionality.

Commands for audio processing with Nama/Ecasound fall into
two categories: I<static commands> that influence the chain
setup and I<dynamic commands> that influence the realtime
behavior of the audio processing engine.

=head2 STATIC COMMANDS

Setting the REC/MON/OFF status of a track by the
C<rec>/C<mon>/C<off> commands, for example,
determine whether that track will be included next time the
transport is armed, and whether the corresponding audio
stream will be recorded to a file or played back from an
existing file. Other static commands include C<loop_enable>
and C<stereo>/C<mono> which select track width.

=head2 CONFIGURING THE ENGINE

The C<arm> command generates an Ecasound chain setup based
on current settings and uses it to configure the audio
processing engine.  Remember to issue this command as the
last operation before starting the engine. This will help
ensure that the processing run accomplishes what you intend.

=head2 DYNAMIC COMMANDS

Once a chain setup is loaded and the engine launched,
another subset of commands controls the audio processing
engine. Commonly used I<dynamic commands> include C<start>
and C<stop>;  C<forward>, C<rewind> and C<setpos> commands
for repositioning the playback head; and C<vol> and C<pan>
for adjusting effect parameters.  Effect parameters may be
adjusted at any time. Effects may be added  audio
processing, however the additional latency will cause an
audible click.

=head1 DIAGNOSTICS

Once a chain setup has generated by the C<arm> commands, it
may be inspected with the C<chains> command.  The C<showio>
command displays the data structure used to generate the
chain setup. C<dump> displays data for the current track.
C<dumpall> shows the state of most program objects and
variables (identical to the F<State.yml> file created by the
C<save> command.)

=head1 Tk GRAPHICAL UI 

Invoked by default, the Tk interface provides all
functionality on two panels, one for general control, the
second for effects. 

Logarithmic sliders are provided automatically for effects
with hinting. Text-entry widgets are used to enter
parameters for effects where hinting is not available.

After issuing the B<arm> or B<connect> commands, the GUI
title bar and time display change color to indicate whether
the upcoming operation will include live recording (red),
mixdown only (yellow) or playback only (green).  Live
recording and mixdown can take place simultaneously.

The text command prompt appears in the terminal window
during GUI operation. Text commands may be issued at any
time.

=head1 TEXT UI

Press the I<Enter> key if necessary to get the following command prompt.

=over 12

C<nama ('h' for help)E<gt>>

=back

You can enter Nama and Ecasound commands directly, Perl code
preceded by C<eval> or shell code preceded by C<!>.

Multiple commands on a single line are allowed if delimited
by semicolons. Usually the lines are split on semicolons and
the parts are executed sequentially, however if the line
begins with C<eval> or C<!> the entire line will be given to
the corresponding interpreter.

You can access command history using up-arrow/down-arrow.

Type C<help> for general help, C<help command> for help with
C<command>, C<help foo> for help with commands containing
the string C<foo>. C<help_effect foo bar> lists all 
plugins/presets/controller containing both I<foo> and
I<bar>. Tab-completion is provided for Nama commands, Ecasound-iam
commands, plugin/preset/controller names, and project names.

=head1 TRACKS

Ecasound deals with audio processing at
the level of devices, files, and signal-processing
chains. Nama implements tracks to provide a
level of control and convenience comparable to 
many digital audio workstations.

Each track has a descriptive name (i.e. vocal) and an
integer track-number assigned when the track is created.

=head2 VERSION NUMBER

Multiple WAV files can be recorded for each track. These are
identified by a version number that increments with each
recording run, i.e. F<sax_1.wav>, F<sax_2.wav>, etc.  All
files recorded at the same time have the same version
numbers. 

Version numbers for playback can be selected at the group
or track level. By setting the group version number to 5,
you can play back the fifth take of a song, or perhaps the
fifth song of a live recording session. 

The track's version setting, if present, overrides 
the group setting. Setting the track version to zero
restores control of the version number to the default
group setting.

=head2 REC/MON/OFF

REC/MON/OFF status is used to generate the chain setup
for an audio processing run.

Each track, including Master and Mixdown, has its own
REC/MON/OFF setting and displays its own REC/MON/OFF status.
The Tracker group, which includes all user tracks, also has
REC, MON and OFF settings. These provides a convenient way
to control the behavior of all user tracks.

As the name suggests, I<REC> status indicates that a track
is ready to record a WAV file. You need to set both track and
group to REC to source an audio stream from JACK or the
soundcard.

I<MON> status indicates an audio stream available from disk.
It requires a MON setting for the track or group as well as
the presence of file with the selected version number.
A track set to REC with no audio stream available with
default to MON status.

I<OFF> status means that no audio is available for the track
from any source.  A track with no recorded WAV files 
will show OFF status, even if set to MON.

An OFF setting for the track or group always results in OFF
status. A track with OFF status will be excluded from the
chain setup. (This setting is distinct from the action of
the C<mute> command, which sets the volume of the track to
zero.)

All user tracks belong to the Tracker group, which has a
group REC/MON/OFF setting and a default version setting for
the entire group.
 
Setting the group to MON (C<group_monitor> or C<gmon>)
forces user tracks with a REC setting to MON status if a WAV
file is available to play, or OFF status if no audio stream
is available. 

The group MON mode triggers automatically after a recording
has created new WAV files.

The group OFF setting (text command B<group_off>)
excludes all user tracks from the chain setup, and is
typically used when playing back mixdown tracks.  The
B<mixplay> command sets the Mixdown track 
to MON and the Tracker group to OFF.

The Master bus has only MON/OFF status. Setting REC status
for the Mixdown bus has the same effect as issuing the
B<mixdown> command. (A C<start> command must be issued for
mixdown to commence.)

=head2 REGIONS

The C<region> command allows you to define endpoints
for a portion of an audio file. Use the C<shift> command
to specify a delay for starting playback.

Only one region may be specified per track.  Use the
C<link_track> command to clone a track in order to make use
of multiple regions or versions of a single track. 

C<link_track> can clone tracks from other projects.
Thus you could create the sections of a song in 
separate projects, then assemble them using
C<link_track> to pull the Mixdown tracks
into a single project for mastering.

=head1 ROUTING

Nama identifies tracks by both a name and a number. The
track number is used to identify corresponding Ecasound
signal-processing chains.

=head2 Raw, cooked and mixed signals

Nama's signal flow is organized at three levels: raw, cooked
and mixed. 

"Raw" signals are the inputs to user tracks. Raw signals can
come from the soundcard, a WAV file, or a JACK client.

"Cooked" signals are the output of user tracks after volume,
pan and effects processing.

The "mixed" signal is the combined outputs of all user
tracks. It is delivered to the Master fader, and to the
Mixdown WAV file during mixdown.

=head2 Loop devices

Nama uses Ecasound loop devices to be able to deliver each
of these signals classes to multiple "customers", i.e.  to
other chains using that signal as input.

An optimizing pass eliminates loop devices that have 
only one customer for the signal they provide.

=head2 Flow diagrams

Let's examine the signal flow from track 3, the first 
available user track. Assume track 3 is named "sax".
All effects for track 3 are applied to chain 3.

We will divide the signal flow into track and mixer
sections.  Parentheses indicate chain identifiers or the
corresponding track name.

All "cooked" signals (i.e. the outputs of each
user track) terminate at loop,111.

=head3 Track, REC status

    Sound device   --+---(3)----> loop,3 ---(J3)----> loop,111
      /JACK client   |
                     +---(R3)---> sax_1.wav

REC status indicates that the source of the signal
is the soundcard or JACK client. The input signal will be 
written directly to a file except in the preview and doodle 
modes.


=head3 Track, MON status

    sax_1.wav ------(3)----> loop,3 ----(J3)----> loop,111

=head3 Mixer, with mixdown enabled

In the second part of the flow graph, the mixed signal is
delivered to an output device through the Master chain,
which can host additional effects. The Mixdown track
can also host effects, however these should be used
during playback only.

    loop,111 --(MixLink)---> loop,222 --(1/Master)---> Sound device
                                 |
                                 +------(2/Mixdown)--> Mixdown_1.wav

=head3 Mastering Mode

In mastering mode, the MixLink chain is replaced by several
tracks.  Effects and default parameters for these tracks 
may be defined in the configuration file F<.namarc>.
The intermediate loops devices loop,120 and loop,130
are not shown.

                         +---(Low)---+ 
                         |           |
    loop,111 ----(Eq)--> +---(Mid)---+---(Boost)--> loop,222
                         |           |
                         +---(High)--+ 

The B<Eq> track provides an equalizer.

The B<Low>, B<Mid> and B<High> tracks each apply a bandpass
filter, a compressor and a spatialiser.

The B<Boost> track applies gain and a limiter.

=head1 TEXT COMMANDS

[% qx(./emit_command_headers pod) %]


=head1 BUGS AND LIMITATIONS

Several of Nama's advanced functions are available only through
text commands.

Unneeded GUI volume and pan controls are provided for 
mastering mode tracks. Only the volume control for the 
Boost track is meaningful.

You should not use track names Eq, Low, Mid, High or Boost
if you intend to use the mastering mode.

Positions are currently specified in seconds only.

=head1 EXPORT

None by default.

=head1 AVAILABILITY

CPAN, for the distribution.

cpan Audio::Ecasound::Multitrack

You will also need to install Tk to use the GUI:

cpan Tk

You can pull the source code as follows: 

C<git clone git://github.com/bolangi/nama.git>

Build instructions are contained in the F<README> file.

=head1 AUTHOR

Joel Roth, E<lt>joelz@pobox.comE<gt>
