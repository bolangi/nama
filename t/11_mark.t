use Test::More qw(no_plan);
use strict;

BEGIN { 
	diag ("TESTING $0\n");
	use_ok('Audio::Ecasound::Multitrack::Mark') ;
}
my $mark  = Audio::Ecasound::Multitrack::Mark->new( name => 'thebeginning');

is(  ref $mark , 'Audio::Ecasound::Multitrack::Mark', "Object creation");

1;
__END__

diag("Serializing, storing and recalling data");
is( $foo, 2, "Scalar number assignment");
is( $name, 'John', "Scalar string assignment");
my $sum;
map{ $sum += $_ } @face;
is ($sum, 25, "Array assignment");
is( $dict{fruit}, 'melon', "Hash assignment");
is ($serialized, $expected, "Serialization round trip");


