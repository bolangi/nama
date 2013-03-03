use Test::More qw(no_plan);
use strict;

BEGIN { 
	use_ok('::Mark') ;
}
$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag ("TESTING $0\n");
my $mark  = ::Mark->new( name => 'thebeginning');

is(  ref $mark , '::Mark', "Object creation");

1;
__END__

diag("Serializing, storing$ENV{NAMA_VERBOSE_TEST_OUTPUT} recalling data");
is( $foo, 2, "Scalar number assignment");
is( $name, 'John', "Scalar string assignment");
my $sum;
map{ $sum += $_ } @face;
is ($sum, 25, "Array assignment");
is( $dict{fruit}, 'melon', "Hash assignment");
is ($serialized, $expected, "Serialization round trip");


