# ---------- IO -----------

package ::IO; # base class for all IO objects
use Modern::Perl;
our $VERSION = 1.0;
our ($debug);
local $debug = 0;
use Carp;
our @ISA = ();
use vars qw($n @all %by_index) ;

use ::Object qw( 	direction
					type
					id
					format
					channel
					width

					ecasound_id
					post_input
					pre_output
				);

# unnecessary: direction (from class) type (claass) 
#

$n = 0;

sub new {
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	my $n = $vals{n} // ++$n; 
	my $self = bless { n => $n, @_ }, $class;
	push @all, $self;
	$by_index{"I$n"} = $self;
	$self;
	
}

package ::IO::Source::Soundcard;
our @ISA = '::IO';
=comment
add_io(track => sax, direction => source, io_type => soundcard, 
	io_id => consumer channel => 3, width => 2);


modify_io
=cut

	
package ::IO::Sink::Soundcard;
our @ISA = '::IO';

package ::IO::Source::Jack_client;
our @ISA = '::IO';

	
package ::IO::Sink::Jack_client;
our @ISA = '::IO';

package ::IO::Sink::Track;
our @ISA = '::IO';

package ::IO_Helper;
use strict;
our $VERSION = 1.0;
our ($debug);
local $debug = 0;
use Carp;
our @ISA = ();

use ::Object qw( 		type
						object
						format

						);

# type (string): loop, device, file, etc.
# object (string): Ecasound device, with optionally appended format string
# format (string): Ecasound format string



sub new {
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	bless \%vals, $class;
	
}


1;
__END__
