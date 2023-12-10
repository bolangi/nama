use Test2::Bundle::More;
use strict;
use ::Mark;
$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag ("TESTING $0\n");
my $mark  = ::Mark->new( name => 'thebeginning');


is(  ref $mark , '::Mark', "Object creation");
$mark->set_attrib( "gabble", "babble");
is( $mark->attrib("gabble"), 'babble', "attribute store and read");
is( $mark->gabble, 'babble', "attribute store and read");

done_testing();
__END__

