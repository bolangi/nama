## Note on object model
# 
# All graphic method are defined in the base class :: .
# These are overridden in the ::Text class with no-op stubs.
# 
# So all the routines in Graphical_methods.pl can consider
# themselves to be in the base class, with access to all
# variables and subs that are imported.

package ::;
use 5.10.0;
use feature ":5.10";
use strict;
use warnings;
#use Carp::Always;
no warnings qw(uninitialized syntax);
use autodie qw(:default);
use Carp;
use Cwd;
use Data::YAML;
use Event;
use File::Find::Rule;
use File::Path;
use File::Spec;
use File::Temp;
use Getopt::Std;
use IO::All;
use IO::Socket; 
use Module::Load::Conditional qw(can_load); 
use Parse::RecDescent;
use Storable; 
use Term::ReadLine;
use Graph;

# use Timer::HiRes; # automatically detected

use File::Spec::Link;

# use Tk;           # loaded conditionally

use vars qw($VERSION);
BEGIN{ 

$VERSION = '0.9982';

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
$main_out = 1; # enable main output

jack_update(); # to be polled by Event
$memoize = 0;

@mastering_track_names = qw(Eq Low Mid High Boost);

$term = new Term::ReadLine("Ecasound/Nama");

## Load my modules

use ::Assign qw(:all);
use ::Track;
use ::Bus;    
use ::Mark;
use ::IO;
use ::Graph;

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
	my $attribs = $term->Attribs;
	$attribs->{attempted_completion_function} = \&complete;
	$term->tkRunning(1);
    $OUT = $term->OUT || \*STDOUT;
	while (1) {
		my ($user_input) = $term->readline($prompt) ;
		process_line( $user_input );
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
sub init_palette {}
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

$default_palette_yml = <<'PALETTE';
[% qx(cat ./palette.yml) %]
PALETTE

1;
__END__

=head1 NAME

B<Audio::Nama> - Perl extensions for multitrack audio processing

B<Nama> - Lightweight recorder, mixer and mastering system

=head1 SYNOPSIS

B<nama> [I<options>] [I<project_name>]

=head1 DESCRIPTION

B<Nama> is a lightweight recorder/mixer application using
Ecasound in the back end to provide effects processing,
cut-and-paste, mastering, and other functions typically
found in digital audio workstations.

By default, Nama starts up a GUI interface with a command
line interface running in the terminal window. The B<-t>
option provides a text-only interface for console users.

=head1 OPTIONS

=over 12

=item B<-d> F<project_root>

Use F<project_root> as Nama's top-level directory.

=item B<-D> 

Output debugging information

=item B<-f> F<config_file>

Use F<config_file> instead of default F<.namarc>

=item B<-g>

GUI mode (default)

=item B<-t>

Text-only mode

=item B<-c>

Create the specified project if necessary

=item B<-a>

Save and reload ALSA mixer state using alsactl

=item B<-m>

Don't load saved state

=item B<-n>

Communicate with engine via NetECI. Start Ecasound in
server mode if necessary.

=item B<-l>

Communicate with engine via libecasoundc (default, if
Audio::Ecasound is installed)

=back

=head1 CONTROLLING NAMA/ECASOUND

Ecasound is configured through use of I<chain setups>.
Nama generates appropriate chain setups for 
recording, playback, mixing, mastering
and bus routing.

Commands for audio processing with Nama/Ecasound fall into
two categories: I<static commands> that influence the chain
setup and I<dynamic commands> that influence the realtime
behavior of the audio processing engine.

=head2 STATIC COMMANDS

Static commands affect I<future> runs of the audio
processing engine. For example, B<rec, mon> and B<off>
determine whether the current track will get its audio
stream from a live source or whether an existing WAV file will be
played back. Nama responds to static commands by reconfiguring the
engine as necessary by generating and loading chain setup
files.

=head2 DYNAMIC COMMANDS

Once a chain setup is loaded and the engine launched,
another subset of commands controls the realtime behavior of
the audio processing engine. Commonly used I<dynamic
commands> include transport C<start> and C<stop>; playback
head repositioning commands such C<forward>,
C<rewind> and C<setpos>; and C<vol> and C<pan> for adjusting effect
parameters. Effects can be added during audio processing,
however this action may be accompanied by an audible click.

=head2 CONFIGURATION

General configuration of sound devices and program options
is performed by editing the file F<.namarc>. Nama
automatically generates this well-commented file on the
program's first run, usually placing it in the user's home
directory.

=head1 DIAGNOSTICS

By inspecting the current chain setup with the C<chains>
command, one can easily determine if the audio engine is
properly configured. (It is much easier to read these setups
than to write them!) The C<showio> command displays the data
structure used to generate the chain setup. C<dump> displays
data for the current track.  The C<dumpall> command shows
the state of most program objects and variables using the
same format as the F<State.yml> file created by the
C<save> command.

=head1 Tk GRAPHICAL UI 

Invoked by default, the Tk interface provides all
functionality on two panels, one for general control, the
second for effects. 

Nama detects and uses plugin hints for 
parameter range and use of logarithmic scaling.
Text-entry widgets are used to enter values 
for plugins without hinted ranges.

The GUI project name bar and time display change color to indicate
whether the upcoming operation will include live recording
(red), mixdown only (yellow) or playback only (green).  Live
recording and mixdown can take place simultaneously.

The text command prompt appears in the terminal window
during GUI operation, and text commands may be issued at any
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

Ecasound deals with audio processing at the level audio and
loop devices, files, and signal-processing chains. Nama
provides tracks, buses, marks and other high-level
abstractions. Chief among these are tracks.
 
Each track has a descriptive name (i.e. vocal) and an
integer track-number assigned when the track is created.
The following paragraphs describes track fields and
settings.

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

The track version setting, if present, overrides 
the group setting. Setting the track version to zero
restores control of the version number to the 
group setting.

=head2 REC/MON/OFF

Track REC/MON/OFF status guides audio processing.

Each track, including Master and Mixdown, has its own
REC/MON/OFF setting and displays its own REC/MON/OFF status.
The Main group, which includes all user tracks, also has
REC, MON and OFF settings that influence the behavior of all
user tracks.

As the name suggests, I<REC> status indicates that a track
is ready to record a WAV file. You need to set both track and
group to REC to source an audio stream from JACK or the
soundcard. 

I<MON> status indicates an audio stream available from disk.
It requires a MON setting for the track or group as well as
the presence of a file with the selected version number.  A
track set to REC with no live input will default to MON
status.

I<OFF> status means that no audio is available for the track
from any source.  A track with no recorded WAV files 
will show OFF status, even if set to MON.

An OFF setting for a track or group always results in OFF
status, causing the track to be excluded from the
chain setup. I<Note: This setting is distinct from the action of
the C<mute> command, which sets the volume of the track to
zero.>

Newly created user tracks belong to the Main group, which
goes through a mixer and Master fader track to the 
soundcard for monitoring.

=head2 REGIONS

The C<region> command allows you to define endpoints
for a portion of an audio file. Use the C<shift> command
to specify a delay for starting playback.

Only one region may be specified per track.  Use the
C<link_track> command to clone a track in order to make use
of multiple regions or versions of a single track. 

C<link_track> can clone tracks from other projects.  Thus
you could create the sections of a song in separate
projects, then assemble them using C<link_track> to pull the
Mixdown tracks into a single project.

=head2 GROUPS

Track groups are used internally.  The Main group
corresponds to a mixer. It has its own REC/MON/OFF setting
that influences the rec-status of individual tracks. 

When the group is set to OFF, all tracks are OFF. When the
group is set to MON, track REC settings are forced to MON.
When the group is set to REC, tracks can be any of REC, MON
or OFF.  and a default version setting for the entire group.
The

The group MON mode triggers automatically after a recording
run.

The B<mixplay> command sets the Mixdown track to MON and the
Main group to OFF.

The Master bus has only MON/OFF status. 

=head2 BUNCHES

A bunch is just a list of track names. Bunch names are used
with C<for> to apply one or more commands to to several
tracks at once. A group name can also be treated as a bunch
name.

=head2 BUSES

Nama uses buses internally, and provides two kinds of
user-defined buses. 

B<Send buses> can be used as instrument monitors,
or to send pre- or post-fader signals from multiple
user tracks to an external program such as jconv.

B<Sub buses> enable multiple tracks to be routed through a
single track for vol/pan/effects processing before reaching
the mixer.

	add_sub_bus Strings
	add_tracks violin cello bass
	for violin cello bass; set bus Strings
	Strings vol - 10  # adjust bus output volume


=head1 ROUTING

Nama commands can address tracks by both a name and a
number. In Ecasound chain setups, only the track
number is used. 

=head2 Loop devices

Nama uses Ecasound loop devices to be able to deliver each
of these signals classes to multiple "customers", i.e.  to
other chains using that signal as input.

An optimizing pass eliminates loop devices that have 
only one signal outputs. The following diagrams show
the unoptimized routing.

=head2 Flow diagrams

Let's examine the signal flow from track 3, the first 
available user track. Assume track 3 is named "sax".

We will divide the signal flow into track and mixer
sections.  Parentheses indicate chain identifiers or the
corresponding track name.

The stereo outputs of each user track terminate at loop,mix.

=head3 Track, REC status

    Sound device   --+---(3)----> loop,3 ---(J3)----> loop,mix
      /JACK client   |
                     +---(R3)---> sax_1.wav

REC status indicates that the source of the signal
is the soundcard or JACK client. The input signal will be 
written directly to a file except in the special preview and doodle 
modes.


=head3 Track, MON status

    sax_1.wav ------(3)----> loop,3 ----(J3)----> loop,mix

=head3 Mixer, with mixdown enabled

In the second part of the flow graph, the mixed signal is
delivered to an output device through the Master chain,
which can host effects. Usually the Master track
provides final control before audio output or mixdown.

    loop,mix --(1/Master)--> loop,output -> Sound device
                                 |
                                 +----->(2/Mixdown)--> Mixdown_1.wav

During mastering, the mastering network is inserted between
the Master track and the output node C<loop,output>.

    loop,mix --(1/Master)-> loop,mastering-[NETWORK]->loop,output -> Sound device
                                                         |
                                                         +->(2/Mixdown)--> Mixdown_1.wa


=head3 Mastering Mode

In mastering mode (invoked by C<master_on> and released
C<master_off>) the following network is used:

                                      +---(Low)---+ 
                                      |           |
    lp,mastering -(Eq)-> lp,crossover +---(Mid)---+ lp,boost --(Boost)--> lp,output
                                      |           |
                                      +---(High)--+ 

The B<Eq> track hosts an equalizer.

The B<Low>, B<Mid> and B<High> tracks each apply a bandpass
filter, a compressor and a spatialiser.

The B<Boost> track applies gain and a limiter.

These effects and their default parameters are defined
in the configuration file F<.namarc>.

=head2 Preview and Doodle Modes

These non-recording modes, invoked by C<preview> and C<doodle> commands
tweak the routing rules for special purposes.  B<Preview
mode> disables recording of WAV files to disk.  B<Doodle
mode> disables MON inputs while enabling only one REC track per
signal source. The C<arm> command releases both preview
and doodle modes.

=head1 TEXT COMMANDS

[% qx(./emit_command_headers pod) %]

=head1 BUGS AND LIMITATIONS

No waveform or signal level displays are provided.
No latency compensation is provided across the various
signal paths, although this function is under development.

=head1 SECURITY CONCERNS

If you are using Nama with the NetECI interface (i.e. if
Audio::Ecasound is I<not> installed) you should firewall TCP port 2868 
if you computer is exposed to the Internet. 

=head1 EXPORT

None by default.

=head1 AVAILABILITY

CPAN, for the distribution.

C<cpan Audio::Nama>

You will need to install Tk to use the GUI.

C<cpan Tk>

You can pull the source code as follows: 

C<git clone git://github.com/bolangi/nama.git>

Build instructions are contained in the F<README> file.

=head1 PATCHES

The main module, Nama.pm is a concatenation of
several source files.  Patches should be made against the
source files.

=head1 AUTHOR

Joel Roth, E<lt>joelz@pobox.comE<gt>
