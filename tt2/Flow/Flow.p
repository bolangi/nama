use 5.008;
use strict qw(vars);
use warnings;

package Audio::Ecasound::Flow::UI;

use Carp;
use IO::All;
use Cwd;
use Storable; 
use Data::Dumper;
use Getopt::Std;
use Tk;
use Audio::Ecasound;
use Parse::RecDescent;
use YAML::Tiny;
use Data::YAML::Writer;
use Data::YAML::Reader;

our $VERSION = '0.01';

## Imported modules

use lib '/home/jroth/build/flow/lib'; # no trailing slash
use lib '/home/jroth/build/flow/blib/lib/';

## Definitions ##

[% qx(cat ./declarations.pl) %]

[% qx(cat ./var_types.pl) %]

# we use the following settings if we can't find config files

$default = <<'FALLBACK_CONFIG';
[% qx(cat ./config.yaml) %]
FALLBACK_CONFIG

# the following template are used to generate chain setups.
$oids = <<'TEMPLATES';
[% qx(cat ./chain_templates.yaml) %]
TEMPLATES

##  Grammar.p, source for Grammar.pm

package Audio::Ecasound::Flow::UI;

### COMMAND LINE PARSER 

$debug2 and print "Reading grammar\n";

$AUTOSTUB = 1;
$RD_HINT = 1;

# rec command changes active take

$grammar = q(

[% qx(./emit_command_headers) %]

[% qx(cat ./grammar_body.pl) %]

);

1;

## Load my modules

use Audio::Ecasound::Flow::Grammar;	# Command line grammar
use Audio::Ecasound::Flow::Iam;    	# IAM command support
use Audio::Ecasound::Flow::Tkeca_effects; # Some effects data

# CLASS DEFINITIONS

# Preloaded methods go here.
package Audio::Ecasound::Flow::UI;
our @ISA; # superclass, has no ancestor
use Object::Tiny qw{mode};
use Carp;
=comment
sub new { my $class = shift; 
			my $mode = shift; # Text or Graphical
			lc $mode eq 'tk' 
		or	lc $mode eq 'gui'
		or  lc $mode eq 'graphic'
		or  lc $mode eq 'graphical'
		and return bless { @_ },
			Audio::Ecasound::Flow::UI::Graphical 
		or  lc $mode eq 'text'
		and return bless { @_ },
			Audio::Ecasound::Flow::UI::Text
}

=cut

sub hello {my $h = "superclass hello"; print ($h); $h ;}

sub take_gui {}
sub track_gui {}
sub track_gui {}
sub refresh {}
sub flash_ready {}
sub update_master_version_button {}
sub paint_button {}
sub refresh_oids {}
sub paint_button {}
sub session_label_configure{}
sub length_display{}
sub clock_display {}
sub manifest {}
sub global_version_buttons {}
sub destroy_widgets {}

## The following methods belong to the ancestor UI class. 

package Audio::Ecasound::Flow::UI;

[% qx(cat ./UI_methods.pl ) %]

## The following methods belong to the Graphical interface class

package Audio::Ecasound::Flow::UI::Graphical;

[% qx(cat ./Graphical_methods.pl ) %]

package Audio::Ecasound::Flow::UI::Text;

## The following methods belong to the Text interface class

[% qx(cat ./Text_methods.pl ) %]

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Audio::Ecasound::Flow::UI - Perl extensions for multitrack audio
recording and processing by Ecasound

=head1 SYNOPSIS

  use Audio::Ecasound::Flow;

  my $ui = Audio::Ecasound::Flow::UI->new("tk");

		or

  my $ui = Audio::Ecasound::Flow::UI->new("text");

	my %options = ( 

			session => 'Night at Carnegie',
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

=cut
