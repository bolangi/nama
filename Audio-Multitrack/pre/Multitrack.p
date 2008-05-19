package ::;
use 5.008;
use strict;
no strict qw(subs);
use warnings;
no warnings qw(uninitialized);
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

$unit = 1;
$effects_cache_file = '.effects_cache';
$state_store_file = 'State';
$chain_setup_file = 'Setup.ecs'; # For loading by Ecasound
$tk_input_channels = 10;
$use_monitor_version_for_mixdown = 1; # not implemented yet
$ladspa_sample_rate = 44100; # temporary setting
$jack_on = 0;

## Load my modules

use ::Assign qw(:all);
use ::Iam;    
use ::Tkeca_effects; 
use ::Track;
use ::Bus;    

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

$::AUTOSTUB = 1;
$::RD_HINT = 1;

# rec command changes active take

$grammar = q(

[% qx(./strip_comments  ./grammar_body.pl) %]

[% qx(./emit_command_headers) %]
);
# we use the following settings if we can't find config files

$default = <<'FALLBACK_CONFIG';
[% qx(cat ./ecmdrc) %]
FALLBACK_CONFIG

1;
__END__

=head1 NAME

:: - Perl extensions for multitrack audio
recording and processing by Ecasound

=head1 SYNOPSIS

  use ::;

  my $ui = ::->new("tk");

		or

  my $ui = ::->new("text");

	my %options = ( 

			project => 'Night at Carnegie',
			create => 1,
			effects => 'force-reload',
			track_state   => 'ignore',     
			effect_state   => 'ignore',     
			) ;

	$ui->main(%options);

	

=head1 NAME

Audio::Multitrack - User interfaces for multitrack audio
recording, mixing and effects processing with the Ecasound
audio processing engine.

=head1 SYNOPSIS

use Audio::Multitrack;
Audio::Multitrack::mainloop();

=head1 DESCRIPTION

Audio::Multitrack provides class libraries for managing
tracks and buses.  The user interfaces are configured to
provide a single mixer bus with per-track
volume/pan/effects, a master fader, and a mixdown track.
Settings are persistent, stored as YAML files.

On the first run the program creates $HOME/.ecmdrc, the
configuration file and project directory $HOME/ecmd. 
WAV files and parameter settings for each project are stored
in directories under $HOME/ecmd. 

You will need to edit .ecmdrc to suit your audio
configuration.

There are two types of commands. Chain setup related
commands take effect before audio processing begins.

For example, the REC/MON/OFF status for each track
is used to decide whether a given track will be
included in the Ecasound processing chain, and whether
audio for that track will be recorded or played back.

Realtime commands such as volume and pan levels,
and transport controls such as fast-forward
take effect while the engine is connected. 

=head1 Tk GUI

Audio::Multitrack will automatically incorporate locally
available LADSPA plugins provided you have the listplugins
program installed.  

The Tk interface will provide linear/log sliders for most
plugins. Text-entry widgets are used to enter parameters for
plugins when hints are not available.

=head1 TRACKS

Multiple WAV
files can be recorded for each track. These
are identified by version number, which can
be specified for each track.

Each track, including the Master and Mixdown have
their own REC/MON/OFF setting. 
and displays its own REC/MON/OFF status.

There is also a global REC/MON/OFF 
and global version setting that apply to all
tracks except Master and Mixdown.
Global MON setting forces all user tracks 
to MON state, and is entered automatically 
after a recording.

Global OFF setting excludes all user tracks
from the chain setup, useful when playing back
files recorded through the Mixdown function.

A track with no recorded WAV files that is set to 
MON will show OFF status.



=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Joel Roth, E<lt>jroth@dsl-verizon.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Joel Roth

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

__END__
