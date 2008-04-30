use Test::More qw(no_plan);
use strict;


BEGIN { 
	diag ("TESTING $0\n");
	use_ok('Audio::Multitrack::Object') ;
}

diag "testing trivial class Apple";
package Apple;
our @ISA; 
use Audio::Multitrack::Object qw(color);

package main;

my $apple = Apple->new(color => 'green');

is( ref $apple, 'Apple', "instantiation") ;

is( $apple->color, 'green', "accessor" ); 

$apple->set( color => 'red' );

is( $apple->color, 'red', "mutator" ); 

diag( $apple->dump );

1;

__END__
