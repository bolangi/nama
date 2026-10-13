use Test2::Bundle::More;
use v5.36;

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag ("TESTING $0\n");
$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag "testing trivial class Apple";
package Apple;
our @ISA; 
use ::Object qw(color);

package main;

my $apple = Apple->new(color => 'green');

ok( $apple isa 'Apple', "instantiation") ;

is( $apple->color, 'green', "accessor" ); 

$apple->set( color => 'red' );

is( $apple->color, 'red', "mutator" ); 

#$apple->color = 'blue'; 

#is( $apple->color, 'blue', "lvalue" ); 

done_testing()

__END__
