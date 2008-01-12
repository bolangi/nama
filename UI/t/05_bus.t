use lib qw(. ..);
use UI::Track;
use UI::Assign qw(yaml_out);


my $stereo = UI::Rule->new(
	name			=> 'stereo',
	chain_id		=> sub{ 'Stereo' },

	target			=> 'none',
	depends_on		=> sub{},

	input_type 		=> 'mixed',
	input_object	=> 'loop,222', # $loopb 

	output_type		=> 'device',
	output_object	=> 'stereo',

	default			=> 'on',

);
my $track_bus = UI::Bus->new(
	name => 'Tracker',
	groups => ['Tracker'],
	tracks => [],
	rules  => [],
);

my $master_fader  = UI::Bus->new(
	name => 'Master',
	rules  => [ $stereo ],
);

$master_fader->apply;
print yaml_out( \%UI::inputs);
print yaml_out( \%UI::outputs);


my %rules;

$rules{ $stereo->name } = $stereo;
