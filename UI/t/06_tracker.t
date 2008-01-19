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
	rules  => [ qw( mix_setup mon_setup  rec_file rec_setup) ],
);

$UI::mix_to_disk_format = "mix-format";
$UI::raw_to_disk_format = "raw-format";
print join (" ", map{ my $rule = $$_; $rule->name} UI::Rule::all_rules() ), $/;

my $master_fader  = UI::Bus->new(
	name => 'Master_Bus',
	rules  => [ qw(mixer_out) ],
);

my $master = UI::Track->new( group => 'Master', name => 'Master' );

my $mix = UI::Track->new( group => 'Mixer', name => 'Mixes'); 

my $sax = UI::Track->new( name => 'sax' );

my $piano  = UI::Track->new( name => 'piano', ch_r => 2 );

$master_fader->apply;

#print &group( qw(Tracker tracks) ); exit;


#map{ ::Group::group( $_,  'tracks') } 
#print $tracker->dump; 
$tracker->apply;


print yaml_out( \%UI::inputs ). yaml_out(\%UI::outputs);
print map{ UI::Group::group( $_,  'tracks') }("Tracker");

1;

__END__

