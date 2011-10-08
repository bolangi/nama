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
$VERSION = 1.080;
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
use Graph;
use IO::Socket; 
use IO::Select;
use IPC::Open3;
use Module::Load::Conditional qw(can_load); 
use Parse::RecDescent;
use Storable qw(thaw);
use Term::ReadLine;
use Text::Format;
# use File::HomeDir;# Assign.pm
# use File::Slurp;  # several
# use List::Util;   # Fade.pm
# use Time::HiRes; # automatically detected
# use Tk;           # loaded conditionally
# use Event;		# loaded conditionally
# use AnyEvent;		# loaded after Tk or Event

## Load my modules

use ::Assign qw(:all);
use ::Track;
use ::Group;
use ::Bus;    
use ::Mark;
use ::IO;
use ::Graph;
use ::Wav;
use ::Insert;
use ::Fade;
use ::Edit;
use ::Text;
use ::Graphical;
use ::ChainSetup ();

# the following separate out functionality
# however occupy the :: namespace

use ::Initializations ();
use ::Options ();
use ::Config ();
use ::Terminal ();
use ::Wavinfo ();
use ::Project ();
use ::Modes ();
use ::Engine_setup ();
use ::Engine_cleanup ();
use ::Realtime ();
use ::Mute_Solo_Fade ();
use ::Jack ();
use ::Regions ();
use ::Effect_chains ();
use ::Midi ();
use ::Memoize ();
use ::CacheTrack ();
use ::Effects ();
use ::Persistence ();
use ::Util qw(:all);

## Definitions ##

$| = 1;     # flush STDOUT buffer on every write

# 'our' declaration: code in all packages in Nama.pm can address
# the following variables without package name prefix

use ::Globals qw(:all);

$ui eq 'bullwinkle' or die "no \$ui, bullwinkle";

[% qx(./strip_all ./var_types.pl) %]


$text->{wrap} = new Text::Format {
	columns 		=> 75,
	firstIndent 	=> 0,
	bodyIndent		=> 0,
	tabstop			=> 4,
};

$debug2 = 0; # subroutine names
$debug = 0; # debug statements

# other initializations

#$engine->{events} = {};

$file = {
			effects_cache 		=> '.effects_cache',
			gui_palette 		=> 'palette',
			state_store 		=> 'State',
			effect_chain 		=> 'effect_chains',
			effect_profile 		=> 'effect_profiles',
			chain_setup 		=> 'Setup.ecs',
			user_customization 	=> 'custom.pl',
};

$gui->{_save_id} = "State";
$gui->{_seek_unit} = 1;
$gui->{marks} = {};


$config = {
	root_dir 						=> join_path( $ENV{HOME}, "nama"),
	soundcard_channels 				=> 10,
	memoize 						=> 1,
	use_pager 						=> 1,
	use_placeholders 				=> 1,
	volume_control_operator 		=> 'ea', # default to linear scale
	sync_mixdown_and_monitor_version_numbers => 1, # not implemented yet
	engine_fade_length_on_start_stop => 0.3, # when starting/stopping transport
	engine_fade_default_length 		=> 0.5, # for fade-in, fade-out
	engine_base_jack_seek_delay 	=> 0.1, # seconds
	edit_playback_end_margin 		=> 3,
	edit_crossfade_time 			=> 0.03,
	fade_down_fraction 				=> 0.75,
	fade_time1_fraction 			=> 0.9,
	fade_time2_fraction 			=> 0.1,
	fader_op 						=> 'ea',
	serialize_formats               => [ qw(yaml) ],
};

$prompt = "nama ('h' for help)> ";

$this_bus = 'Main';
jack_update(); # to be polled by Event

$fx = {
	mute_level 					=> {ea => 0, 	eadb => -96}, 
	fade_out_level 				=> {ea => 0, 	eadb => -40},
	unity_level 				=> {ea => 100, 	eadb => 0}, 
	fade_resolution 			=> 200, # steps per second
};
$setup->{_old_snapshot} = {};

$mastering->{track_names} = [ qw(Eq Low Mid High Boost) ];

$mode->{mastering} = 0;

init_memoize() if $config->{memoize};

sub setup_grammar { }

	### COMMAND LINE PARSER 

	$debug2 and print "Reading grammar\n";

	$text->{commands_yml} = get_data_section("commands_yml");
	$text->{commands_yml} = quote_yaml_scalars($text->{commands_yml});
	$text->{commands} = yaml_in( $text->{commands_yml}) ;

	$::AUTOSTUB = 1;
	$::RD_TRACE = 1;
	$::RD_ERRORS = 1; # Make sure the parser dies when it encounters an error
	$::RD_WARN   = 1; # Enable warnings. This will warn on unused rules &c.
	$::RD_HINT   = 1; # Give out hints to help fix problems.

	$text->{grammar} = get_data_section('grammar');

	$text->{parser} = Parse::RecDescent->new($text->{grammar}) or croak "Bad grammar!\n";

	[% qx(cat ./help_topic.pl) %]

	# JACK environment for testing

	$jack->{fake_ports_list} = get_data_section("fake_jack_lsp");

	# Midish command keywords
	
	$midi->{keywords} = 
	{
			map{ $_, 1} split " ", get_data_section("midish_commands")
	};

	# print remove_spaces("bulwinkle is a...");

#### Class and Object definitions for package '::'

our @ISA; # no anscestors
use ::Object qw(mode);

## The following methods belong to the root class

sub hello {"superclass hello"}

sub new { my $class = shift; return bless {@_}, $class }

[% qx(cat ./Core_subs.pl ) %]


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
