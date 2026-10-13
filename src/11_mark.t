use Test2::Bundle::More;
use v5.36;
use ::Mark;
$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag ("TESTING $0\n");
my $mark  = ::Mark->new( name => 'thebeginning');

ok( $mark isa '::Mark', "Object creation");

done_testing();
__END__

