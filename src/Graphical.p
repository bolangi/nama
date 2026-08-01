# ------------ Graphical User Interface ------------

package ::Graphical;  ## gui routines
use v5.36; use Carp;
our $VERSION = 1.071;
use ::Globals qw($text $prompt);

use Module::Load::Conditional qw(can_load);
use ::Assign qw(:all);
use ::Util qw(colonize);
no warnings 'uninitialized';

our @ISA = '::';      ## default to root namespace, e.g.  Refresh_subs, Graphical_subs
						# actually this doesn't seem like a
						# good idea
# widgets

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub loop {
	# Tk owns the graphical event loop.  Give IO::Async (and therefore
	# Tickit::Async) a nonblocking turn at regular intervals so terminal input,
	# timers, and engine I/O remain live while Tk is running.
	::start_terminal_ui();
	my $pump_async;
	$pump_async = sub {
		return unless Tk::Exists($::gui->{mw});
		$text->{loop}->loop_once(0);
		$::gui->{mw}->after(10, $pump_async);
	};

	$::gui->{mw}->afterIdle($pump_async);
	Tk::MainLoop();
}

sub initialize_tk { 
	my $result1 = can_load( modules => { Tk => undef } ) ;
	my $result2 = can_load( modules => { 'Tk::PNG' => undef } );
	$result1
}

# the following graphical methods are placed in the root namespace
# allowing access to root namespace variables 
# with a package path

package ::;
[% qx(cat ./Graphical_subs.pl ) %]

[% qx(cat ./Refresh_subs.pl ) %]

1;

__END__
