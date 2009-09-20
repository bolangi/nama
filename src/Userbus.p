# ---------- Userbus -----------
use strict;
package ::Userbus;
our $VERSION = 1.0;
our ($debug);
local $debug = 0;
use Carp;
our @ISA = ();

use ::Object qw( 		name
						destination

						);

# name, init capital e.g. Brass
# destination: 3, jconv, loop,output

sub new {
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	bless \%vals, $class;
	
}


1;
__END__
