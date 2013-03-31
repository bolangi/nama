use Test::More qw(no_plan);
use strict;

BEGIN { use_ok(qw(::Lat) ) };

my $lat = ::Lat->new(4,8);
is(ref $lat, '::Lat', "Latency object instantiation");

1;
__END__
