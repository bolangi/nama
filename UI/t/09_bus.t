use lib qw(.. .);
package UI;
use UI;

UI::prepare;

my $sax = UI::Track->new( name => 'sax' );

my $piano  = UI::Track->new( name => 'piano', ch_r => 2 );

use vars qw($ch_m, $ch_r); 
$ch_m = 3; $ch_r = 7;
add_track("vocal"); 

$sax->set(rw => 'MON');
map{ print $_->dump } map { $UI::Track::by_name{$_} } ($UI::tracker->tracks); 

#print keys %UI::Track::by_name; exit;

print join $/,map{$_->name} map{$UI::Rule::by_name{$_}} map{$_->name} UI::Rule::all_rules;
$master_bus->apply;
$tracker_bus->apply;

#is ( yaml_out( \%UI::inputs ). yaml_out(\%UI::outputs), $nice_output, "Apply bus rules to generate chains");

print  yaml_out( \%UI::inputs ). yaml_out(\%UI::outputs);

UI::write_chains();

print $ti[3]->name;
