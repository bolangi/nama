package ::;
our $VERSION = '0.95';
use 5.008;
use strict;
no strict qw(subs);
use warnings;
no warnings qw(uninitialized);
no warnings;
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
use IO::All;

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
$jack_on = 0; # you should configure jack as device directly in .namarc
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
#use Tk;
#use ::Assign qw(:all);

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub new { my $class = shift; return bless {@_}, $class }
sub loop {
    package ::;
    #MainLoop;
    my $term = new Term::ReadLine 'Nama';
	$term->tkRunning(1);
    my $prompt = "Enter command: ";
    $OUT = $term->OUT || \*STDOUT;
	while (1) {
    my ($user_input) = $term->readline($prompt) ;
	next if $user_input =~ /^\s*$/;
     $term->addhistory($user_input) ;
	::Text::command_process( $user_input );
	}
#   Term::Shell version
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

sub start_heartbeat {}
sub start_clock {}
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
$::RD_HINT = 1;

# rec command changes active take

$grammar = q(

[% qx(./strip_comments  ./grammar_body.pl) %]

[% qx(./emit_command_headers) %]
);
open SAVERR, ">&STDERR";
open STDERR, ">/dev/null" or die "couldn't redirect IO";
$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";
close STDERR;
open STDERR, ">&SAVERR";
#select STDOUT; $| = 1;
# ::Text::OuterShell::create_help_subs();
#

[% qx(cat ./help_topic.pl) %]

# we use the following settings if we can't find config files

$default = <<'FALLBACK_CONFIG';
[% qx(cat ./namarc) %]
FALLBACK_CONFIG

1;
__END__

=head1 NAME

B<Audio::Multitrack> - Perl extensions for multitrack audio processing

B<nama> - multitrack recording/mixing application

Type 'man nama' for details on usage and licensing.

No further documentation is provided regarding
Audio::Multitrack and its subordinate modules.
