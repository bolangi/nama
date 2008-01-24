package ::;
use 5.008;
use strict;
no strict qw(subs);
use warnings;
our $VERSION = '0.01';
use lib "$ENV{HOME}/build/flow/UI/lib"; 
use lib qw(. ..);
use IO::All;
use Carp;
use Cwd;
use Tk;
use Storable; 
use Getopt::Std;
use Audio::Ecasound;
use Parse::RecDescent;
use Data::YAML::Writer;
use Data::YAML::Reader;

## Definitions ##

# 'our' declaration: all packages in the file will see the following
# variables. 

[% qx(cat ./declarations.pl) %] 

[% qx(cat ./var_types.pl) %]


# instances needed for yaml_out and yaml_in

$yw = Data::YAML::Writer->new; 
$yr = Data::YAML::Reader->new;

$debug3 = 0; # qualified routines get local $debug = $debug 3;
$debug2 = 1;
$debug = 1;

## The names of two helper loopback devices:

$loopa = 'loop,111';
$loopb = 'loop,222';

$wav_dir = '.'; # current directory default

$mixchain = 1; 
$mixchain_aux = 'MixDown'; # used for playing back mixes
                           # when chain 1 is active

$mixname = 'mix';
$unit = 1;
$effects_cache_file = 'effects_cache.storable';
$state_store_file = 'State';
$chain_setup_file = 'project.ecs';
$tk_input_channels = 10;
$use_monitor_version_for_mixdown = 1;
%alias = (1 => 'Mixdown', 2 => 'Tracker');
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
## Load bus rules

[% qx(cat ./Rules.pl ) %]

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
	transport_gui;
	oid_gui;
	time_gui;
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

sub take_gui {}
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
sub manifest {}
sub global_version_buttons {}
sub destroy_widgets {}
sub restore_time_marker_labels {}
sub show_unit {};
sub add_effect_gui {};
sub remove_effect_gui {};

## Some of these, may be overwritten
## by definitions that follow

[% qx(cat ./Text_methods.pl ) %]

package ::;

##  Grammar.p, source for Grammar.pm

### COMMAND LINE PARSER 

$debug2 and print "Reading grammar\n";

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

	


=head1 ABSTRACT

	Builds on the Audio::Ecasound interface to the 
	Ecasound audio processing engine to facilitate
	multitrack audio recording. Additions include:

	- Functions for generating chain setups, managing wav
	files, handling persistent configuration data.

	- Useful text-mode and Tk user interfaces

	- A foundation for high-level abstractions such 
	  as track, group, effect, mark, etc.

	Hash data structures representing system state are
	serialized to YAML and written to file. 
	The Git version control system cheaply provides 
	infrastructure for switching among various parameter
	sets. 


=head1 DESCRIPTION

Stub documentation for Audio::Ecasound::Flow, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

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
