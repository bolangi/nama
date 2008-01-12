use Test::More qw(no_plan);
use strict;

## Grab at anything nearby

use lib qw(.. .);

#use UI::Assign qw(:all);
# `make test'. After `make install' it should work as `perl 1.t'

BEGIN { 
	diag ("TESTING $0\n");
	use_ok('UI::Object') ;
}

diag "testing trivial class Apple";
package Apple;
our @ISA; 
use UI::Object qw(color);

package main;

my $apple = Apple->new(color => 'green');

is( ref $apple, 'Apple', "instantiation") ;

is( $apple->color, 'green', "accessor" ); 

$apple->set( color => 'red' );

is( $apple->color, 'red', "mutator" ); 

diag( $apple->dump );

1;

__END__
