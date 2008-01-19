use Test::More qw(no_plan);
use strict;
use Carp;
use lib qw(. ..);
#use aliased 'UI::Track';
use_ok( 'UI::Track' );
use UI::Assign qw(yaml_out);

#use UI::Group qw(group);

*group = \&UI::Group::group; # no longer necessary
*track = \&UI::Track::track; # 

my $tracker  = UI::Bus->new(
	name => 'Tracker_Bus',
	groups => ['Tracker'],
	tracks => [],
	rules  => [ qw( rec_setup) ],
	#rules  => [ qw( mix_setup mon_setup rec_setup rec_file) ],
	#rules  => [ qw( mix_setup mon_setup  rec_file rec_setup) ],
);

$UI::mix_to_disk_format = "mix-format";
$UI::raw_to_disk_format = "raw-format";
print join (" ", map{ $_->name} UI::Rule::all_rules() ), $/;

my $master_fader  = UI::Bus->new(
	name => 'Master_Bus',
	rules  => [ qw(mixer_out) ],
);

my $master = UI::Track->new( group => 'Master', name => 'Master' );

my $mix = UI::Track->new( group => 'Mixer', name => 'Mixes'); 

my $sax = UI::Track->new( name => 'sax' );

is ( "@{$sax->versions}", "1 2 4", "Version checking (redundant?) ");

my $piano  = UI::Track->new( name => 'piano', ch_r => 2 );

is ($piano->last, 1, "piano last");

is ( $sax->last, 4, "\$track->last_version");

print "piano last version: ", $piano->last_version, $/;

print "overall: ", $piano->overall_version, $/; exit;
my $group = $UI::Group::by_name{$sax->group};

print "group name: ", $group->name, $/;

#print keys %UI::Track::by_name; exit;

map{ print $_->dump } map { $UI::Track::by_name{$_} } ($group->tracks); 

print "tracks: ", $group->tracks , $/;
#is ( $group->last_version, 4, "\$group->last_version");

# print "last tracker: " , group('Tracker','last'), $/;
#print &group( qw(Tracker last) ); exit; # no!!
# it's broken by the testing for fields somwhere,
# no that affects set

$master_fader->apply;

# test deref_code

my $code = sub { my $track = shift; $track->name  };
is ( UI::Bus::deref_code($code, $sax), 'sax', "Deref_code function");

#map{ ::Group::group( $_,  'tracks') } 
#print $tracker->dump; 
$tracker->apply;

exit;

print yaml_out( \%UI::inputs ). yaml_out(\%UI::outputs);
print map{ UI::Group::group( $_,  'tracks') }("Tracker");

1;

__END__

