package ::;
use 5.008;
use strict;
use strict qw(refs);
use strict qw(subs);
use warnings;
no warnings qw(uninitialized);
no warnings;

BEGIN{ 

our $VERSION = '0.978';
our $ABSTRACT = 'Lightweight multitrack recorder/mixer';

[% qx(cat ./banner.pl) %]

}

use Carp;
use Cwd;
use Storable; 
use Getopt::Std;
use Audio::Ecasound;
use Parse::RecDescent;
use Term::ReadLine;
use Data::YAML;
use File::Find::Rule;
use File::Spec::Link;
use File::Spec::Unix;
use File::Temp;
use IO::All;
use Time::HiRes; 
use Event;
# use Tk    # loaded conditionally in GUI mode

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

## The names of two helper loopback devices:

$loopa = 'loop,111';
$loopb = 'loop,222';

# other initializations
$unit = 1;
$effects_cache_file = '.effects_cache';
$state_store_file = 'State';
$chain_setup_file = 'Setup.ecs'; # For loading by Ecasound
$tk_input_channels = 10;
$use_monitor_version_for_mixdown = 1; # not implemented yet
$ladspa_sample_rate = 44100; # temporary setting
$jack_enable = 0; # you should configure jack as device directly in .namarc
$project_root = join_path( $ENV{HOME}, "nama");

## Load my modules

use ::Assign qw(:all);
use ::Iam;    
use ::Tkeca_effects; 
use ::Track;
use ::Bus;    
use ::Mark;

# aliases for concise access

*tn = \%::Track::by_name;
*ti = \@::Track::by_index;

# $ti[3]->rw

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
our @ISA = '::';

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub new { my $class = shift; return bless {@_}, $class }
sub loop {
    package ::;
    #MainLoop;
    my $term = new Term::ReadLine 'Ecaound/Nama';
	$term->tkRunning(1);
    my $prompt = "nama ('h' for help)> ";
    $OUT = $term->OUT || \*STDOUT;
	while (1) {
    my ($user_input) = $term->readline($prompt) ;
	next if $user_input =~ /^\s*$/;
     $term->addhistory($user_input) ;
	::Text::command_process( $user_input );
	}
}

## The following methods belong to the Text interface class

package ::Text;
our @ISA = '::';
use Carp;
sub hello {"hello world!";}

## no-op graphic methods 

# those that take parameters will break!!!
# because object and procedural access get
# different parameter lists ($self being included);

sub init_gui {}
sub transport_gui {}
sub group_gui {}
sub track_gui {}
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
sub show_unit {};
sub add_effect_gui {};
sub remove_effect_gui {};
sub marker {};
## Some of these, may be overwritten
## by definitions that follow

[% qx(cat ./Text_methods.pl ) %]

package ::;

### COMMAND LINE PARSER 

$debug2 and print "Reading grammar\n";

$commands_yml = <<'YML';
[% qx(./strip_comments  ./commands.yml) %]
YML

%commands = %{ ::yaml_in( $::commands_yml) };

$::AUTOSTUB = 1;
$::RD_TRACE = 1;
$::RD_ERRORS = 1; # Make sure the parser dies when it encounters an error
$::RD_WARN   = 1; # Enable warnings. This will warn on unused rules &c.
$::RD_HINT   = 1; # Give out hints to help fix problems.
# rec command changes active take

$grammar = q(

[% qx(./strip_comments  ./grammar_body.pl) %]

[% qx(./emit_command_headers) %]
);

# we redirect STDERR to shut up noisy Parse::RecDescent
open SAVERR, ">&STDERR";
open STDERR, ">/dev/null" or die "couldn't redirect IO";
$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";
close STDERR;
open STDERR, ">&SAVERR";

[% qx(cat ./help_topic.pl) %]

# we use the following settings if we can't find config files

$default = <<'FALLBACK_CONFIG';
[% qx(cat ./namarc) %]
FALLBACK_CONFIG

1;
__END__

=head1 NAME

=head1 NAME

B<Audio::Ecasound::Multitrack> - Perl extensions for multitrack audio processing

B<Nama> - Lightweight multitrack recorder/mixer

=head1 SYNOPSIS

B<nama> [I<options>] [I<project_name>]

=head1 DESCRIPTION

B<Audio::Ecasound::Multitrack> provides class libraries for
tracks and buses, and a track oriented user interface for managing 
runs of the Ecasound audio-processing engine.

B<Nama> is a recorder/mixer application that configures
Ecasound as a single mixer bus.

By default, B<Nama> starts up the Tk GUI interface.
The command line interface runs simultaneously in the
terminal. The B<-t> option provides text interface for
console users, and does not require the Tk libraries.

=head1 OPTIONS

=over 12

=item B<-d> F<project_root>

Use F<project_root> as Nama's top-level directory. Default: $HOME/nama

=item B<-g>

Graphical mode, with text interface in terminal window

=item B<-t>

Text-only mode

=item B<-f> F<config_file>

Use F<config_file> instead of default F<.namarc>

=item B<-c>

Create the named project

=item B<-a>

Save and reload ALSA mixer state using alsactl

=item B<-m>

Suppress loading of saved state

=item B<-e>

Don't load static effects data

=item B<-s>

Don't load static effects data cache

=back

=head1 STATIC AND DYNAMIC COMMANDS

It may be helpful to observe that our commands for audio
processing fall into two categories:

=head2 STATIC COMMANDS

Some commands control the chain setup that will be used to
configure Ecasound for audio processing.  I refer to them as
I<static commands>.  Static commands have no effect while
the engine is running, come into play only the next time the
transport is armed.

For example, setting the REC/MON/OFF status of a track or
bus determines whether it will be included next time the
transport is armed, and whether the corresponding audio
stream will be recorded to a file or played back from an
existing file. 


=head2 DYNAMIC COMMANDS

Once the transport is running, another subset of commands
controls the audio processing engine, for example adjusting
effect parameters or repositioning the playback head.

=head1 FIRST RUN

On the first run the program prompts the user for permission
to create the configuration file, usually F<$HOME/.namarc>, and
a recording projects directory, F<$HOME/nama> by
default.  You should then edit F<.namarc> to suit your audio
configuration.

=head1 PERSISTENCE

Project state can be stored/retrieved. These data are stored
by default in the F<State.yml> file in the project
directory.

=head1 Tk GRAPHICAL UI 

Invoked by default, the Tk interface provides all
functionality on two panels, one for general control,
the second for effects. 

Logarithmic sliders are provided automatically for effects
with hinting. Text-entry widgets are used to 
enter parameters for effects where hinting is not
available.

After issuing the B<arm> or B<connect> commands, the GUI
time display changes color to indicate whether the upcoming operation
will include live recording (red), mixdown only (yellow) or
playback only (green).  Live recording and mixdown can 
take place simultaneously.

The text command prompt appears in the terminal window
during GUI operation. Text commands may be issued at any
time.

=head1 TEXT UI

Press the I<Enter> key if necessary to get the following command prompt.

=over 12

B<nama ('h' for help)E<gt>>

=back

You can now enter commands.  Nama and Ecasound
commands may be entered directly. You may also enter Perl
code preceded by C<eval> or shell code preceded by C<!>.

Multiple commands on a single line are allowed if delimited
by semicolons. Usually the lines are split on semicolons and
the parts are executed sequentially, however if the line
begins with C<eval> or C<!> the entire line will be given to
the corresponding interpreter.

You can access command history using up-arrow/down-arrow.

Type C<help> for general help, C<help command> for help with
C<command>, C<help foo> for help with commands containing
the string C<foo>. 

=head1 TRACKS

Each track has a descriptive name (i.e. vocal) and an
integer track-number assigned when the track is created.

Multiple WAV files can be recorded for each track. These are
identified by version number. Identical version numbers indicate WAV files
recorded at the same time. Version number increments
automatically so that the order of version numbers
follows the time sequence of the recordings.

Each track, including Master and Mixdown, has its own
REC/MON/OFF setting and displays its own REC/MON/OFF status.
The Master bus has only MON/OFF status. Setting REC status
for the Mixdown bus has the same effect as issuing the
B<mixdown> command. As with other engine operations, a start
command must be issued for mixdown to commence.

All user tracks belong to the Tracker group, which has
a group REC/MON/OFF setting and a default version setting
that advances automatically so that the default will
be to play back the most recent set of multitrack
recordings all together.

Setting the group to MON (text command B<group_monitor>)
forces user tracks with a REC setting to MON status if
a WAV file is available to play, or OFF status if no
audio stream is available. 

The group MON mode triggers automatically after 
recording has created new WAV files.

The group OFF setting (text command B<group_off>)
excludes all user tracks from the chain setup, and is
typically used when playing back mixdown tracks.  The
B<mixplay> command sets the Mixdown group
to MON and the Tracker group to
OFF.

A track with no recorded WAV files that is set to MON will
show OFF status.

=head1 BUGS AND LIMITATIONS

Several important functions including loop_enable and 
everything JACK-related are available only through 
text commands. 

setpos commands result in an long engine delay when 
JACK is used.

GUI volume sliders are linear scaled.

=head1 EXPORT

None by default.

=head1 AVAILABILITY

CPAN, for the distribution.

Pull source code using this command: 

C<git clone git://github.com/bolangi/nama.git>

=head1 AUTHOR

Joel Roth, E<lt>joelz@pobox.comE<gt>
