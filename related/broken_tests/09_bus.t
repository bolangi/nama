package Audio::Multitrack;
use Audio::Multitrack;

Audio::Multitrack::prepare;

my $sax = Audio::Multitrack::Track->new( name => 'sax' );

my $piano  = Audio::Multitrack::Track->new( name => 'piano', ch_r => 2 );

use vars qw($ch_m, $ch_r); 
$ch_m = 3; $ch_r = 7;
add_track("vocal"); 

$sax->set(rw => 'MON');
map{ print $_->dump } map { $Audio::Multitrack::Track::by_name{$_} } ($Audio::Multitrack::tracker->tracks); 

#print keys %Audio::Multitrack::Track::by_name; exit;

print join $/,map{$_->name} map{$Audio::Multitrack::Rule::by_name{$_}} map{$_->name} Audio::Multitrack::Rule::all_rules;
$master_bus->apply;
$tracker_bus->apply;

#is ( yaml_out( \%Audio::Multitrack::inputs ). yaml_out(\%Audio::Multitrack::outputs), $nice_output, "Apply bus rules to generate chains");

print  yaml_out( \%Audio::Multitrack::inputs ). yaml_out(\%Audio::Multitrack::outputs);

Audio::Multitrack::write_chains();

print $ti[3]->name;
