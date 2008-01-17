use Test::More qw(no_plan);
use lib qw(. ..);
use_ok( 'UI::Track' );
use UI::Assign qw(yaml_out);


# $mixer_out->dump;
# Don't know how to encode CODE at ../UI/Assign.pm line 253

my $tracker  = UI::Bus->new(
	name => 'Tracker_Bus',
	groups => ['Tracker'],
	tracks => [],
	rules  => [],
);

my $td = <<'TRACKER';
---
groups:
  - Tracker
name: Tracker_Bus
rules:
tracks:
...
TRACKER

is ($tracker->dump, $td, "Tracker bus");

my $master_fader  = UI::Bus->new(
	name => 'Master_Bus',
	rules  => [ $mixer_out ],
);

my $tracker  = UI::Bus->new(
	name => 'Tracker_Bus',
	groups => ['Tracker'],
	tracks => [],
	rules  => [],
);

my $master_g = UI::Group->new( name => 'Master'); 
#print keys %UI::Group::by_name; 
#exit;
#print (map{ref $$_} values %UI::Group::by_name);  exit;
my $master = UI::Track->new( group => 'Master', name => 'Master' );
#print keys %UI::Track::by_name; 
#print (map{ref $$_} values %UI::Track::by_name);  exit;
#print "-------\n";
#print keys %UI::Group::by_name; 
#exit;
#print "-------\n";
#my $ref = $UI::Group::by_name{Master};
#print ref $ref; 
#print ref $$ref; 
#print "-------\n";
#$ref = $UI::Group::by_index[1];
#print ref $ref; 
#print ref $$ref; 
#print "-------\n";
#exit;
#print keys %UI::Group::by_name; 
#$$master_g->set( tracks => [qw( Test )] );
#exit;
#$$master_g->dump; exit;
${$UI::Group::by_name{Master}}->dump; exit;
#$$master_g->dump; exit;
my $mix_g = UI::Group->new( name => 'Mixer');
my $mix = UI::Track->new( group => 'Mixer', name => 'Mixes'); 
my $tracker = UI::Group->new( name => 'Tracker' );
my $sax = UI::Track->new( name => 'sax' );
my $piano  = UI::Track->new( name => 'piano' );

#print join " ", @{ ${$UI::Group::by_name{Tracker}}->tracks }; exit;
print ref ${$UI::Group::by_name{Tracker}}; exit;
my $track_diag = <<TRACK;
---
group: Tracker
n: 3
name: sax
rw: REC
...
TRACK

is( $$sax->dump, $track_diag, "Track object instantiation and serialization");

my $mix_diag = <<MIXDIAG;
---
mixed:
  loop,222:
    - Mixer_out
...
---
device:
  stereo:
    - Mixer_out
...
MIXDIAG

$master_fader->apply;

is( yaml_out( \%UI::inputs ). yaml_out(\%UI::outputs),
	$mix_diag, "Master Fader setup");

$tracker  = UI::Bus->new(
	name => 'Tracker_Bus',
	groups => ['Tracker'],
	tracks => [],
	rules  => [ qw( mix_setup mon_setup  rec_file rec_setup) ],
);

__END__

at the moment, Track and Group new methods return
references to objects.
