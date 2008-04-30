use Test::More qw(no_plan);
use strict;
use Carp;
use_ok( 'Audio::Multitrack::Track' );
use Audio::Multitrack::Assign qw(yaml_out);

use Audio::Multitrack::Track;
use Audio::Multitrack::Bus;

my $mixer_out = Audio::Multitrack::Rule->new( #  this is the master fader
	name			=> 'mixer_out', 
	chain_id		=> 'Mixer_out',

	target			=> 'none',

# condition =>	
	# sub{ defined $inputs{mixed}  or $debug and print("no customers for mixed, skipping\n"), 0},

	input_type 		=> 'mixed', # bus name
	input_object	=> 'loop,222', 

	output_type		=> 'device',
	output_object	=> 'stereo',

	status			=> 1,

);


# $mixer_out->dump;
# Don't know how to encode CODE at ../::/Assign.pm line 253

my $tracker  = Audio::Multitrack::Bus->new(
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

$Audio::Multitrack::mix_to_disk_format = "mix-format";
$Audio::Multitrack::raw_to_disk_format = "raw-format";
print join (" ", map{ my $rule = $_; $rule->name} Audio::Multitrack::Rule::all_rules() ), $/;

my $master_fader  = Audio::Multitrack::Bus->new(
	name => 'Master_Bus',
	rules  => [ qw(mixer_out) ],
);


my $tracker  = Audio::Multitrack::Bus->new(
	name => 'Tracker_Bus',
	groups => ['Tracker'],
	tracks => [],
	rules  => [],
);

#my $master_g = Audio::Multitrack::Group->new( name => 'Master');  # automatic

my $master = Audio::Multitrack::Track->new( group => 'Master', name => 'Master' );

my $mix = Audio::Multitrack::Track->new( group => 'Mixer', name => 'Mixes'); 

my $sax = Audio::Multitrack::Track->new( name => 'sax' );


my $piano  = Audio::Multitrack::Track->new( name => 'piano', ch_r => 2 );

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

my $mixer_out = $Audio::Multitrack::Rule::by_name{mixer_out};
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

is( yaml_out( \%Audio::Multitrack::inputs ). yaml_out(\%Audio::Multitrack::outputs),
$mix_diag, "Master Fader setup");

__END__

