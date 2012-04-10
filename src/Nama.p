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
# the base class package, all variables defined by 'our' can 
# be accessed without a package prefix.
#
# With the introduction of variable export by ::Globals,
# 'our' is used secondarily to provide the global vars to multiple
# members of a class hierarchy to singletons, pronouns,
# and other categories of remaining globals.
#
#

package ::;
require 5.10.0;
use vars qw($VERSION);
$VERSION = "1.100";
use Modern::Perl;
#use Carp::Always;
no warnings qw(uninitialized syntax);
use autodie qw(:default);
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
# use Data::Rmap    # EffectChain.pm
# use File::HomeDir;# Assign.pm
# use File::Slurp;  # several
# use List::Util;   # Fade.pm
# use List::MoreUtils;   # Effects.pm
# use Time::HiRes; # automatically detected
# use Tk;           # loaded conditionally
# use Event;		# loaded conditionally
# use AnyEvent;		# loaded after Tk or Event

####### Load Nama modules

## import functions and variables

use ::Assign qw(:all);
use ::Globals qw(:all);
use ::Util qw(:all);

## Classes

use ::Track;
use ::Bus;    
use ::Mark;
use ::IO;
use ::Wav;
use ::Insert;
use ::Fade;
use ::Edit;
use ::Text;
use ::Graphical;
use ::ChainSetup;
use ::EffectChain;

# The following modules serve only to define and segregate subroutines. 
# They occupy the root namespace and do not execute any code when use'd.

use ::Bunch ();
use ::Grammar ();
use ::Help ();
use ::Custom ();
use ::Initializations ();
use ::Options ();
use ::Config ();
use ::Terminal ();
use ::Wavinfo ();
use ::Project ();
use ::Modes ();
use ::Graph ();
use ::Engine_setup ();
use ::Engine_cleanup ();
use ::Realtime ();
use ::Mute_Solo_Fade ();
use ::Jack ();
use ::Regions ();
use ::Midi ();
use ::Memoize ();
use ::CacheTrack ();
use ::Effects ();
use ::Persistence ();

sub main { 
	#setup_grammar(); 		# executes directly in body
	definitions();
	process_options();
	initialize_interfaces();
	command_process($config->{execute_on_project_load});
	reconfigure_engine();	# Engine_setup_subs.pm
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


#### Class and Object definitions for package '::'

our @ISA; # no anscestors
use ::Object qw(mode);

## The following methods belong to the root class

sub hello {"superclass hello"}

sub new { my $class = shift; return bless {@_}, $class }

package ::;  # for Data::Section

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
