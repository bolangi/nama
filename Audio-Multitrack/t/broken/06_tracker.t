use Test::More qw(no_plan);
use strict;
use Carp;
#use aliased 'Audio::Multitrack::Track';
use_ok( 'Audio::Multitrack::Track' );
use Audio::Multitrack::Assign qw(yaml_out);

# *::inputs = \%Audio::Multitrack::Coreinputs; 

#use Audio::Multitrack::Group qw(group);


my $tracker  = Audio::Multitrack::Bus->new(
	name => 'Tracker_Bus',
	groups => ['Tracker'],
	tracks => [],
	rules  => [ qw( mix_file mix_setup rec_setup mon_setup rec_file) ],
	#rules  => [ qw( mix_setup mon_setup rec_setup rec_file) ],
	#rules  => [ qw( mix_setup mon_setup  rec_file rec_setup) ],
);

$Audio::Multitrack::mix_to_disk_format = "mix-format";
$Audio::Multitrack::raw_to_disk_format = "raw-format";
print join (" ", map{ $_->name} Audio::Multitrack::Rule::all_rules() ), $/;

my $master_fader  = Audio::Multitrack::Bus->new(
	name => 'Master_Bus',
	rules  => [ qw(mixer_out) ],
);

my $master = Audio::Multitrack::Track->new( group => 'Master', name => 'Master' );

my $mix = Audio::Multitrack::Track->new( group => 'Mixer', name => 'Mixes'); 

my $sax = Audio::Multitrack::Track->new( name => 'sax' );

is ( "@{$sax->versions}", "1 2 4", "Version checking (redundant?) ");

my $piano  = Audio::Multitrack::Track->new( name => 'piano', ch_r => 2 );

is ($piano->last, 1, "piano last");

is ( $sax->last, 4, "\$track->last");

is ( $piano->very_last, 4, "\$track->very_last (2)");

my $group = $Audio::Multitrack::Group::by_name{$sax->group};

print "group name: ", $group->name, $/;

#print keys %Audio::Multitrack::Track::by_name; exit;

map{ print $_->dump } map { $Audio::Multitrack::Track::by_name{$_} } ($group->tracks); 

print "tracks: ", $group->tracks , $/;
$master_fader->apply;

# test deref_code

my $code = sub { my $track = shift; $track->name  };
is ( Audio::Multitrack::Bus::deref_code($code, $sax), 'sax', "Deref_code function");

#print $tracker->dump; 

$tracker->apply;



my $nice_output = <<NICE;
---
cooked:
  loop,4:
    - J4
device:
  multi:
    - 4
    - R4
mixed:
  loop,222:
    - Mixer_out
...
---
cooked:
  loop,111:
    - J4
  loop,4:
    - 4
device:
  stereo:
    - Mixer_out
file:
  "./piano_5.wav raw-format":
    - R4
...
NICE

is ( yaml_out( \%Audio::Multitrack::inputs ). yaml_out(\%Audio::Multitrack::outputs), $nice_output, "Apply bus rules to generate chains");


#print  yaml_out( \%Audio::Multitrack::inputs ). yaml_out(\%Audio::Multitrack::outputs);



1;

__END__

