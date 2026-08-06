package ::; 
use ::;
use Test2::Bundle::More;
use File::Path qw(make_path remove_tree);
use Path::Tiny qw(path);
use Cwd;

use strict;
use warnings;
no warnings qw(uninitialized);

our ($expected_setup_lines);

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag ("TESTING $0\n");

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag("working directory: ",cwd);

our $test_dir = "/tmp/nama-test";
$fx_cache->{fake} = path("t/data/fake_effects_cache.json")->slurp_utf8;

cleanup_dirs();
setup_dirs();

sub cleanup_dirs { 	chdir('..'), remove_tree($test_dir) if -e $test_dir }
sub setup_dirs{ make_path("$test_dir/test/.wav", "$test_dir/untitled/.wav") }

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag( qx(find $test_dir) );

apply_test_args();

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag "options: @ARGV";
bootstrap_environment();
$config->{use_git} = 0;

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag "Check representative variable from default .namarc";

is( $config->{mix_to_disk_format}, "s16_le,N,44100,i", "Read mix_to_disk_format");
is( $config->{edit_realtime}, 1, "Realtime edit playback is enabled by default");

is(::Effect::fade_level(25, 75, 1, 2), 50,
	'fade step is calculated as an absolute level');
is(::Effect::fade_level(75, 25, 1, 2), 50,
	'absolute fade levels work in both directions');

is(::Effect::fade_step_count(0.03), 5,
	'short fades use the minimum operation count');
is(::Effect::fade_step_count(0.18), 18,
	'ordinary fades follow the configured resolution');
is(::Effect::fade_step_count(2), 20,
	'long fades use the maximum operation count');
is(::Effect::fade_step_count(0), 0,
	'a zero-length fade has no intermediate operations');

# object id => type mappings
#
my @id_to_type = (
	1 						=> 'soundcard',
    Fluidsynth 				=> 'jack_client',
	"MPlayer [20120]:out_0" => 'jack_client',
	"drumkit.ports"			=> 'jack_ports_list',
	manual					=> 'jack_manual',
	jack					=> 'jack_manual',
	bus						=> 'bus',
	null					=> 'null',
	"loop,16"				=> 'loop',
	"loop,Main"			=> 'loop',
);

while( my($dest,$type) = splice @id_to_type, 0,2){
	is( dest_type($dest), $type, "$dest => $type");
}

my $test_project = 'test';

load_project(name => $test_project, create => 1);

{
	local $config->{realtime_profile} = 'nonrealtime';
	local $config->{edit_realtime} = 1;
	local $setup->{timeline_adjustment} = { type => 'edit' };
	local $this_edit = bless {}, '::Edit';
	ok(::ChainSetup::setup_requires_realtime(),
		'edit mode overrides the nonrealtime profile');
}

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag("project project dir: ".project_dir());
$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag("project project wav dir: ".this_wav_dir());

#diag(map{ $_->dump} values %::Track::by_index );

is( project_dir(), "$test_dir/$test_project", "establish project directory");

is( ref $bn{Main}, q(Audio::Nama::SubBus), 'Bus initializtion');

is($tn{Main}->candidate_rw, MON,
	'Main candidate rw is MON when enabled');
ok($tn{Main}->candidate_mon,
	'Main candidate MON follows candidate rw');
ok(!$tn{Main}->candidate_rec,
	'Main candidate REC follows candidate rw');
is($tn{Main}->rec_status, $tn{Main}->candidate_rw,
	'rec_status delegates to candidate_rw');
$tn{Main}->set(rw => OFF);
is($tn{Main}->candidate_rw, OFF,
	'Main candidate rw is OFF when disabled');
$tn{Main}->set(rw => MON);


force_jack();

### Unit Tests for ::IO.pm

my @io_test_data = split "\n\n",
my $yaml = q(---
-
  class: from_null
  ecs_string: -i:null
-
  class: to_null
  ecs_string: -o:null
-
  class: to_wav
  args:
    name: sax
    width: 1
    full_path: /foo/.wav/sax_1.wav
  ecs_string: -f:s16_le,1,44100,i -o:/foo/.wav/sax_1.wav
-
  class: from_wav
  args:
    playat_output: playat,5
    select_output: select,1,4
    modifiers:
    full_path: test_dir/sax_1.wav
  ecs_string: -i:playat,5,select,1,4,test_dir/sax_1.wav
-
  class: from_loop
  args:
    endpoint: sax_in
  ecs_string: -i:loop,sax_in
-
  class: to_loop
  args:
    endpoint: sax_out
  ecs_string: -o:loop,sax_out
-
  class: to_alsa_soundcard_device
  ecs_string: -o:alsa,default
-
  class: from_alsa_soundcard_device
  ecs_string: -i:alsa,default
-
  class: from_soundcard
  args:
    width: 1
    source_id: 2
    source_type: soundcard
  ecs_string: -i:jack_multi,system:capture_2
-
  class: to_soundcard
  args:
    width: 2
    send_id: 5
    send_type: soundcard
  ecs_string: -o:jack_multi,system:playback_5,system:playback_6
-
  class: to_jack_port
  args:
    width: 1
    port_name: sax
  ecs_string: -f:f32_le,1,44100 -o:jack,,sax_out
-
  class: from_jack_port
  args:
    port_name: sax
    width: 2
  ecs_string: -f:f32_le,2,44100 -i:jack,,sax_in
-
  class: from_jack_client
  args:
    source_id: Horgand
    source_type: jack_client
  ecs_string: -i:jack,Horgand
-
  class: to_jack_client
  args:
    send_id: system
    send_type: jack_client
  ecs_string: -o:jack,system
-
  class: to_jack_multi
  args:
    width: 2
    send_id: system
    send_type: jack_multi
  ecs_string: -o:jack_multi,system:playback_1,system:playback_2
-
  class: from_jack_multi
  args:
    width: 2
    source_id: Horgand
    source_type: jack_client
  ecs_string: -i:jack_multi,Horgand:out_1,Horgand:out_2
...);

my @test = @{yaml_in($yaml)};

is(
	yaml_in('name: one-line YAML')->{name},
	'one-line YAML',
	'yaml_in treats a non-file string as YAML text',
);


my $i;

for (@test) {
	my %t = %$_;
	$i++;
	$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag "IO.pm unit test $i";
	my $class = "Audio::Nama::IO::$t{class}";
	my $io = $class->new(%{$t{args}});
	my @keys = sort grep{ $_ ne 'class'} keys %t;
	is( $io->ecs_string, $t{ecs_string}, "$t{class} ecs_string");
}
	

force_alsa();

nama_cmd('add sax');

like(ref $this_track, qr/Track/, "track creation"); 

is( $this_track->name, 'sax', "current track assignment");

{
	my $track = $tn{sax};
	my $original_level = $track->vol_level;
	transition_tracks({ mute => ['sax'] });
	is($track->vol_level, $track->volume_effect->mute_level,
		'a coordinated mute reaches the mute level');
	is($track->old_vol_level, $original_level,
		'a coordinated mute saves the original level');

	@{$fx->{muted}} = ('sax');
	nosolo();
	ok(defined $track->old_vol_level,
		'nosolo leaves a previously muted track muted');
	is_deeply($fx->{muted}, [], 'nosolo clears its saved mute list');

	transition_tracks({ unmute => ['sax'] });
	is($track->vol_level, $original_level,
		'a coordinated unmute restores the original level');
	ok(! defined $track->old_vol_level,
		'a coordinated unmute clears the saved level');
}

$this_track->set(group => 'Null');
ok(!$this_track->is_used, 'idle track is not currently used');
is($this_track->candidate_rw, MON,
	'candidate rw does not depend on graph use');
ok(!$this_track->effective_mon,
	'effective rw are false before graph resolution');
$this_track->set(group => 'Main');

{
	local $::ChainSetup::g = Graph->new;
	$::ChainSetup::g->add_edge('sax', 'soundcard_out');
	my $report = ::ChainSetup::prune_graph();
	is_deeply($report->{removed},
		[{ track => 'sax', reason => 'no-source' }],
		'pruning reports a track without a source');
	my $resolution = $this_track->resolve_rw_status;
	is($resolution->{requested}, MON, 'resolution records requested status');
	is($resolution->{candidate_rw}, MON, 'resolution records candidate rw');
	ok($resolution->{in_candidate_graph}, 'track entered candidate graph');
	ok(!$resolution->{in_final_graph}, 'track did not survive final graph');
	is($resolution->{reason}, 'no-source', 'resolution records no-source reason');
	like($this_track->why, qr/graph branch had no viable source/,
		'why explains no-source pruning');
	like($this_track->why,
		qr/Requested rw: MON\nCandidate rw: MON\nEffective rw: OFF\n/,
		'why presents the three resolved rw values in order');
	unlike($this_track->why, qr/\b(?:Current|Resolved)\b/,
		'why omits current and resolved qualifiers');
	is($this_track->effective_rw, OFF,
		'a pruned track has effective rw OFF');
	ok($this_track->effective_off,
		'effective OFF predicate follows graph resolution');
	ok(!$this_track->effective_mon,
		'effective MON predicate rejects a pruned candidate');
	ok($this_track->mon,
		'MON alias follows requested rw after pruning');
	ok(!$this_track->off,
		'OFF alias does not follow effective graph status');
	is($this_track->rec_status, OFF,
		'rec_status uses effective rw after pruning');
	my ($snapshot) = grep { $_->{name} eq 'sax' }
		@{status_snapshot()->{tracks}};
	is($snapshot->{candidate_rw}, MON,
		'status snapshot uses candidate rw before graph resolution');
	ok(!exists $snapshot->{rec_status},
		'status snapshot does not depend on effective rec_status');
	$this_track->set(rw => REC);
	is($this_track->current_version, $this_track->last + 1,
		'current version does not depend on effective graph status');
	is($this_track->current_wav,
		'sax_' . ($this_track->last + 1) . '.wav',
		'current WAV does not depend on effective graph status');
	is($this_track->full_path,
		::join_path(this_wav_dir(), $this_track->current_wav),
		'full path does not depend on effective graph status');
	my ($rec_snapshot) = grep { $_->{name} eq 'sax' }
		@{status_snapshot()->{tracks}};
	is($rec_snapshot->{current_version}, $this_track->last + 1,
		'status snapshot uses graph-independent current version');
	$this_track->set(rw => MON);
}

{
	local $::ChainSetup::g = Graph->new;
	$::ChainSetup::g->add_edge('soundcard_in', 'sax');
	my $report = ::ChainSetup::prune_graph();
	is_deeply($report->{removed},
		[{ track => 'sax', reason => 'no-sink' }],
		'pruning reports a track without a sink');
	is($this_track->resolve_rw_status->{reason}, 'no-sink',
		'resolution records no-sink reason');
}

{
	local $::ChainSetup::g = Graph->new;
	$::ChainSetup::g->add_path('soundcard_in', 'sax', 'soundcard_out');
	::ChainSetup::prune_graph();
	is($this_track->effective_rw, MON,
		'a surviving track retains its candidate rw');
	is($this_track->rec_status, MON,
		'rec_status uses surviving effective rw');
	my $resolution = $this_track->resolve_rw_status;
	is($resolution->{requested}, MON, 'survivor records requested status');
	is($resolution->{candidate_rw}, MON, 'survivor records candidate rw');
	is($resolution->{effective_rw}, MON, 'survivor records effective rw');
	ok($resolution->{in_candidate_graph}, 'survivor entered candidate graph');
	ok($resolution->{in_final_graph}, 'survivor remains in final graph');
	ok(!defined $resolution->{reason}, 'survivor has no failure reason');
	$resolution->{effective_rw} = OFF;
	is($this_track->effective_rw, MON,
		'track status resolution is returned as a snapshot');
	my $message;
	{
		no warnings 'redefine';
		local *::terminal_say = sub { $message = join '', @_ };
		$this_track->set_rw(OFF);
	}
	is($message, 'Track sax set to OFF',
		'set-rw feedback uses new candidate rw, not old graph status');
	ok((grep { $_ eq 'sax' } ::bunch_tracks('off')),
		'lowercase status bunch selects requested rw');
	ok((grep { $_ eq 'sax' } ::bunch_tracks('MON')),
		'uppercase status bunch selects effective graph status');
	my $source_message;
	{
		no warnings 'redefine';
		local *::terminal_say = sub { $source_message = join '', @_ };
		nama_cmd('source');
	}
	like($source_message, qr/however track is OFF/,
		'source query uses candidate rw, not old graph status');
	$this_track->set(rw => MON);
}

{
	local $::ChainSetup::g = Graph->new;
	$this_track->set(rw => REC);
	$::ChainSetup::g->add_path('soundcard_in', 'sax', 'wav_out');
	::ChainSetup::prune_graph();
	is_deeply(
		[map { $_->name } ::ChainSetup::engine_wav_out_tracks()],
		['sax'],
		'engine WAV outputs use effective recording status',
	);
	$this_track->set(rw => MON);
}

{
	local $::ChainSetup::g = Graph->new;
	$this_track->set(rw => OFF);
	::ChainSetup::prune_graph();
	my $resolution = $this_track->resolve_rw_status;
	is($resolution->{candidate_rw}, OFF,
		'candidate-OFF track is included in resolution report');
	ok(!$resolution->{in_candidate_graph},
		'candidate-OFF track did not enter candidate graph');
	is($resolution->{reason}, 'requested-off',
		'resolution explains requested OFF');
	like($this_track->why, qr/track was requested OFF/,
		'why explains candidate-OFF track');
	$this_track->set(rw => MON);
}

{
	local $::ChainSetup::g = Graph->new;
	::ChainSetup::prune_graph();
	my $resolution = $this_track->resolve_rw_status;
	is($resolution->{candidate_rw}, MON,
		'non-OFF candidate absent from graph is included in report');
	ok(!$resolution->{in_candidate_graph},
		'unconnected candidate did not enter candidate graph');
	is($resolution->{reason}, 'not-connected',
		'resolution records candidate not connected to graph');
	like($this_track->why, qr/not connected to the routing graph/,
		'why explains candidate not connected to graph');
}
::ChainSetup::clear_rw_status();

my ($vol_id) = $this_track->vol;

ok(   (defined $vol_id and $::Effect::by_id{$vol_id}) , "apply volume control");

nama_cmd('add_effect time_reverb3');

like( this_op_o()->about->{code}, qr/time_reverb3/, "apply preset");

is (this_op_o()->track_effect_index, 0, "positioned before vol/pan faders");

nama_cmd('add_effect decimator 1 2');


like( this_op_o()->about->{code}, qr/decimator/, "apply LADSPA effect");
is( this_op_o()->track_effect_index, 1, "position before faders, after other effects");

is($this_track->op_id, $this_track->op,
	'op_id aliases the selected effect ID');
is($this_track->selected_effect, this_op_o(),
	'selected_effect returns the selected Effect object');
is_deeply($this_track->effect_ids, $this_track->ops,
	'effect_ids aliases the serialized effect IDs');
is_deeply([$this_track->user_effect_ids], [$this_track->user_ops],
	'user_effect_ids aliases user effect IDs');
is_deeply(
	[map { $_->id } $this_track->user_effects],
	[$this_track->user_effect_ids],
	'user_effects resolves user effect IDs to objects',
);
is($this_track->volume_effect, $this_track->volume_effect,
	'volume_effect returns the volume Effect object');
is($this_track->pan_effect, $this_track->pan_effect,
	'pan_effect returns the pan Effect object');
is($this_track->vol_id, $this_track->vol,
	'vol_id aliases the volume effect ID');
is($this_track->pan_id, $this_track->pan,
	'pan_id aliases the pan effect ID');

my $volume_effect = $this_track->volume_effect;
is($volume_effect->parent_id, $volume_effect->{parent},
	'parent_id returns the serialized parent effect ID');
is_deeply($volume_effect->owned_ids, $volume_effect->owns,
	'owned_ids aliases the serialized owned effect IDs');
is_deeply(
	[map { $_->id } $volume_effect->owned_effects],
	$volume_effect->owned_ids,
	'owned_effects resolves owned effect IDs to objects',
);
is_deeply([$volume_effect->controller_ids], [$volume_effect->controllers],
	'controller_ids aliases controller IDs');
is_deeply(
	[map { $_->id } $volume_effect->controller_effects],
	[$volume_effect->controller_ids],
	'controller_effects resolves controller IDs to objects',
);

{
	my $effect_chain = bless {
		ops_list => [qw(template-parent template-controller)],
		ops_data => {
			'template-parent' => {
				type   => 1,
				params => [],
			},
			'template-controller' => {
				type       => 2,
				params     => [],
				belongs_to => 'template-parent',
			},
		},
	}, '::EffectChain';

	my @created_with;
	my $next_runtime_id = 0;
	package ::EffectChainTestEffect {
		sub id { $_[0]->{id} }
	}
	no warnings 'redefine';
	local *::EffectChain::append_effect = sub {
		my ($args) = @_;
		push @created_with, { %$args };
		my $id = $args->{id} // 'runtime-' . ++$next_runtime_id;
		[bless { id => $id }, '::EffectChainTestEffect'];
	};

	{
		local *::EffectChain::fxn = sub { undef };
		$effect_chain->add_ops($this_track, {});
	}
	is($created_with[0]->{id}, 'template-parent',
		'EffectChain preserves an available parent ID');
	is($created_with[1]->{parent}, 'template-parent',
		'EffectChain preserves an available controller relationship');

	@created_with = ();
	{
		local *::EffectChain::fxn = sub { 1 };
		$effect_chain->add_ops($this_track, {});
		$effect_chain->add_ops($this_track, {});
	}
	is($created_with[1]->{parent}, 'runtime-1',
		'first application maps a controller to its runtime parent ID');
	is($created_with[3]->{parent}, 'runtime-3',
		'second application builds an independent runtime ID mapping');
	is($effect_chain->parent_id('template-controller'), 'template-parent',
		'applying an EffectChain does not mutate its template relationships');
}

nama_cmd('vol -2');

is( $this_track->volume_effect->params->[0], -2, "modify effect" );

nama_cmd(join " ", 'position_effect', this_op_o()->id, 'ZZZ');

is( $this_track->ops->[-1], this_op_o()->id, 
	'position effect at end, using ZZZ pseudo-id');

nama_cmd(join " ", 'position_effect', this_op_o()->id, $vol_id);

is( $this_track->ops->[this_op_o()->track_effect_index + 1], $vol_id, 
	"position effect before another effect");

my $op_id = this_op_o()->id;
nama_cmd("remove_effect $op_id");

ok( (not grep { $_ eq $op_id } @{$this_track->ops}), 'remove effect');

nama_cmd('source 2');

is( $this_track->source_type, 'soundcard', "set soundcard input");
is( $this_track->source_id,  2, "set input channel");

nama_cmd('send 5');

# track sax, source 2, send 5

is( $this_track->send_type, 'soundcard', 'set soundcard output');
is( $this_track->send_id, 5, 'set soundcard output');

# IO objects are generated from the graph only after pruning has resolved
# candidate rw into effective rw.
{
	local $::ChainSetup::g = Graph->new;
	$::ChainSetup::g->add_path('soundcard_in', 'sax', 'soundcard_out');
	::ChainSetup::prune_graph();
}

# this is ALSA dependent (i.e. no JACK running)

my $io = ::IO->new(track => 'sax');

like( ref $io, qr/IO$/, 'IO base class object');

$io = ::IO::to_alsa_soundcard_device->new(track => 'sax'); 

is($io->ecs_string, '-o:alsa,default', 'IO to_alsa_soundcard_device 1');
is($io->ecs_extra,  ' -chmove:1,5', 'IO to_alsa_soundcard_device 2');

$io = ::IO::to_soundcard->new(track => 'sax'); 

is($io->ecs_string, '-o:alsa,default', 'IO to_soundcard 1');
is($io->ecs_extra, ' -chmove:1,5', 'IO to_soundcard 2');

force_jack();


$io = ::IO::from_soundcard->new(track => 'sax'); 
like (ref $io, qr/from_jack_multi/, 'sound system ALSA/JACK detection: input');
is($io->ecs_string, '-i:jack_multi,system:capture_2', 'IO from_soundcard: jack 1');
is($io->ecs_extra, '-chcopy:1,2', 'IO from_soundcard: jack 2');


$io = ::IO::to_soundcard->new(track => 'sax'); 
like (ref $io, qr/to_jack_multi/, 'sound system ALSA/JACK detection: output');

is($io->ecs_string, '-o:jack_multi,system:playback_5', 'IO to_soundcard: jack 1');
ok(! $io->ecs_extra, 'IO to_soundcard: jack 2');

$io = ::IO::to_null->new(track => 'sax', device_id => 'alsa,default');

is($io->device_id, 'alsa,default', 'value overrides method call');

nama_cmd("sax; source Horgand; gen");
like( ::ChainSetup::ecasound_chain_setup(), qr/Horgand/, 'set JACK client as input');
nama_cmd("sax; source jack; gen");
like( ::ChainSetup::ecasound_chain_setup(), qr/jack,,sax_in/, 'set JACK port for manual input');

nama_cmd("sax; rec; source 2");


force_alsa();

nama_cmd('3; nosend; gen');

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Main_in
-a:3,R3 -i:alsa,default

# post-input processing

-a:R3 -chmove:2,1
-a:3 -chmove:2,1 -chcopy:1,2

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,Main_in
-a:R3 -f:s16_le,1,44100,i -o:/tmp/nama-test/test/.wav/sax_1.wav
EXPECTED

check_setup('ALSA basic setup' );

force_jack();
nama_cmd('gen');
$expected_setup_lines = <<EXPECTED;

# audio inputs

-a:1 -i:loop,Main_in
-a:3,R3 -i:jack_multi,system:capture_2

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,Main_in
-a:R3 -f:s16_le,1,44100,i -o:/tmp/nama-test/test/.wav/sax_1.wav

EXPECTED

check_setup('JACK basic setup' );

nama_cmd('3; mon; gen');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Main_in
-a:3 -i:jack_multi,system:capture_2

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,Main_in
EXPECTED

check_setup('JACK mon setup' );

force_alsa(); nama_cmd('gen');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Main_in
-a:3 -i:alsa,default

# post-input processing

-a:3 -chmove:2,1 -chcopy:1,2

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,Main_in

EXPECTED

check_setup('ALSA mon setup' );
nama_cmd('Main; send 5;gen');

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Main_in
-a:3 -i:alsa,default

# post-input processing

-a:3 -chmove:2,1 -chcopy:1,2

# pre-output processing

-a:1  -chmove:2,6 -chmove:1,5

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,Main_in
EXPECTED

check_setup('ALSA send-Main-to-alternate-channel setup' );
force_jack(); nama_cmd('gen');

$expected_setup_lines = <<EXPECTED;
-a:1 -i:loop,Main_in
-a:3 -i:jack_multi,system:capture_2

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_5,system:playback_6
-a:3 -o:loop,Main_in
EXPECTED
check_setup('JACK send-Main-to-alternate-channel setup' );

nama_cmd('for 4 5 6 7 8; remove_track quiet');
nama_cmd('Main; send 1');
nama_cmd('add_bus Horns; sax move_to_bus Horns; sax stereo');

$tn{Horns}->set(group => 'Null');
ok(!$tn{Horns}->is_used, 'idle bus mix track is not currently used');
my $horns_rw = $tn{Horns}->rw;
$tn{Horns}->set(rw => OFF);
ok($tn{Horns}->is_mixer,
	'bus mix-track identity does not depend on status');
$tn{Horns}->set(rw => $horns_rw);
my @horns_consumers = $bn{Horns}->candidate_consumers;
is(scalar @horns_consumers, 1,
	'bus finds candidate consumer without traversing graph use');
is($horns_consumers[0]->name, 'Horns',
	'bus candidate consumer is its mix track');
is(($bn{Horns}->wantme)[0]->name, 'Horns',
	'wantme remains a compatibility interface');
$tn{Horns}->set(group => 'Main');

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Main_in
-a:3 -i:alsa,default
-a:4 -i:loop,sax_out

# post-input processing

-a:3 -chmove:2,1 -chmove:3,2

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,sax_out
-a:4 -o:loop,Main_in
EXPECTED
gen_alsa();
check_setup('Bus - ALSA');
gen_jack();

$expected_setup_lines = <<EXPECTED;
-a:1 -i:loop,Main_in
-a:3 -i:jack_multi,system:capture_2,system:capture_3
-a:4 -i:loop,sax_out

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,sax_out
-a:4 -o:loop,Main_in
EXPECTED
check_setup('Bus - JACK');

nama_cmd('remove_bus Horns');
nama_cmd('add_submix_cooked Vo 5');
$expected_setup_lines = <<EXPECTED;

-a:1,4 -i:loop,sax_out
-a:3 -i:jack_multi,system:capture_2,system:capture_3

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,sax_out
-a:4 -o:jack_multi,system:playback_5,system:playback_6
EXPECTED
gen_jack();
check_setup('Create submix with output at soundcard - JACK');
nama_cmd('remove_bus Vo');
nama_cmd('sax mono');

###### Timeline conversion tests

{
package OffsetRunTestTrack;
use Role::Tiny::With;
with '::TrackRegion';

sub new { my ($class, %args) = @_; bless \%args, $class }
sub set {
	my ($self, %args) = @_;
	$self->{$_} = $args{$_} for keys %args;
}
sub name { $_[0]->{name} }
sub playat { $_[0]->{playat} }
sub region_start { $_[0]->{region_start} }
sub region_end { $_[0]->{region_end} }
sub wav_length { $_[0]->{wav_length} }
sub full_path { $_[0]->{full_path} }
sub modifiers { '' }
sub effective_rw { 'PLAY' }
sub width { 2 }
sub pan { undef }
sub wav_format { 's16_le,2,44100,i' }
sub fader { 'offset-test-fader' }

package OffsetRunTestEffect;
sub type { 'ea' }

package OffsetRunTestEngine;
sub valid_setup { 1 }

package OffsetRunTestUI;
sub save_palette {}

package ::;
}

{
local $setup->{timeline_adjustment};
is(
	::adjusted_time_from_timeline_position(37),
	37,
	'timeline position is unchanged without adjustment',
);
is(
	::timeline_position_from_adjusted_time(7),
	7,
	'adjusted time is unchanged without adjustment',
);

$setup->{timeline_adjustment} = {
	type => 'offset_run',
	timeline_play_start => 30,
	timeline_play_end => 60,
};
is(
	::adjusted_time_from_timeline_position(37),
	7,
	'timeline position converts to adjusted time',
);
is(
	::timeline_position_from_adjusted_time(7),
	37,
	'adjusted time converts to timeline position',
);
is(
	::Mark::time_from_tag('37.0'),
	'37.0',
	'time from tag remains a permanent timeline position',
);
is(
	::Mark::adjusted_time_from_tag('37.0'),
	7,
	'adjusted time from tag converts for an engine consumer',
);
is(
	::Mark::adjusted_time_from_tag('30.0'),
	0,
	'adjusted time from tag retains engine time zero',
);
is(
	::adjusted_playback_position_from_timeline_position(20),
	0,
	'playback position before adjustment window clamps to zero',
);
is(
	::adjusted_playback_position_from_timeline_position(37),
	7,
	'playback timeline position converts for engine restore',
);
}

{
my @cases = (
	{
		name => 'full WAV overlapping offset start',
		track => { playat => '0.0' },
		window => [5, 9],
		device_id => 'select,5,4,/tmp/offset-test.wav',
	},
	{
		name => 'full WAV beginning after offset start',
		track => { playat => '6.0' },
		window => [5, 9],
		device_id => 'playat,1,select,0,3,/tmp/offset-test.wav',
	},
	{
		name => 'region overlapping offset start',
		track => {
			playat => '0.0', region_start => '5.0', region_end => '15.0',
		},
		window => [4, 8],
		device_id => 'select,9,4,/tmp/offset-test.wav',
	},
	{
		name => 'region beginning after offset start',
		track => {
			playat => '6.0', region_start => '5.0', region_end => '15.0',
		},
		window => [5, 9],
		device_id => 'playat,1,select,5,3,/tmp/offset-test.wav',
	},
	{
		name => 'region ending before offset start',
		track => {
			playat => '0.0', region_start => '5.0', region_end => '15.0',
		},
		window => [12, 20],
		out_of_bounds => 1,
	},
	{
		name => 'track playat delay crossing offset start',
		track => { playat => '8.0' },
		window => [5, 12],
		device_id => 'playat,3,select,0,4,/tmp/offset-test.wav',
	},
);

for my $case (@cases){
	local $setup->{timeline_adjustment} = {
		type => 'offset_run',
		timeline_play_start => $case->{window}->[0],
		timeline_play_end => $case->{window}->[1],
	};
	my $track = OffsetRunTestTrack->new(
		name => 'offset-test',
		wav_length => 30,
		full_path => '/tmp/offset-test.wav',
		%{$case->{track}},
	);
	local $tn{'offset-test'} = $track;
	local $::IO::by_name{'offset-test'};
	if ($case->{out_of_bounds}){
		ok($track->region_is_out_of_bounds, $case->{name});
		next;
	}
	local $setup->{wav_info}->{'/tmp/offset-test.wav'}->{format} =
		's16_le,2,44100,i';
	my $input = ::IO::from_wav->new(track => 'offset-test');
	is($input->device_id, $case->{device_id},
		"$case->{name}: adjusted Ecasound playat/select");
	is(
		$input->ecs_string,
		'-f:s16_le,2,44100,i -i:' . $case->{device_id},
		"$case->{name}: complete adjusted Ecasound input",
	);
}
}

{
local $setup->{timeline_adjustment} = {
	type => 'offset_run',
	timeline_play_start => 10,
	timeline_play_end => 20,
};
my $track = OffsetRunTestTrack->new(
	name => 'fade-window-test',
	playat => '0.0',
	wav_length => 30,
	full_path => '/tmp/fade-window-test.wav',
);
local $tn{'fade-window-test'} = $track;
local %::Mark::by_name = (
	before_start => bless({name => 'before_start', time => 2}, '::Mark'),
	before_end   => bless({name => 'before_end',   time => 4}, '::Mark'),
	inside_start => bless({name => 'inside_start', time => 12}, '::Mark'),
	inside_end   => bless({name => 'inside_end',   time => 14}, '::Mark'),
	after_start  => bless({name => 'after_start',  time => 22}, '::Mark'),
	after_end    => bless({name => 'after_end',    time => 24}, '::Mark'),
);
local %::Fade::by_index = (
	1 => bless({
		track => 'fade-window-test', type => 'out',
		mark1 => 'before_start', mark2 => 'before_end',
	}, '::Fade'),
	2 => bless({
		track => 'fade-window-test', type => 'in',
		mark1 => 'inside_start', mark2 => 'inside_end',
	}, '::Fade'),
	3 => bless({
		track => 'fade-window-test', type => 'out',
		mark1 => 'after_start', mark2 => 'after_end',
	}, '::Fade'),
);
no warnings 'redefine';
local $::Effect::by_id{'offset-test-fader'} =
	bless({}, 'OffsetRunTestEffect');
my $envelope = ::Fade::fader_envelope($track);
is($envelope->{initial_level}, 0,
	'a fade before the window establishes its initial level');
is_deeply(
	$envelope->{pairs},
	[4, 0, 0, 2, 0, 4, 1, 10, 1],
	'fades before, inside, and after produce the clipped engine envelope',
);
}

{
local $setup->{timeline_adjustment} = {
	type => 'offset_run',
	timeline_play_start => 30,
	timeline_play_end => 60,
};
local %::Mark::by_name;
local @::Mark::all;
local $::this_mark;

my $jump_mark = bless({name => 'Jump', time => 37}, '::Mark');
$::Mark::by_name{Jump} = $jump_mark;
my $engine_position;
no warnings 'redefine';
local *::set_position = sub { $engine_position = shift };
$jump_mark->jump_here;
is($engine_position, 7,
	'jumping to a mark during offset mode seeks to adjusted engine time');

local *::ecasound_iam = sub { 7 };
::drop_mark(name => 'Dropped');
is($::Mark::by_name{Dropped}->time, 37,
	'dropping a mark during offset mode stores permanent timeline time');
}

{
local $setup->{timeline_adjustment} = {
	type => 'offset_run',
	timeline_play_start => 30,
	timeline_play_end => 60,
};
local $project->{playback_position};
local $project->{nama_version};
local $this_engine = bless({}, 'OffsetRunTestEngine');
local $ui = bless({}, 'OffsetRunTestUI');
local $config->{opts}->{a} = 0;
no warnings 'redefine';
local *::ecasound_iam = sub { 7 };
local *::save_system_state = sub {};
local *::save_global_effect_chains = sub {};
local *::save_midish = sub {};
::save_state('/tmp/offset-run-state.json');
is($project->{playback_position}, 37,
	'saving during offset mode stores permanent playback position');
is(
	::adjusted_playback_position_from_timeline_position(
		$project->{playback_position}
	),
	7,
	'restored permanent playback position converts back to engine time',
);
}

{
local $setup->{timeline_adjustment} = {
	type => 'offset_run',
	timeline_play_start => 30,
	timeline_play_end => 60,
	positioning_mark => 'RecordHere',
};
local %::Mark::by_name = (
	RecordHere => bless({name => 'RecordHere', time => 37}, '::Mark'),
);
my $recorded = OffsetRunTestTrack->new(
	name => 'recorded-offset-test',
	playat => undef,
	wav_length => 30,
	full_path => '/tmp/recorded-offset-test.wav',
);
no warnings 'redefine';
local *::ChainSetup::engine_wav_out_tracks = sub { $recorded };
::adjust_offset_recordings();
is($recorded->{playat}, 'RecordHere',
	'recorded track stores permanent offset-run positioning mark');
is($recorded->timeline_position, 37,
	'recorded track resolves its permanent timeline position');
}

{
local $setup->{timeline_adjustment};
local $setup->{loop_endpoints} = ['20.5', '40.5'];

is_deeply(
	[::Mark::loop_timeline_interval()],
	[20.5, 40.5],
	'loop endpoints remain project timeline positions',
);
is_deeply(
	[::Mark::adjusted_loop_interval()],
	[20.5, 40.5],
	'loop endpoints are unchanged without timeline adjustment',
);

$setup->{loop_endpoints} = ['0.0', '10.0'];
is_deeply(
	[::Mark::adjusted_loop_interval()],
	['0.0', '10.0'],
	'a loop endpoint at engine time zero is retained',
);

$setup->{timeline_adjustment} = {
	type => 'offset_run',
	timeline_play_start => 30.5,
	timeline_play_end => 60.5,
};
$setup->{loop_endpoints} = ['20.5', '40.5'];
is_deeply(
	[::Mark::loop_timeline_interval()],
	[20.5, 40.5],
	'adjustment does not change permanent loop endpoints',
);
is_deeply(
	[::Mark::adjusted_loop_interval()],
	[0, 10],
	'loop crossing setup start is clipped and retains adjusted zero',
);

$setup->{loop_endpoints} = ['10.5', '20.5'];
is_deeply(
	[::Mark::adjusted_loop_interval()],
	[],
	'loop entirely before adjusted setup is inactive',
);

$setup->{loop_endpoints} = ['50.5', '70.5'];
is_deeply(
	[::Mark::adjusted_loop_interval()],
	[20, 30],
	'loop crossing setup end is clipped to adjusted setup endpoint',
);

$setup->{loop_endpoints} = ['40.5', '50.5'];
is_deeply(
	[::Mark::adjusted_loop_interval()],
	[10, 20],
	'loop wholly inside offset window retains both adjusted endpoints',
);

$setup->{loop_endpoints} = ['70.5', '80.5'];
is_deeply(
	[::Mark::adjusted_loop_interval()],
	[],
	'loop wholly after offset window is inactive',
);
}



load_project(name => "test_project-convert51", create => 1);

my $script = <<CONVERT51;
[% qx(cat ./stereo51.nms ) %]
CONVERT51

do_script($script);
$expected_setup_lines = <<EXPECTED;
[% qx(cat ./stereo51.te ) %]
EXPECTED

force_alsa();
nama_cmd('gen');
check_setup('Stereo to 5.1 converter script' );

load_project(name => "test_project-crossover", create => 1);
$script = <<CROSSOVER;
[% qx(cat ./crossover.nms ) %]
CROSSOVER

do_script($script);
$expected_setup_lines = <<EXPECTED;
[% qx(cat ./crossover-alsa.te ) %]
EXPECTED
force_alsa();
nama_cmd('gen');
check_setup('pianoteq feeding crossover network' );


load_project(name => "$test_project-sendbus-cooked", create => 1);

do_script(' add mic
            add guitar
            for 3 4; mon
            add_submix_cooked ear 7
');
$expected_setup_lines = <<EXPECTED;
# general

-z:mixmode,sum -G:jack,NamaEcasound,send -b 1024 -z:nodb -z:intbuf

# audio inputs

-a:1,5 -i:loop,mic_out
-a:1,6 -i:loop,guitar_out
-a:3,4 -i:alsa,default

# post-input processing

-a:3  -chcopy:1,2
-a:4  -chcopy:1,2

# pre-output processing

-a:5  -chmove:2,8 -chmove:1,7
-a:6  -chmove:2,8 -chmove:1,7

# audio outputs

-a:1,5,6 -o:alsa,default
-a:3 -o:loop,mic_out
-a:4 -o:loop,guitar_out
EXPECTED
force_alsa();
nama_cmd('gen');
check_setup('Submix - ALSA');

force_jack();
nama_cmd('gen');

$expected_setup_lines = <<EXPECTED;
# general

-z:mixmode,sum -G:jack,NamaEcasound,send -b 1024 -z:nodb -z:intbuf -f:f32_le,2,44100

# audio inputs

-a:1,5 -i:loop,mic_out
-a:1,6 -i:loop,guitar_out
-a:3,4 -i:jack_multi,system:capture_1

# post-input processing

-a:3 -chcopy:1,2
-a:4 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,mic_out
-a:4 -o:loop,guitar_out
-a:5,6 -o:jack_multi,system:playback_7,system:playback_8
EXPECTED
check_setup('Submix, AKA add_submix_cooked - JACK');

load_project(name => "add_submix_raw", create => 1);

nama_cmd("add_tracks mic guitar; for 3 4; mon;; 4 source 2; stereo; add_submix_raw raw-user 7"); 
$expected_setup_lines = <<EXPECTED;


# general

-z:mixmode,sum -G:jack,NamaEcasound,send -b 1024 -z:nodb -z:intbuf -f:f32_le,2,44100

# audio inputs

-a:1 -i:loop,Main_in
-a:3,5 -i:jack_multi,system:capture_1
-a:4,6 -i:jack_multi,system:capture_2,system:capture_3

# post-input processing

-a:3 -chcopy:1,2
-a:5 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3,4 -o:loop,Main_in
-a:5,6 -o:jack_multi,system:playback_7,system:playback_8
EXPECTED

force_jack();
nama_cmd('gen');
check_setup('Submix, raw - JACK');

force_alsa();
nama_cmd('gen');
$expected_setup_lines = <<EXPECTED;
# audio inputs

-a:1 -i:loop,Main_in
-a:3,4,5,6 -i:alsa,default

# post-input processing

-a:3  -chcopy:1,2
-a:4 -chmove:2,1 -chmove:3,2
-a:5  -chcopy:1,2
-a:6 -chmove:2,1 -chmove:3,2

# pre-output processing

-a:5  -chmove:2,8 -chmove:1,7
-a:6  -chmove:2,8 -chmove:1,7

# audio outputs

-a:1,5,6 -o:alsa,default
-a:3,4 -o:loop,Main_in
EXPECTED
check_setup('Send Bus, Raw - ALSA');

force_jack();
load_project(name => "$test_project-add_insert_post", create => 1);

nama_cmd("add sax; mon; gen");
nama_cmd("add_insert post jconvolver; gen");
$expected_setup_lines = <<EXPECTED;

# general

-z:mixmode,sum -G:jack,NamaEcasound,send -b 8192 -z:nodb -z:intbuf -f:f32_le,2,44100

# audio inputs

-a:1 -i:loop,Main_in
-a:3 -i:jack_multi,system:capture_1
-a:4 -i:jack_multi,jconvolver:out_1,jconvolver:out_2
-a:J3,5 -i:loop,sax_insert_post

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,sax_insert_post
-a:4,5 -o:loop,Main_in
-a:J3 -o:jack_multi,jconvolver:in_1,jconvolver:in_2
EXPECTED

check_setup('JACK client as postfader insert');

load_project(name => "add_insert_pre", create => 1);
nama_cmd("add sax; mon; add_insert pre jconvolver; gen");
$expected_setup_lines = <<EXPECTED;

# general

-z:mixmode,sum -G:jack,NamaEcasound,send -b 1024 -z:nodb -z:intbuf -f:f32_le,2,44100

# audio inputs

-a:1 -i:loop,Main_in
-a:3 -i:loop,sax_insert_pre
-a:4 -i:jack_multi,jconvolver:out_1
-a:5,6 -i:jack_multi,system:capture_1

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,Main_in
-a:4,5 -o:loop,sax_insert_pre
-a:6 -chcopy:1,2
-a:6 -o:jack_multi,jconvolver:in_1
EXPECTED
check_setup('JACK client as pre-fader insert');

load_project(name => "add_insert_via_soundcard-postfader", create => 1);
nama_cmd("add sax; mon; source 2; add_insert post 5; gen");
$expected_setup_lines = <<EXPECTED;
-a:1 -i:loop,Main_in
-a:3 -i:jack_multi,system:capture_2
-a:4 -i:jack_multi,system:capture_7,system:capture_8
-a:J3,5 -i:loop,sax_insert_post

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,sax_insert_post
-a:4,5 -o:loop,Main_in
-a:J3 -o:jack_multi,system:playback_5,system:playback_6

EXPECTED
check_setup('Insert via soundcard, postfader - JACK');

force_alsa();
nama_cmd("gen");
$expected_setup_lines = <<EXPECTED;

# general

-z:mixmode,sum -G:jack,NamaEcasound,send -b 1024 -z:nodb -z:intbuf

# audio inputs

-a:1 -i:loop,Main_in
-a:3,4 -i:alsa,default
-a:J3,5 -i:loop,sax_insert_post

# post-input processing

-a:3 -chmove:2,1 -chcopy:1,2
-a:4 -chmove:7,1 -chmove:8,2 

# pre-output processing

-a:J3  -chmove:2,6 -chmove:1,5

# audio outputs

-a:1,J3 -o:alsa,default
-a:3 -o:loop,sax_insert_post
-a:4,5 -o:loop,Main_in
EXPECTED
check_setup('Insert via soundcard, postfader - ALSA');

load_project(name => "add_insert_via_soundcard_pre", create => 1);
nama_cmd("add sax; mon; source 2; add_insert pre 5; gen");
$expected_setup_lines = <<EXPECTED;

# general

-z:mixmode,sum -G:jack,NamaEcasound,send -b 1024 -z:nodb -z:intbuf

# audio inputs

-a:1 -i:loop,Main_in
-a:3 -i:loop,sax_insert_pre
-a:4,5,6 -i:alsa,default

# post-input processing

-a:4 -chmove:7,1 
-a:5 -chmove:2,1 
-a:6 -chmove:2,1 -chcopy:1,2

# pre-output processing

-a:6  -chmove:1,5

# audio outputs

-a:1,6 -o:alsa,default
-a:3 -o:loop,Main_in
-a:4,5 -o:loop,sax_insert_pre
EXPECTED
check_setup('Hardware insert via soundcard, prefader  - ALSA');
gen_jack();
$expected_setup_lines = <<EXPECTED;
# general

-z:mixmode,sum -G:jack,NamaEcasound,send -b 1024 -z:nodb -z:intbuf -f:f32_le,2,44100

# audio inputs

-a:1 -i:loop,Main_in
-a:3 -i:loop,sax_insert_pre
-a:4 -i:jack_multi,system:capture_7
-a:5,6 -i:jack_multi,system:capture_2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,Main_in
-a:4,5 -o:loop,sax_insert_pre
-a:6 -chcopy:1,2
-a:6 -o:jack_multi,system:playback_5
EXPECTED
check_setup('Hardware insert via soundcard, prefader  - JACK');

#load_project(name => "midi", create => 1);
{
	my $midi = add_midi_track('synth');
	is(ref $midi, 'Audio::Nama::MidiTrack',
		'MIDI declaration creates a MidiTrack');
	is($tn{synth}, $midi,
		'MIDI declaration uses the normal track registry');
	is($ti{$midi->n}, $midi,
		'MIDI declaration receives a normal track number');
	is($midi->engine_group, $config->{midi_engine_name},
		'MIDI declaration assigns the MIDI engine');
	is($midi->rw, OFF,
		'MIDI declaration does not inherit the audio MON default');
	ok(! defined $midi->source_id && ! defined $midi->send_id,
		'MIDI declaration leaves routing endpoints unset');
	is($midi->source_type, 'midi',
		'MIDI declaration identifies the source type');
	is($midi->send_type, 'midi',
		'MIDI declaration identifies the destination type');
	is($this_track, $midi,
		'MIDI declaration selects the new track');
	is($midi->as_hash->{class}, 'Audio::Nama::MidiTrack',
		'MIDI track class is preserved for project persistence');
	$midi->set_rw(PLAY);
	is($midi->rw, OFF,
		'MIDI track cannot play before source and send are set');
	$midi->set(source_id => 'nord', send_id => 'dx7', rw => PLAY);
	my $midi_display = show_tracks_section($midi);
	like($midi_display, qr/\bsynth\b.*\bPLAY\b.*\bnord\b.*\bdx7\b/,
		'show-tracks displays MIDI status and routing');
	unlike($midi_display, qr/PLAY but OFF/,
		'MIDI display is independent of the audio graph status');
	{
		my @midish_commands;
		no warnings 'redefine';
		local *Audio::Nama::midish_cmd = sub {
			my ($command) = @_;
			push @midish_commands, $command;
			return '{synth_1}' if $command eq 'print [tlist]';
			return;
		};
		local $en{$config->{midi_engine_name}} =
			bless {}, 'Audio::Nama::MidiEngine';
		$midi->set(midi_versions => [1], version => 1, rw => PLAY);
		is($midi->midi_version_name(1), 'synth_1',
			'MIDI version name is derived by MidiTrack');

		$midi->mute;
		is_deeply(\@midish_commands,
			['print [tlist]', 'mute synth_1'],
			'MIDI mute is dispatched through MidiEngine');

		@midish_commands = ();
		$midi->unmute;
		is_deeply(\@midish_commands,
			['print [tlist]', 'unmute synth_1'],
			'MIDI unmute is dispatched through MidiEngine');

		@midish_commands = ();
		$midi->select_track;
		is_deeply(\@midish_commands, [],
			'selecting a MIDI track does not unmute it');

		$midi->set_rw(OFF);
		is_deeply(\@midish_commands,
			['print [tlist]', 'mute synth_1'],
			'setting a MIDI track OFF mutes its current version');
	}
	$midi->remove;
}

sub gen_alsa { force_alsa(); nama_cmd('gen')}
sub gen_jack { force_jack(); nama_cmd('gen')}
sub force_alsa { $config->{opts}->{A} = 1; $config->{opts}->{J} = 0; $jack->{jackd_running} = 0; }
sub force_jack{ $config->{opts}->{A} = 0; $config->{opts}->{J} = 1; $jack->{jackd_running} = 1; }
sub setup_content {
	my @lines = split "\n", shift;
	my %setup;
	for (@lines){
		next unless /^-a:/;
		s/\s*$//;
		$setup{$_}++;
	}
	\%setup;
}
sub check_setup {
	my $test_name = shift;
	is( json_out(setup_content(::ChainSetup::ecasound_chain_setup())), 
		json_out(setup_content($expected_setup_lines)), 
		$test_name);
}
sub check_tempo_conversions {
	# make objects
	# run tests






}


cleanup_dirs();
done_testing();
__END__
