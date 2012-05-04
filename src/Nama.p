package ::;
require 5.10.0;
use vars qw($VERSION);
$VERSION = "1.100";
use Modern::Perl;
#use Carp::Always;
no warnings qw(uninitialized syntax);
use autodie qw(:default);

########## External dependencies ##########

use Carp;
use Cwd;
use Data::Section::Simple qw(get_data_section);
use File::Find::Rule;
use File::Path;
use File::Spec;
use File::Spec::Link;
use File::Temp;
use Getopt::Long;
use Git::Repository;
use Graph;
use IO::Socket; 
use IO::Select;
use IPC::Open3;
use Log::Log4perl qw(get_logger :levels);
use Module::Load::Conditional qw(can_load); 
use Parse::RecDescent;
use Storable qw(thaw);
use Term::ReadLine;
use Text::Format;
use Try::Tiny;
# use File::HomeDir;# Assign.pm
# use File::Slurp;  # several
# use List::Util;   # Fade.pm
# use List::MoreUtils; # Effects.pm
# use Time::HiRes; # automatically detected
# use Tk;           # loaded conditionally
# use Event;		# loaded conditionally
# use AnyEvent;		# loaded after Tk or Event

########## Nama modules ###########
#
# Note that :: in the *.p source files is expanded by       # SKIP_PREPROC
# preprocessing to Audio::Nama in the generated *.pm files. # SKIP_PREPROC
# ::Assign becomes Audio::Nama::Assign                      # SKIP_PREPROC
#
# These modules import functions and variables
#

use ::Assign qw(:all);
use ::Globals qw(:all);
use ::Util qw(:all);

# Import the two user-interface classes

use ::Text;
use ::Graphical;

# They are descendents of a base class we define in the root namespace

our @ISA; # no ancestors
use ::Object qw(mode); # based on Object::Tiny

sub hello {"superclass hello"}

sub new { my $class = shift; return bless {@_}, $class }

# The singleton $ui belongs to either the ::Text or ::Graphical class
# depending on command line flags (-t or -g).
# This (along with the availability of Tk) 
# determines whether the GUI comes up. The Text UI
# is *always* available in the terminal that launched
# Nama.

# How is $ui->init_gui interpreted? If $ui belongs to class
# ::Text, Nama finds a no-op init_gui() stub in package ::Text
# and does nothing.

# If $ui belongs to class ::Graphical, Nama looks for
# init_gui() in package ::Graphical, finds nothing, so goes to
# look in the base class.  All graphical methods (found in
# Graphical_subs.pl) are defined in the root namespace so they can
# call Nama core methods without a package prefix.

######## Nama classes ########

use ::Track;
use ::Bus;    
use ::Mark;
use ::IO;
use ::Wav;
use ::Insert;
use ::Fade;
use ::Edit;
use ::EffectChain;

####### Nama subroutines ######
#
# The following modules serve only to define and segregate subroutines. 
# They occupy the root namespace (except ::ChainSetup)
# and do not execute any code when use'd.
#

use ::Initializations ();
use ::Options ();
use ::Config ();
use ::Custom ();
use ::Terminal ();
use ::Grammar ();
use ::Help ();

use ::Project ();
use ::Persistence ();

use ::ChainSetup (); # separate namespace
use ::Graph ();
use ::Modes ();
use ::Memoize ();

use ::Engine_setup ();
use ::Engine_cleanup ();
use ::Effects ();
use ::Realtime ();
use ::Mute_Solo_Fade ();
use ::Jack ();

use ::Regions ();
use ::CacheTrack ();
use ::Bunch ();
use ::Wavinfo ();
use ::Midi ();
use ::Latency ();

sub main { 
	definitions();
	process_command_line_options();
	setup_grammar();
	initialize_interfaces();
	command_process($config->{execute_on_project_load});
	reconfigure_engine();
	command_process($config->{opts}->{X});
	$ui->loop;
}
sub cleanup_exit {
 	remove_riff_header_stubs();
	# for each process: 
	# - SIGINT (1st time)
	# - allow time to close down
	# - SIGINT (2nd time)
	# - allow time to close down
	# - SIGKILL
	map{ my $pid = $_; 
		 map{ my $signal = $_; 
			  kill $signal, $pid; 
			  sleeper(0.2) 
			} (2,2,9)
	} @{$engine->{pids}};
 	#kill 15, ecasound_pid() if $engine->{socket};  	
	close_midish() if $config->{use_midish};
	$text->{term}->rl_deprep_terminal() if defined $text->{term};
	exit; 
}
END { cleanup_exit() }


1;
__DATA__
@@ commands_yml
[% qx(./strip_all ./commands.yml ) %]
@@ grammar
[% qx(./strip_all  ./grammar_body.pl) %]
[% qx(./emit_command_headers headers) %]
@@ chain_op_hints_yml
[% qx(cat ./ecasound_chain_operator_hints.yml) %];
@@ default_namarc
[% qx(cat ./namarc) %]
@@ custom_pl
[% qx(cat ./custom.pl) %]
@@ fake_jack_lsp
[% qx(cat ./fake_jack_lsp) %]
@@ fake_jack_latency
[% qx(cat ./fake_jack_latency) %]
@@ midish_commands
[% qx(cat ./midish_commands) %]
@@ default_palette_yml
[% qx(cat ./palette.yml) %]
__END__

=head1 NAME

Nama/Audio::Nama - an audio recording, mixing and editing application

=head1 DESCRIPTION

B<Nama> is an application for multitrack recording,
non-destructive editing, mixing and mastering using the
Ecasound audio engine developed by Kai Vehmanen.

Features include tracks, buses, effects, presets,
sends, inserts, marks and regions. Nama runs under JACK and
ALSA audio frameworks, automatically detects LADSPA plugins,
and supports Ladish Level 1 session handling.

Type C<man nama> for details.
