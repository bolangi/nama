# ---------- IO -----------
use strict;
package ::IO;
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
