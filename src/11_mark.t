use Test2::Bundle::More;
use strict;
use ::Mark;
$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag ("TESTING $0\n");
my $mark  = ::Mark->new( name => 'thebeginning');

is(  ref $mark , '::Mark', "Object creation");

done_testing();
__END__

