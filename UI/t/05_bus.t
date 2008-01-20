use Test::More qw(no_plan);
use strict;
use Carp;
use lib qw(. ..);
#use aliased 'UI::Track';
use_ok( 'UI::Track' );
use UI::Assign qw(yaml_out);

#use UI::Group qw(group);

*group = \&UI::Group::group;
*track = \&UI::Track::track;


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
print join (" ", map{ my $rule = $_; $rule->name} UI::Rule::all_rules() ), $/;

my $master_fader  = UI::Bus->new(
	name => 'Master_Bus',
	rules  => [ qw(mixer_out) ],
);


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


my $piano  = UI::Track->new( name => 'piano', ch_r => 2 );

is (  (&track qw(piano name)), 'piano', "Aliased track function" );
is ( (&group qw(Tracker rw)), 'REC', "Aliased group function" );
is ($piano->rec_status , 'REC', "Rec_status function"); 

my $track_diag = <<TRACK;
---
dir: .
group: Tracker
n: 3
name: sax
rw: REC
...
TRACK

is( $sax->dump, $track_diag, "Track object instantiation and serialization");

my $mixer_out = $UI::Rule::by_name{mixer_out};
$mixer_out->set( condition => 1);  

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

#  Temporarily disabled till we fix Tracker apply
$master_fader->apply;

is( yaml_out( \%UI::inputs ). yaml_out(\%UI::outputs),
$mix_diag, "Master Fader setup");

__END__

