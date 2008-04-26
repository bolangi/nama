package ::;
use ::;

::prepare;

my $sax = ::Track->new( name => 'sax' );

my $piano  = ::Track->new( name => 'piano', ch_r => 2 );

use vars qw($ch_m, $ch_r); 
$ch_m = 3; $ch_r = 7;
add_track("vocal"); 

$sax->set(rw => 'MON');
map{ print $_->dump } map { $::Track::by_name{$_} } ($::tracker->tracks); 

#print keys %::Track::by_name; exit;

print join $/,map{$_->name} map{$::Rule::by_name{$_}} map{$_->name} ::Rule::all_rules;
$master_bus->apply;
$tracker_bus->apply;

#is ( yaml_out( \%::inputs ). yaml_out(\%::outputs), $nice_output, "Apply bus rules to generate chains");

print  yaml_out( \%::inputs ). yaml_out(\%::outputs);

::write_chains();

print $ti[3]->name;
