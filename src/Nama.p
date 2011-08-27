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
$VERSION = 1.078;
use Modern::Perl;
#use Carp::Always;
no warnings qw(uninitialized syntax);
use autodie qw(:default);
use Carp;
use Cwd;
use Data::Section -setup;
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
use Storable; 
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

# the following separate out functionality
# however occupy the :: namespace

use ::Initializations ();
use ::Options ();
use ::Config ();
use ::Terminal ();
use ::Wavinfo ();
use ::Project ();
use ::Modes ();
use ::ChainSetup ();
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
use ::Util qw(
	rw_set 
	process_is_running 
	d1 d2 dn 
	colonize 
	time_tag 
	heuristic_time
	dest_type
	channels
	signal_format
	dest_type
	input_node
	output_node
);

## Definitions ##

$| = 1;     # flush STDOUT buffer on every write

# 'our' declaration: code in all packages in Nama.pm can address
# the following variables without package name prefix

our (

$commands_yml,

[% qx(cat ./declarations.pl) %] 

[% qx(./add_vars) %]

[% qx(cat ./singletons.pl) %]

);

[% qx(./strip_all ./var_types.pl) %]

$text->{wrap} = new Text::Format {
	columns 		=> 75,
	firstIndent 	=> 0,
	bodyIndent		=> 0,
	tabstop			=> 4,
};

$debug2 = 0; # subroutine names
$debug = 0; # debug statements

[% qx(cat ./banner.pl) %]

# other initializations

$gui->{_seek_unit} = 1;
$file->{effects_cache} = '.effects_cache';
$file->{gui_palette} = 'palette.yml';
$file->{state_store} = 'State.yml';
$file->{effect_chain} = 'effect_chains.yml';
$file->{effect_profile} = 'effect_profiles.yml';
$file->{chain_setup} = 'Setup.ecs'; # For loading by Ecasound
$config->{soundcard_channels} = 10;
$config->{sync_mixdown_and_monitor_version_numbers} = 1; # not implemented yet
$config->{root_dir} = join_path( $ENV{HOME}, "nama");
$config->{engine}->{jack_seek_delay} = 0.1; # seconds
$text->{prompt} = "nama ('h' for help)> ";
$config->{use_pager} = 1;
$config->{use_placeholders} = 1;
$gui->{_save_id} = "State";
$file->{user_customization} = "custom.pl";
$config->{engine}->{fade_length_on_start_stop} = 0.3; # when starting/stopping transport
$setup->{_old_snapshot} = {};
$this_bus = 'Main';
jack_update(); # to be polled by Event
$config->{memoize} = 1;
$config->{volume_control_operator} = 'ea'; # default to linear scale
%{$fx->{mute_level}} 	= (ea => 0, 	eadb => -96); 
%{$fx->{fade_out_level}} = (ea => 0, 	eadb => -40);
%{$fx->{unity_level}} 	= (ea => 100, 	eadb => 0); 
$fx->{fade_resolution} = 200; # steps per second
$config->{engine}->{fade_default_length} = 0.5; # for fade-in, fade-out
$config->{edit}->{playback_past_last_mark} = 3;
$config->{edit}->{crossfade_time} = 0.03; # 
$::Fade::fade_down_fraction = 0.75;
$::Fade::fade_time1_fraction = 0.9;
$::Fade::fade_time2_fraction = 0.1;
$::Fade::fader_op = 'ea';

@{$mastering->{track_names}} = qw(Eq Low Mid High Boost);
$mode->{mastering} = 0;

init_memoize() if $config->{memoize};

# aliases for concise access

*bn = \%::Bus::by_name;
*tn = \%::Track::by_name;
*ti = \%::Track::by_index;
*gn = \%::Group::by_index;
# $ti{3}->rw
sub setup_grammar { }

	### COMMAND LINE PARSER 

	$debug2 and print "Reading grammar\n";

	*commands_yml = __PACKAGE__->section_data("commands_yml");
	$commands_yml = quote_yaml_scalars($commands_yml);
	*cop_hints_yml = __PACKAGE__->section_data("chain_op_hints_yml");
	%{$text->{commands}} = %{ ::yaml_in( $commands_yml) };

	$::AUTOSTUB = 1;
	$::RD_TRACE = 1;
	$::RD_ERRORS = 1; # Make sure the parser dies when it encounters an error
	$::RD_WARN   = 1; # Enable warnings. This will warn on unused rules &c.
	$::RD_HINT   = 1; # Give out hints to help fix problems.

	*grammar = __PACKAGE__->section_data("grammar");

	$text->{parser} = Parse::RecDescent->new($text->{grammar}) or croak "Bad grammar!\n";

	[% qx(cat ./help_topic.pl) %]

	# we use the following settings if we can't find config files

	*default = __PACKAGE__->section_data("default_namarc");

	# default user customization file custom.pl - see EOF
	
	*custom_pl = __PACKAGE__->section_data("custom_pl");

	# default colors

	*default_palette_yml = __PACKAGE__->section_data("default_palette_yml");

	# JACK environment for testing

	*fake_jack_lsp = __PACKAGE__->section_data("fake_jack_lsp");

	# Midish command keywords
	
	%{$midi->{keywords}} = map{ $_, 1} split " ", 
		${ __PACKAGE__->section_data("midish_commands") };

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
__[commands_yml]__
[% qx(./strip_all ./commands.yml ) %]
__[grammar]__
[% qx(./strip_all  ./grammar_body.pl) %]
[% qx(./emit_command_headers headers) %]
__[chain_op_hints_yml]__
[% qx(cat ./ecasound_chain_operator_hints.yml) %];
__[default_namarc]__
[% qx(cat ./namarc) %]
__[custom_pl]__
[% qx(cat ./custom.pl) %]
__[default_palette_yml]__
[% qx(cat ./palette.yml) %]
__[fake_jack_lsp]__
[% qx(cat ./fake_jack_lsp) %]
__[midish_commands]__
[% qx(cat ./midish_commands) %]
__[end_data_section]__
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
