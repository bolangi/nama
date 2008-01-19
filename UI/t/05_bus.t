use Test::More qw(no_plan);
use Carp;
use lib qw(. ..);
#use aliased 'UI::Track';
use_ok( 'UI::Track' );
use UI::Assign qw(yaml_out);

use UI::Track qw(track);

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

$UI::mix_to_disk_format = "mix-format";
$UI::raw_to_disk_format = "raw-format";
print join (" ", map{ my $rule = $$_; $rule->name} UI::Rule::all_rules() ), $/;

my $master_fader  = UI::Bus->new(
	name => 'Master_Bus',
	rules  => [ qw(mixer_out) ],
);

#$master_fader->dump; exit;

my $tracker  = UI::Bus->new(
	name => 'Tracker_Bus',
	groups => ['Tracker'],
	tracks => [],
	rules  => [],
);

#my $master_g = UI::Group->new( name => 'Master'); 

my $master = UI::Track->new( group => 'Master', name => 'Master' );

my $mix = UI::Track->new( group => 'Mixer', name => 'Mixes'); 

my $sax = UI::Track->new( name => 'sax' );

#print ref $tracker; exit;
#${$tracker}->dump; exit;

my $piano  = UI::Track->new( name => 'piano', ch_r => 2 );

#print track(qw(piano rw)); exit;
is (  (track qw(piano name)), 'piano', "Exported track function 1" );
is ( (track qw(piano rw)), 'REC', "Exported track function 2" );

is ($$piano->rec_status , 'REC', "Rec_status function"); 

# print join " ", @{ ${$UI::Group::by_name{Tracker}}->tracks }; exit;
#my $tracker = $UI::Group::by_name{Tracker}; 
#print "--------\n";
#$$tracker->dump; exit;
#print ref ${$UI::Group::by_name{Tracker}}; exit;

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

#$master_fader->dump; exit;
#print @{ $master_fader->rules} ; exit;

$master_fader->apply;

is( yaml_out( \%UI::inputs ). yaml_out(\%UI::outputs),
	$mix_diag, "Master Fader setup");

$tracker  = UI::Bus->new(
	name => 'Tracker_Bus',
	groups => ['Tracker'],
	tracks => [],
	rules  => [ qw( mix_setup mon_setup  rec_file rec_setup) ],
);

$tracker->apply;
print yaml_out( \%UI::inputs ). yaml_out(\%UI::outputs);

1;
__END__

