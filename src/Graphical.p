# ------------ Graphical User Interface ------------

package ::Graphical;  ## gui routines
use Modern::Perl; use Carp;
our $VERSION = 1.071;
use ::Globals qw($text);

use Module::Load::Conditional qw(can_load);
use ::Assign qw(:all);
use ::Util qw(colonize);
no warnings 'uninitialized';

our @ISA = '::';      ## default to root class
# widgets

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub loop {
	package ::;
	$text->{term_attribs}->{already_prompted} = 0;
	$text->{term}->tkRunning(1);
  	while (1) {
  		my ($user_input) = $text->{term}->readline($prompt) ;
  		::process_line( $user_input );
  	}
}

sub initialize_tk { can_load( modules => { Tk => undef } ) }

# the following graphical methods are placed in the root namespace
# allowing access to root namespace variables 
# with a package path

package ::;
[% qx(cat ./Graphical_subs.pl ) %]

[% qx(cat ./Refresh_subs.pl ) %]

1;

__END__

