use Test::More tests => 4;
use strict;


BEGIN { 
	use_ok('::Object') ;
}
$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag ("TESTING $0\n");
$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag "testing trivial class Apple";
package Apple;
our @ISA; 
use ::Object qw(color);

package main;

my $apple = Apple->new(color => 'green');

is( ref $apple, 'Apple', "instantiation") ;

is( $apple->color, 'green', "accessor" ); 

$apple->set( color => 'red' );

is( $apple->color, 'red', "mutator" ); 

#$apple->color = 'blue'; 

#is( $apple->color, 'blue', "lvalue" ); 

1;

__END__
