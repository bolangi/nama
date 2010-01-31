## Note on object model
# 
# All graphic method are defined in the base class :: .
# These are overridden in the ::Text class with no-op stubs.

# How is $ui->init_gui interpreted? If $ui is class ::Text
# Nama finds a no-op init_gui stub in package ::Text.
#
# If $ui is class ::Graphical, 
# Nama looks for init_gui() in package ::Graphical,
# finds nothing, so goes to look in the root namespace ::
# of which ::Text and ::Graphical are both descendants.

# All the routines in Graphical_methods.pl can consider
# themselves to be in the base class, and can call base
# class subroutines without a package prefix

# Text_method.pl subroutines live in the ::Text class,
# and so they must use the :: prefix when calling
# subroutines in the base class.
#
# However because both subclass packages occupy the same file as 
# the base class package, all variables (defined by 'our') can 
# be accessed without a package prefix.

package ::;
require 5.10.0;
use vars qw($VERSION);
$VERSION = 1.052;
use Modern::Perl;
#use Carp::Always;
no warnings qw(uninitialized syntax);
use autodie qw(:default);
use Carp;
use Cwd;
use File::Find::Rule;
use File::Spec::Link;
use File::Path;
use File::Spec;
use File::Temp;
use Getopt::Long;
use IO::All;
use IO::Socket; 
use Module::Load::Conditional qw(can_load); 
use Parse::RecDescent;
use Storable; 
use Term::ReadLine;
use Graph;
use Data::Section -setup;
# use Timer::HiRes; # automatically detected
# use Tk;           # loaded conditionally
# use Event;		# loaded conditionally
# use AnyEvent;		# loaded after Tk or Event
# use Tk::FontDialog; # hmmm might be nice to use
use Text::Format;

## Load my modules

use ::Assign qw(:all);
use ::Track;
use ::Group;
use ::Bus;    
use ::Mark;
use ::IO;
use ::Graph;
use ::Wav;

## Definitions ##

$| = 1;     # flush STDOUT buffer on every write

# 'our' declaration: code in all packages in Nama.pm can address
# the following variables without package name prefix

[% qx(cat ./declarations.pl) %] 

[% qx(cat ./var_types.pl) %]

$text_wrap = new Text::Format {
	columns 		=> 75,
	firstIndent 	=> 0,
	bodyIndent		=> 0,
	tabstop			=> 4,
};

$debug2 = 0; # subroutine names
$debug = 0; # debug statements

[% qx(cat ./banner.pl) %]

# other initializations
$unit = 1;
$effects_cache_file = '.effects_cache';
$palette_file = 'palette.yml';
$state_store_file = 'State.yml';
$effect_chain_file = 'effect_chains.yml';
$effect_profile_file = 'effect_profiles.yml';
$chain_setup_file = 'Setup.ecs'; # For loading by Ecasound
$soundcard_channels = 10;
$use_monitor_version_for_mixdown = 1; # not implemented yet
$project_root = join_path( $ENV{HOME}, "nama");
$seek_delay = 0.1; # seconds
$prompt = "nama ('h' for help)> ";
$use_pager = 1;
$use_placeholders = 1;
$save_id = "State";
$fade_time = 0.3;
$old_snapshot = {};
$main_out = 1; # enable main output
$this_bus = 'Main';
jack_update(); # to be polled by Event
$memoize = 1;
$volume_control_operator = 'ea'; # don't break Stephanie's system
%mute_level 	= (ea => 0, 	eadb => -96); 
%fade_out_level = (ea => 0, 	eadb => -40);
%unity_level 	= (ea => 100, 	eadb => 0); 
$fade_resolution = 200; # steps per second

@mastering_track_names = qw(Eq Low Mid High Boost);
$mastering_mode = 0;

init_memoize() if $memoize;

# aliases for concise access

*tn = \%::Track::by_name;
*ti = \%::Track::by_index;
# $ti{3}->rw
sub setup_grammar { 
}
	### COMMAND LINE PARSER 

	$debug2 and print "Reading grammar\n";

	*commands_yml = __PACKAGE__->section_data("commands_yml");
	*cop_hints_yml = __PACKAGE__->section_data("chain_op_hints_yml");
	%commands = %{ ::yaml_in( $::commands_yml) };

	$::AUTOSTUB = 1;
	$::RD_TRACE = 1;
	$::RD_ERRORS = 1; # Make sure the parser dies when it encounters an error
	$::RD_WARN   = 1; # Enable warnings. This will warn on unused rules &c.
	$::RD_HINT   = 1; # Give out hints to help fix problems.

	*grammar = __PACKAGE__->section_data("grammar");

	$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";

	[% qx(cat ./help_topic.pl) %]

	# we use the following settings if we can't find config files

	*default = __PACKAGE__->section_data("default_namarc");

	# default colors

	*default_palette_yml = __PACKAGE__->section_data("default_palette_yml");

	# JACK environment for testing

	*fake_jack_lsp = __PACKAGE__->section_data("fake_jack_lsp");

	# print remove_spaces("bulwinkle is a...");

#### Class and Object definitions for package '::'

our @ISA; # no anscestors
use ::Object qw(mode);

## The following methods belong to the root class

sub hello {"superclass hello"}

sub new { my $class = shift; return bless {@_}, $class }

[% qx(cat ./Core_subs.pl ) %]

[% qx(cat ./Graphical_subs.pl ) %] # root namespace!

[% qx(cat ./Refresh_subs.pl ) %]

## The following code loads the object core of the system 
## and initiates the chain templates (rules)

package ::Graphical;  ## gui routines

our @ISA = '::';      ## default to root class

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub loop {
	package ::;
	$attribs->{already_prompted} = 0;
	$term->tkRunning(1);
  	while (1) {
  		my ($user_input) = $term->readline($prompt) ;
  		::process_line( $user_input );
  	}
}

## The following methods belong to the Text interface class

package ::Text;
our @ISA = '::';
use Carp;
use ::Assign qw(:all);

sub hello {"hello world!";}

sub loop {
	package ::;
	issue_first_prompt();
	$Event::DIED = sub {
	   my ($event, $errmsg) = @_;
	   say $errmsg;
	   $attribs->{line_buffer} = q();
	   $term->clear_message();
	   $term->rl_reset_line_state();
	};
	Event::loop();
}

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
sub reset_engine_mode_color_display {}
sub set_engine_mode_color_display {}

package ::;  # for Data::Section

1;
__DATA__
__[commands_yml]__
[% qx(./strip_all  ./commands.yml) %]
__[grammar]__
[% qx(./strip_all  ./grammar_body.pl) %]
[% qx(./emit_command_headers headers) %]
__[chain_op_hints_yml]__
[% qx(cat ./ecasound_chain_operator_hints.yml) %];
__[default_namarc]__
[% qx(cat ./namarc) %]
__[default_palette_yml]__
[% qx(cat ./palette.yml) %]
__[fake_jack_lsp]__
[% qx(cat ./fake_jack_lsp) %]
__[end_data_section]__
__END__

=head1 NAME

B<Nama> - Ecasound-based recorder, mixer and mastering system

=head1 SYNOPSIS

B<nama> [I<options>] [I<project_name>]

=head1 DESCRIPTION

B<Nama> is a recorder/mixer application using Ecasound in
the back end to provide multitrack recording, effects
processing, and mastering. Nama includes aux sends, inserts,
buses, regions and time-shifting functions. Full help is
provided, including commands by category, search for
commands or effects by name or by arbitrary string.

By default, Nama starts up a GUI interface with a command
line interface running in the terminal window. The B<-t>
option provides a text-only interface for console
users.

=head1 OPTIONS

=over 12

=item B<--gui, -g>

Start Nama in GUI mode

=item B<--text, -t>

Start Nama in text mode

=item B<--config, -f>

Specify configuration file (default: ~/.namarc)

=item B<--project-root, -d>

Specify project root directory

=item B<--create-project, -c>

Create project if it doesn't exist

=item B<--net-eci, -n>

Use Ecasound's Net-ECI interface

=item B<--libecasoundc, -l>

Use Ecasound's libecasoundc interface

=item B<--save-alsa, -a>

Save/restore alsa state with project data

=item B<--help, -h>

This help display

=back

Debugging options:

=over 12

=item B<--no-static-effects-data, -s>

Don't load effects data

=item B<--no-state, -m>

Don't load project state

=item B<--no-static-effects-cache, -e>

Bypass effects data cache

=item B<--regenerate-effects-cache, -r>

Regenerate the effects data cache

=item B<--no-reconfigure-engine, -R>

Don't automatically configure engine

=item B<--debugging-output, -D>

Emit debugging information

=item B<--fake-jack, -J>

Simulate JACK environment

=item B<--fake-alsa, -A>

Simulate ALSA environment

=item B<--no-ecasound, -E>

Don't spawn Ecasound process

=item B<--execute-command, -X>

Supply a command to execute

=back

=head1 CONTROLLING NAMA/ECASOUND

Ecasound is configured through use of I<chain setups>. Nama
serves as intermediary generating appropriate chain setups
for recording, playback, mixing, etc. and running the audio
processing engine according to user commands.

Commands for audio processing with Nama/Ecasound fall into
two categories: I<static commands> that influence the chain
setup and I<dynamic commands> that influence the realtime
behavior of the audio processing engine.

=head2 STATIC COMMANDS

Static commands affect I<future> runs of the audio
processing engine. For example, B<rec, mon> and B<off>
determine whether the current track will get its audio
stream from a live source or whether an existing WAV file
will be played back. Nama responds to static commands by
reconfiguring the engine and displaying the updated
track status in text and GUI form.

=head2 DYNAMIC COMMANDS

Once a chain setup is loaded and the engine is launched,
another set of commands controls the realtime behavior of
the audio processing engine. Commonly used I<dynamic
commands> include transport C<start> and C<stop>; playback
head repositioning commands such C<forward>, C<rewind> and
C<setpos>. Effects may be added, modified or removed 
while the engine is running.

=head2 CONFIGURATION

General configuration of sound devices and program options
is performed by editing the F<.namarc> file. On Nama's first
run, a default version of F<.namarc> is usually placed in
the user's home directory.

=head1 Tk GRAPHICAL UI 

Invoked by default if Tk is installed, this interface
provides a subset of Nama's functionality on two
panels, one for general control, the second for effects. 

The general panel has buttons for project create, load
and save, for adding tracks and effects, and for setting
the vol, pan and record status of each track.

The GUI project name bar and time display change color to indicate
whether the upcoming operation will include live recording
(red), mixdown only (yellow) or playback only (green).  Live
recording and mixdown can take place simultaneously.

The effects window provides sliders for each effect
parameters. Parameter range, defaults, and log/linear
scaling hints are automatically detects. Text-entry widgets
are used to enter parameters values for plugins without
hinted ranges.

The text command prompt appears in the terminal window
during GUI operation. Text commands may be issued at any
time.

=head1 TEXT UI

Press the I<Enter> key if necessary to get the following command prompt.

=over 12

C<nama [sax] ('h' for help)E<gt>>

=back

In this instance, 'sax' is the current track.

When using sub-buses, the bus is indicated before
the track:

=over 12

C<nama [Strings/violin] ('h' for help)E<gt>>

=back

At the prompt, you can enter Nama and Ecasound commands, Perl code
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

Each track has a descriptive name (i.e. vocal) and an
integer track-number assigned when the track is created.
The following paragraphs describes track attributes and
their settings.

=head2 WIDTH

Specifying 'mono' means a one-channel input, which is
recorded as a mono WAV file. The mono signal is duplicated
to a stereo signal with pan in the default mixer
configuration.

Specifying 'stereo' means two-channel input with recording
as a stereo WAV file.

Specifying N channels ('set width N') means N-channel input
with recording as an N-channel WAV file.

=head2 VERSION NUMBER

Multiple WAV files can be recorded for each track. These are
identified by a version number that increments with each
recording run, i.e. F<sax_1.wav>, F<sax_2.wav>, etc.  All
files recorded at the same time have the same version
numbers. 

The version numbers of files for playback can be selected at
the group or track level. By setting the group version
number to 5, you can play back the fifth take of a song, or
perhaps the fifth song of a live recording session. 

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
from any source. A track with no recorded WAV files 
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
projects, pull them into one project using C<link_track> 
commands, and sequence them using C<shift> commands.

=head2 EFFECTS

Each track gets volume and pan effects by default.  New
effects added using C<add_effect> are applied after pan and
before volume.  You can position effects anywhere you choose
using C<insert_effect> and C<append_effect>.

=head3 SENDS AND INSERTS

The C<send> command can routes a track's post-fader output
to a soundcard channel or JACK client in addition to the
normal mixer input. Nama currently allows one aux send per
track.

The C<add_insert_cooked> command configures a post-fader
send-and-return to soundcard channels or JACK clients.
Wet and dry signal paths are provided, with a default
setting of 100% wet.

=head1 GROUPS

Track groups are used internally.  The Main group
corresponds to a mixer. It has its own REC/MON/OFF setting
that influences the rec-status of individual tracks. 

Setting a group to OFF forces all of the group's tracks to
OFF. When the group is set to MON, track REC settings are
forced to MON.  When the group is set to REC, track status
can be REC, MON or OFF. 

The group MON mode triggers automatically after a successful
recording run.

The B<mixplay> command sets the Mixdown track to MON and the
Main group to OFF.

=head2 BUNCHES

A bunch is just a list of track names. Bunch names are used
with the keyword C<for> to apply one or more commands to to several
tracks at once. A bunch can be created with the C<new_bunch>
command. Any bus name can also be treated as a bunch.
Finally, a number of special bunch keywords are available.

=over 12

=item B<all>

Standard user tracks in the Main (default) bus

=item B<mix>

Sub-bus mix tracks in the Main bus

=item B<bus>

All tracks in the current bus

=item B<rec>, B<mon>, B<off>

All tracks with the corresponding I<setting> in the current bus

=item B<REC>, B<MON>, B<OFF>

All tracks with the corresponding I<status> in the current bus

=back

=head2 BUSES

Nama uses buses internally, and provides two kinds of
user-defined buses. 

B<Send buses> can be used as instrument monitors,
or to send pre- or post-fader signals from multiple
user tracks to an external program such as jconv.

B<Sub buses> (currently broken) enable multiple tracks to be
routed through a single track for vol/pan/effects processing
before reaching the mixer.

	add_sub_bus Strings
	add_tracks violin cello bass
	for violin cello bass; set bus Strings
	Strings vol - 10  # adjust bus output volume

=head1 ROUTING

Nama commands can address tracks by both a name and a
number. In Ecasound chain setups, only the track
number is used. 

=head2 Loop devices

Nama uses Ecasound loop devices to join two tracks, 
or to allow one track to have multiple inputs or
outputs. 

=head2 Flow diagrams

Let's examine the signal flow from track 3, the first 
available user track. Assume track 3 is named "sax".

We will divide the signal flow into track and mixer
sections.  Parentheses indicate chain identifiers or the
corresponding track name.

The stereo outputs of each user track terminate at 
Master_in, a loop device at the mixer input.

=head3 Track, REC status

    Sound device   --+---(3)----> Master_in
      /JACK client   |
                     +---(R3)---> sax_1.wav

REC status indicates that the source of the signal is the
soundcard or JACK client. The input signal will be written
directly to a file except in the special preview and doodle
modes.


=head3 Track, MON status

    sax_1.wav ------(3)----> Master_in

=head3 Mixer, with mixdown enabled

In the second part of the flow graph, the mixed signal is
delivered to an output device through the Master chain,
which can host effects. Usually the Master track
provides final control before audio output or mixdown.

    Master_in --(1/Master)--> Master_out -> Sound device
                                 |
                                 +----->(2/Mixdown)--> Mixdown_1.wav

During mastering, the mastering network is inserted
between the Master track, and the audio/mixdown output. 

=head3 Mastering Mode

In mastering mode (invoked by C<master_on> and released
C<master_off>) the following network is used:

                          +-(Low)-+ 
                          |       |
    Eq-in -(Eq)-> Eq_out -+-(Mid)-+- Boost_in -(Boost)-> soundcard/wav_out
                          |       |
                          +-(High)+ 

The B<Eq> track hosts an equalizer.

The B<Low>, B<Mid> and B<High> tracks each apply a bandpass
filter, a compressor and a spatialiser.

The B<Boost> track applies gain and a limiter.

These effects and their default parameters are defined
in the configuration file F<.namarc>.

=head2 Mixdown

The C<mixdown> command configures Nama for mixdown. 
The Mixdown track is set to REC (equivalent to C<Mixdown rec>) and the audio
monitoring output is turned off (equivalent to C<main_off>).

Mixdown proceeds after you enter the C<start> command.

=head2 Preview and Doodle Modes

These non-recording modes, invoked by C<preview> and C<doodle> commands
tweak the routing rules for special purposes.  B<Preview
mode> disables recording of WAV files to disk.  B<Doodle
mode> disables MON inputs while enabling only one REC track per
signal source. The C<arm> command releases both preview
and doodle modes.

=head1 TEXT COMMANDS

[% qx(./emit_command_headers pod) %]

=head1 DIAGNOSTICS

In most situations, the GUI display and the output of the
C<show_tracks> command (executed automatically on any change
in setup) show what to expect the next time the engine is
started.

Additionally, Nama has a number of diagnostic functions that
can help resolve problems without resorting to the debugging
flag (and wading through its prolific output.) The C<chains>
command displays the current chain setup to determine if
Ecasound is properly configured for the task at hand. (It
is much easier to read these setups than to write them!)

The C<dump> command displays data for the current track.
The C<dumpall> command shows all state that would be saved.
This is the same output that is written to the F<State.yml>
file when you issue the C<save> command.

=head1 BUGS AND LIMITATIONS

No waveform or signal level displays are provided.  

No latency compensation across signal paths is provided at
present, although this feature is planned.

=head1 SECURITY CONCERNS

If you are using Nama with the NetECI interface (i.e. if
Audio::Ecasound is I<not> installed) you should block TCP
port 2868 if you computer is exposed to the Internet. 

=head1 INSTALLATION

The following command, available on Unixlike systems with
Perl installed, will pull in Nama and other Perl libraries
required for text mode operation:

PERL_MM_USE_DEFAULT=1 cpan Audio::Nama

To use the GUI, you will need to install Tk:

C<cpan Tk>

You may want to install Audio::Ecasound if you prefer not to
run Ecasound in server mode:

C<cpan Audio::Ecasound>

You can pull the source code as follows: 

C<git clone git://github.com/bolangi/nama.git>

Consult the F<BUILD> file for build instructions.

=head1 SUPPORT

The Ecasound mailing list is a suitable forum for questions
regarding Nama installation, usage, feature requests, etc.,
as well as questions relating to Ecasound itself.

https://lists.sourceforge.net/lists/listinfo/ecasound-list

=head1 PATCHES

The main module, Nama.pm, its sister modules are
concatenations of several source files. Patches against the
source files are preferred.

=head1 AUTHOR

Joel Roth, E<lt>joelz@pobox.comE<gt>
