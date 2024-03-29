package ::; 
use ::;
use Test2::Bundle::More;
use File::Path qw(make_path remove_tree);
use File::Slurp;
use Cwd;

use strict;
use warnings;
no warnings qw(uninitialized);

our ($expected_setup_lines);

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag ("TESTING $0\n");

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag("working directory: ",cwd);

our $test_dir = "/tmp/nama-test";
$fx_cache->{fake} = read_file("t/data/fake_effects_cache.json");

cleanup_dirs();
setup_dirs();

sub cleanup_dirs { 	chdir('..'), remove_tree($test_dir) if -e $test_dir }
sub setup_dirs{ make_path("$test_dir/test/.wav", "$test_dir/untitled/.wav") }

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag( qx(find $test_dir) );

apply_test_args();

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag "options: @ARGV";
startup();
$config->{use_git} = 0;

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag "Check representative variable from default .namarc";

is( $config->{mix_to_disk_format}, "s16_le,N,44100,i", "Read mix_to_disk_format");

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

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag("project project dir: ".project_dir());
$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag("project project wav dir: ".this_wav_dir());

#diag(map{ $_->dump} values %::Track::by_index );

is( project_dir(), "$test_dir/$test_project", "establish project directory");

is( ref $bn{Main}, q(Audio::Nama::SubBus), 'Bus initializtion');


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

my ($vol_id) = $this_track->vol;

ok(   (defined $vol_id and $::Effect::by_id{$vol_id}) , "apply volume control");

nama_cmd('add_effect time_reverb3');

like( this_op_o()->code, qr/time_reverb3/, "apply preset");

is (this_op_o()->track_effect_index, 0, "positioned before vol/pan faders");

nama_cmd('add_effect decimator 1 2');

like( this_op_o()->code, qr/decimator/, "apply LADSPA effect");

is( this_op_o()->track_effect_index, 1, "position before faders, after other effects");

nama_cmd('vol -2');

is( $this_track->vol_o->params->[0], -2, "modify effect" );

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

###### Timeline tests
#
# This table tests how the offset run mode affects
# other time displacing operations. 
#
# If you have a region, the offset could occur
# before the region, in the middle of the region
# or after the region. Code for each case
# is different. There is further an 
# interaction with playat. 
#
# The tests are exhaustive, all possible
# combinations are covered.
#
# The numbers indicate time positions.

# asterisk (*) indicates that no output is available
# for that specific field

{

$ENV{NAMA_VERBOSE_TEST_OUTPUT} and diag "Edit mode playat$ENV{NAMA_VERBOSE_TEST_OUTPUT} region endpoints adjustment";
my @tests = split "\n",<<TEST_DATA;
1 12 5 15 4   8  *  *  * 30 out_of_bounds_near region
2 12 5 15 23 26  *  *  * 30 out_of_bounds_far region
3 12 5 15 10 17  2  5 10 30 play_start_during_playat_delay region
4 12 5 15 13 21  0  6 14 30 play_start_within_region region
5 12 5 15 21 26  0 14 19 30 play_start_within_region region
6  0 5 15  5  9  0 10 14 30 play_start_within_region region
7  0 0  0  5  9  0  5  9 30 no_region_play_start_after_playat_delay no_playat
8  2 0  0  5  9  0  3  7 30 no_region_play_start_after_playat_delay
9  6 0  0  5  9  1  0  3 30 no_region_play_start_during_playat_delay
10 6 0  0  3  5  *  *  * 30 out_of_bounds_near no_region
11 6 0  0 40 49  *  *  * 30 out_of_bounds_far  no_region
12 6 0  0 34 40  0 28 30 30 no_region_play_start_after_playat_delay end_after_wav_length

TEST_DATA

foreach(@tests){

	#diag($_);
	my ($index, 
		$playat, 
		$region_start, 
		$region_end, 
		$edit_play_start,
		$edit_play_end, 
		$new_playat, 
		$new_region_start, 
		$new_region_end,
		$length,
		$case, 
		$comment,
	) = split " ", $_;

	my $args = {
		playat 			=> $playat, 
		region_start 	=> $region_start, 
		region_end 		=> $region_end, 
		edit_play_start => $edit_play_start,
		edit_play_end 	=> $edit_play_end,
		setup_length 	=> $length,
	};
	is( ::edit_case($args), $case, "$index: $case $comment");
	is( ::new_playat($args), $new_playat, "$index: new_playat: $case");
	is( ::new_region_start($args), $new_region_start, "$index: new_region_start: $case");
	is( ::new_region_end($args), $new_region_end, "$index: new_region_end: $case");
}
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
#add_midi_track('synth');

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
