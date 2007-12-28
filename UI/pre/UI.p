package ::;
use 5.008;
use strict;
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

$debug3 = 0; # qualified routines get local $debug = $debug 3;
$debug2 = 1;
$debug = 1;

## Load my modules

use ::Assign qw(:all);
use ::Iam;    
use ::Tkeca_effects; 

print remove_spaces("bulwinkle is a...");
## Class and Object definitions for package '::'

our @ISA; # no anscestors
use Object::Tiny qw(mode);

## The following methods belong to the root class

sub hello {"superclass hello"}

sub new { my $class = shift; return bless {@_}, $class }

[% qx(cat ./Core_subs.pl ) %]

[% qx(cat ./Graphical_subs.pl ) %]

[% qx(cat ./Refresh_subs.pl ) %]


=comment
my $root_class = '::'; 
sub new { 
	my $class = shift;
	if (@_ % 2 and $class eq $root_class){
		my %h = ( @_ );
		my $mode = $h{mode};
		$mode =~ /text|txt|graphic|tk|gui/i or croak &usage;
		$mode =~ /text|txt/i       and $mode = 'Text';
		$mode =~ /graphic|tk|gui/i and $mode = 'Graphical';
		return bless { @_ }, "$root_class\::" . $mode;
	} 
	return bless {@_}, $class;
}
sub usage { <<USAGE; }
Usage:    UI->new(mode => "text")
       or UI->new(mode => "tk")
USAGE

=cut


package ::Graphical;  ## gui routines
our @ISA = '::';
#use Tk;
#use ::Assign qw(:all);

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub new { my $class = shift; return bless {@_}, $class }
sub loop {
	package ::;
	init_gui; # the main window, effect window hidden
	transport_gui;
	oid_gui;
	time_gui;
	new_take;
	new_take;
	::load_project(
		{create => $opts{c},
		 name   => $project_name}) if $project_name;
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
sub show_unit{};

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

[% qx(./emit_command_headers) %]

[% qx(cat ./grammar_body.pl) %]

);

# we use the following settings if we can't find config files

$default = <<'FALLBACK_CONFIG';
[% qx(cat ./config.yaml) %]
FALLBACK_CONFIG

# the following template are used to generate chain setups.
$oids = <<'TEMPLATES';
[% qx(cat ./chain_templates.yaml) %]
TEMPLATES


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
