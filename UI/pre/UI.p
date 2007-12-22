use 5.008;
use strict qw(vars);
use warnings;
use lib "$ENV{HOME}/build/flow/UI/lib"; 

package ::;

use Carp;
use Cwd;
use Tk;
use IO::All;
use Storable; 
use Getopt::Std;
use Audio::Ecasound;
use Parse::RecDescent;
use Data::YAML::Writer;
use Data::YAML::Reader;

## Class and Object definition, root class

our @ISA;
use Object::Tiny qw(mode);

our $VERSION = '0.01';

## Definitions ##

[% qx(cat ./declarations.pl) %]

[% qx(cat ./var_types.pl) %]

$debug2 = 1;
$debug = 1;

## prevents bareword sub calls some_sub; from failing
use subs qw(

[% qx(./list_subs UI_methods.pl) %]

);
## Load my modules

use ::Iam;    	# IAM command support
use ::Tkeca_effects; # Some effects data

# we use the following settings if we can't find config files

$default = <<'FALLBACK_CONFIG';
[% qx(cat ./config.yaml) %]
FALLBACK_CONFIG

# the following template are used to generate chain setups.
$oids = <<'TEMPLATES';
[% qx(cat ./chain_templates.yaml) %]
TEMPLATES

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

## The following methods belong to the root class

sub hello {"superclass hello"}

[% qx(cat ./UI_methods.pl ) %]

## no-op graphic methods to inherit by Text

sub take_gui {}
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

## The following methods belong to the Graphical interface class

package ::Graphical;
our @ISA = '::';
use Carp;
use Tk;
sub hello {"make a window";}

[% qx(cat ./Graphical_methods.pl ) %]

## We also need stubs for procedural access to subs
## in the UI class.

[% qx(./make_stubs) %]

## The following methods belong to the Text interface class

package ::Text;
our @ISA = '::';
use Carp;
sub hello {"hello world!";}

[% qx(cat ./Text_methods.pl ) %]

## We also need stubs for procedural access to subs
## in the UI class.

[% qx(./make_stubs) %]

## The following methods belong to the Session class

#my $s = Session->new(name => 'paul_brocante');
# print $s->session_dir;

package ::Session;
our @ISA='::';
use Carp;
use Object::Tiny qw(name);
sub hello {"i'm a session"}
sub new { 
	my $class = shift; 
	my %vals = @_;
	$vals{name} or carp "invoked without values" and return;
	my $name = $vals{name};
	remove_spaces( $vals{name} );
	$vals{name} = $name;
	$vals{create_dir} and create_dir($name) and delete $vals{create_dir};
	return bless { %vals }, $class;
}
sub set {
	my $self = shift;
 	croak "odd number of arguments ",join "\n--\n" ,@_ if @_ % 2;
	my %new_vals = @_;
	my %filter;
	map{$filter{$_}++} keys %{ $self };
	map{ $self->{$_} = $new_vals{$_} if $filter{$_} 
		or carp "illegal key: $_ for object of type ", ref $self,$/
	} keys %new_vals;
}

## aliases 

sub wav_dir {UI::wav_dir() }
sub ecmd_dir { UI::ecmd_dir() }
sub this_wav_dir { UI::this_wav_dir() }
sub session_dir { UI::session_dir() }
sub remove_spaces { UI::remove_spaces() }

package ::Wav;
our @ISA='UI';
use Object::Tiny qw(head active n);
my @fields = qw(head active n);
my %fields;
map{$fields{$_} = undef} @fields;
use Carp;
sub this_wav_dir { UI::this_wav_dir() }
sub new { my $class = shift; 
 		croak "odd number of arguments ",join "\n--\n" ,@_ if @_ % 2;
		 return bless {%fields, @_}, $class }

sub _get_versions {
	my ($dir, $basename, $sep, $ext) = @_;

	$debug and print "getver: dir $dir basename $basename sep $sep ext $ext\n\n";
	opendir WD, $dir or carp ("can't read directory $dir: $!");
	$debug and print "reading directory: $dir\n\n";
	my %versions = ();
	for my $candidate ( readdir WD ) {
		$debug and print "candidate: $candidate\n\n";
		$candidate =~ m/^ ( $basename 
		   ($sep (\d+))? 
		   \.$ext )
		   $/x or next;
		$debug and print "match: $1,  num: $3\n\n";
		$versions{ $3 ? $3 : 'bare' } =  $1 ;
	}
	$debug and print "get_version: " , yaml_out(\%versions);
	closedir WD;
	%versions;
}

sub targets {# takes a Wav object or a string (filename head)
	local $debug = 1;
	my $wav = shift; 
 	my $head =  ref $wav ? $wav->head : $wav;
	$debug2 and print "&targets\n";
	local $debug = 0;
	$debug and ($t = this_wav_dir()), print 
"this_wav_dir: $t
head:         ", $head, $/;
		my %versions =  _get_versions(
			this_wav_dir(),
			$head,
			'_', 'wav' )  ;
		if ($versions{bare}) {  $versions{1} = $versions{bare}; 
			delete $versions{bare};
		}
	$debug and print "\%versions\n================\n", yaml_out(\%versions);
	\%versions;
}
sub versions {  # takes a Wav object or a string (filename head)
	my $wav = shift;
	if (ref $wav){ [ sort { $a <=> $b } keys %{ $wav->targets} ] } 
	else 		 { [ sort { $a <=> $b } keys %{ targets($wav)} ] }
}

sub this_last { 
	my $wav = shift;
	pop @{ $wav->versions} }

sub _selected_version {
	# return track-specific version if selected,
	# otherwise return global version selection
	# but only if this version exists
	my $wav = shift;
no warnings;
	my $version = 
		$wav->active 
		? $wav->active 
		: &monitor_version ;
	(grep {$_ == $version } @{ $wav->versions} ) ? $version : undef;
	### or should I give the active version
use warnings;
}
=comment
sub last_version { 
	## for each track or tracks in take

$track->last_version;
$take->last_version
$session->last_version
	
			$last_version = $this_last if $this_last > $last_version ;

}

sub new_version {
	last_version() + 1;
}
=cut

=comment
my $wav = Wav->new( head => vocal);

$wav->versions;
$wav->head  # vocal
$wav->n     # 3 i.e. track 3
$wav->active
$wav->targets
$wav->full_path

returns numbers

$wav->targets

returns targets

=cut

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

:: - Perl extensions for multitrack audio
recording and processing by Ecasound

=head1 SYNOPSIS

  use Audio::Ecasound::Flow;

  my $ui = ::->new("tk");

		or

  my $ui = ::->new("text");

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

__END__
