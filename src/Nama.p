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
$VERSION = 1.069;
use Modern::Perl;
#use Carp::Always;
no warnings qw(uninitialized syntax);
use autodie qw(:default);
use Carp;
use Cwd;
use File::Find::Rule;
use File::Path;
use File::Spec;
use File::Spec::Link;
use File::Temp;
use Getopt::Long;
use IO::All;
use IO::Socket; 
use IO::Select;
use IPC::Open3;
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
use ::Insert;
use ::Fade;
use ::Edit;

# the following separate out functionality
# however occupy the :: namespace

use ::Persistence ();
use ::ChainSetup ();
use ::CacheTrack ();
use ::Edit_subs ();
use ::Effect_subs ();
use ::Util qw(
	rw_set 
	process_is_running 
	d1 d2 dn 
	colonize 
	time_tag 
	heuristic_time
	dest_type
);
use ::Wavinfo_subs ();
use ::Config_subs ();
use ::Memoize_subs ();
use ::Project_subs ();
use ::Terminal_subs ();
use ::Effect_chain_subs ();
use ::Initialize_subs ();
use ::Option_subs ();
use ::Realtime_subs ();
use ::Engine_setup_subs ();
use ::Engine_cleanup_subs ();
use ::Mark_and_jump_subs ();
use ::Track_subs ();
use ::Jack_subs ();
use ::Mode_subs ();
use ::Mute_Solo_Fade ();
use ::Midi_subs ();
use ::Bus_subs ();
use ::Region_subs ();

## Definitions ##

$| = 1;     # flush STDOUT buffer on every write

# 'our' declaration: code in all packages in Nama.pm can address
# the following variables without package name prefix

our (
[% qx(cat ./declarations.pl) %] 

[% qx(./add_vars) %]

);

[% qx(./strip_all ./var_types.pl) %]

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
$user_customization_file = "custom.pl";
$fade_time = 0.3; # when starting/stopping transport
$old_snapshot = {};
$main_out = 1; # enable main output
$this_bus = 'Main';
jack_update(); # to be polled by Event
$memoize = 1;
$volume_control_operator = 'ea'; # default to linear scale
%mute_level 	= (ea => 0, 	eadb => -96); 
%fade_out_level = (ea => 0, 	eadb => -40);
%unity_level 	= (ea => 100, 	eadb => 0); 
$fade_resolution = 200; # steps per second
$default_fade_length = 0.5; # for fade-in, fade-out
$edit_playback_end_margin = 3;
$edit_crossfade_time = 0.03; # 
$::Fade::fade_down_fraction = 0.75;
$::Fade::fade_time1_fraction = 0.9;
$::Fade::fade_time2_fraction = 0.1;
$::Fade::fader_op = 'ea';

@mastering_track_names = qw(Eq Low Mid High Boost);
$mastering_mode = 0;

init_memoize() if $memoize;

# aliases for concise access

*bn = \%::Bus::by_name;
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

	$parser = Parse::RecDescent->new($grammar) or croak "Bad grammar!\n";

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
	
	%midish_command = map{ $_, 1} split " ", 
		${ __PACKAGE__->section_data("midish_commands") };

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
use ::Util qw(really_recording);
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

[% qx(cat ./man_page_part1) %]

[% qx(./emit_command_headers pod) %]

[% qx(cat ./man_page_part2) %]

