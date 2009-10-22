package ::;
use Test::More qw(no_plan);
use strict;
use warnings;
no warnings qw(uninitialized);
use Cwd;

BEGIN { use_ok('::IO') };

# `make test'. After `make install' it should work as `perl 1.t'

diag ("TESTING $0\n");

=comment
my $io = ::IO->new( qw[ type raw
						object loop,mix
						format s16_le,2,44100 ] );

	is( $io->type, 'raw', 'IO object create, access');
=cut

1;
__END__
