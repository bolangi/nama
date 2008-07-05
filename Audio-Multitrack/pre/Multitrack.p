package ::;
use 5.008;
use strict;
no strict qw(subs);
#use warnings;
#no warnings qw(uninitialized);
no warnings;
our $VERSION = '0.92';
use IO::All;
use Carp;
use Cwd;
use Tk;
use Storable; 
use Getopt::Std;
use Audio::Ecasound;
use Parse::RecDescent;
use Term::ReadLine;
use Data::YAML::Writer;
use Data::YAML::Reader;
use File::Find::Rule;
use File::Spec::Link;

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
$jack_on = 0; # you should configure jack as device directly in .ecmdrc
$project_root = join_path( $ENV{HOME}, "ecmd");

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

print remove_spaces("bulwinkle is a...");

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
#use Tk;
#use ::Assign qw(:all);

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub new { my $class = shift; return bless {@_}, $class }
sub loop {
    package ::;
    MainLoop;
# the following gives a shell in the terminal
# window simultaneous with the Tk user
# interface windows
#
# 	my $shell = ::Text::OuterShell->new;
# 	my $term = $shell->term();
# 	$term->tkRunning(1);
# 	$shell->cmdloop;
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

sub start_clock {}
sub group_gui {}
sub track_gui {}
sub refresh {}
sub refresh_t {}
sub refresh_c {}
sub flash_ready {}
sub update_master_version_button {}
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
$::RD_HINT = 1;

# rec command changes active take

$grammar = q(

[% qx(./strip_comments  ./grammar_body.pl) %]

[% qx(./emit_command_headers) %]
);
$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";
# ::Text::OuterShell::create_help_subs();
#

$helptext = q(
[% qx(cat ./help.txt) %]
);

# we use the following settings if we can't find config files

$default = <<'FALLBACK_CONFIG';
[% qx(cat ./ecmdrc) %]
FALLBACK_CONFIG

1;
__END__

=head1 NAME

B<Audio::Multitrack> - Perl extensions for multitrack audio processing

B<ecmd> - multitrack recording/mixing application

=head1 SYNOPSIS

B<ecmd> I<options> I<project_name>

=head1 OPTIONS

=over 12

=item B<-d> I<ecmd_dir>

Use I<ecmd_dir> as ecmd top-level project directory (default $HOME/ecmd )

=item B<-m>

Suppress loading of saved state

=item B<-g>

Graphical user interface (default)

=item B<-t>

Text interface

=item B<-f> I<config_file>

Use I<config_file> instead of default $HOME/.ecmdrc

=back

=head1 DESCRIPTION

B<Audio::Multitrack> provides class libraries for managing
tracks and buses.  

B<Ecmd> is an end-user application with text and graphical
interfaces. It is configured as a single mixer bus with
per-track volume/pan/effects, a master fader, and a mixdown
track.

There are two types of commands. 

B<Static commands> influence the chain setup that will be
used for audio processing.

For example, the REC/MON/OFF status for a track and 
its associated group controls whether that track will be included in the
next Ecasound chain setup, and whether the audio stream 
will be recorded or played back.

B<Dynamic commands> operate in realtime, affecting
volume, pan, and playback head position while the engine is
running. 

On the first run the program creates $HOME/.ecmdrc, the
configuration file and project directory $HOME/ecmd.  WAV
files and parameter settings for each project are stored in
directories under $HOME/ecmd.  You probably want to edit the
default .ecmdrc to suit your audio configuration.

Project state can be stored/retrieved. Inspect the State.yml
file in the project directory. The storage format is
user-friendly YAML.

To be certain your chain setup loads correctly, you may need
to regenerate the setup using the Arm button in the GUI or
the I<arm> command under the text interface.  This is
usually the last operation before pressing the start button.

=head1 LADSPA

Audio::Multitrack will automatically incorporate locally
available LADSPA plugins provided you have the 'analyseplugin'
program (part of LADSPA client libraries) installed.  

=head1 Tk GUI

Invoked using the -g switch on the ecmd command line, 
the Tk interface provides two panels for record/mix
and effects. Linear/log sliders are automatically used for most
plugins. For other plugins, text-entry widgets are used to
enter parameters. 

The GUI time display color indicates whether the upcoming
operation will include recording (red), mixing only (yellow) or
playback only (green).  

=head1 Text UI

Invoked using the -t switch on the ecmd command line, 
The command line interpreter includes history. 
Tab completion of command names has been disabled
due to problems with the library. 

Type B<help> for a command summary, B<help command> for
help with I<command>. 

=head1 TRACKS

Multiple WAV files can be recorded for each track. These are
identified by version number. Version number increment
automatically.  Identical version numbers indicate WAV files
recorded at the same time. The order of version numbers
follows the time sequence of the recordings.

Each track, including the Master and Mixdown, has its own
REC/MON/OFF setting and displays its own REC/MON/OFF
status. The Master track has only MON/OFF status. Setting REC
status for the Mixdown track is the same as issuing
the 'mixdown' command.

Master and Mixdown tracks can behave differently from 
user-created tracks because they belong to different
groups. 

All user-created tracks belong to the Tracker group.
There is a global REC/MON/OFF and version
setting that apply to all these tracks.

Tracker group MON setting (text command 'group_monitor')
forces all user tracks with a REC setting to MON status.
Tracker group MON setting triggers automatically after a
successful recording.

Tracker group OFF setting (text 'group_off') excludes all user
tracks from the chain setup. Can be useful when playing back files
recorded through the Mixdown function. The
text 'mixplay' command sets the Tracker group to OFF.

A track with no recorded WAV files that is set to MON will
show OFF status.

=head1 DIRECTORY STRUCTURE

$project_root is the directory where your project files,
including WAV files you record, will go. $project_root
is defined in the first non-comment line of 
your .ecmdrc file.

File or directory                Explanation
--------------------------------------------------------------------------
$HOME/.ecmdrc                         Ecmd configuration file

$project_root/project_name/.wav       WAV files we record will be stored here

$project_root/project_name/Setup.ecs  Ecasound chainsetup, dynamically generated

$project_root/project_name/State.yml  Default save file for project parameters

$project_root/project_name/.ecmdrc    Project-specific configuration

=head1 BUGS AND LIMITATIONS

No GUI remove-track command.

Default GUI volume sliders are not log scaled.

Adding and removing chain operators while the engine is
running may cause the engine to stop.

The post-recording cleanup routine currently deletes
newly recorded soundfiles under 44100 bytes in size. 

Looping behavior may not be reliable for loops under 6 seconds

Alsa settings save and restore function is currently disabled.

=head1 EXPORT

None by default.



=head1 DEPENDENCIES

The Ecasound audio processing libraries are required
to use this software, and need to be installed separately.
See http://www.eca.cx/ecasound/ .

LADSPA libraries and plugins are strongly recommended.
See http://ladspa.org/ . The 'analyseplugin'
utility program is needed to make best use of LADSPA.

=head1 AVAILABILITY

CPAN, for the distribution.

Pull source code using this command: 

    git clone git://github.com/bolangi/ecmd.git

=head1 AUTHOR

Joel Roth, E<lt>joelz@pobox.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Joel Roth

This library is licensed under GPL version 2.
