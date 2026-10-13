use Test2::Bundle::More;
use v5.36;
use ::Lat;

my $lat = ::Lat->new(4,8);
my $lat2 = ::Lat->new(16,32);

ok($lat isa '::Lat', "Latency object instantiation");
is("$lat","4 8","Stringify object");
is($lat->min, 4, "Min latency accessor");
is_deeply( $lat->add_latency($lat2), ::Lat->new(20,40), "Latency addition");
is_deeply( ::Lat->new(20,40), ($lat + $lat2), "Latency addition, overloading '+' operator");
is(do{ eval {::Lat->new(1,0)}; defined $@}, 1, "Exception on Max greater than Min");

done_testing();
__END__
