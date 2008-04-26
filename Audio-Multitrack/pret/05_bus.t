use Test::More qw(no_plan);
use strict;
use Carp;
use_ok( '::Track' );
use ::Assign qw(yaml_out);

use ::Track;
use ::Bus;

my $mixer_out = ::Rule->new( #  this is the master fader
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

my $tracker  = ::Bus->new(
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

$::mix_to_disk_format = "mix-format";
$::raw_to_disk_format = "raw-format";
print join (" ", map{ my $rule = $_; $rule->name} ::Rule::all_rules() ), $/;

my $master_fader  = ::Bus->new(
	name => 'Master_Bus',
	rules  => [ qw(mixer_out) ],
);


my $tracker  = ::Bus->new(
	name => 'Tracker_Bus',
	groups => ['Tracker'],
	tracks => [],
	rules  => [],
);

#my $master_g = ::Group->new( name => 'Master');  # automatic

my $master = ::Track->new( group => 'Master', name => 'Master' );

my $mix = ::Track->new( group => 'Mixer', name => 'Mixes'); 

my $sax = ::Track->new( name => 'sax' );


my $piano  = ::Track->new( name => 'piano', ch_r => 2 );

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

my $mixer_out = $::Rule::by_name{mixer_out};
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

is( yaml_out( \%::inputs ). yaml_out(\%::outputs),
$mix_diag, "Master Fader setup");

__END__

