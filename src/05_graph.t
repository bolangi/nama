use Test::More qw(no_plan);
use strict;

BEGIN { 
	diag ("TESTING $0\n");
	use_ok('::Graph') ;
}
use Graph;
my $g = Graph->new;

$g->add_path(qw[ wav_in piano Master Eq Low Boost soundcard_out]) ;
$g->add_path(qw[ Eq High Boost]);
$g->add_path(qw[ Eq Low Boost]);

::Graph::expand_graph($g);

my $expanded = "$g";

my $expected =
'Boost-soundcard_out,Boost_in-Boost,Eq-Eq_out,Eq_out-High,Eq_out-Low,High-Boost_in,Low-Boost_in,Master-Master_out,Master_in-Master,Master_out-Eq,piano-Master_in,wav_in-piano'
;
is( $expanded, $expected, "graph loop expansion");

1;
__END__

