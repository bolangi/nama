# to initialize the environment, we

# 1. use Audio::Nama (pull in the whole application)

# 2. set the current namespace to Audio::Nama 
#    (so we can put both hands in abdominal cavity)

# 3. declare variables by including the declarations blocks of Nama.pm

package ::;
use Test::More qw(no_plan);
use ::Assign qw(yaml_in yaml_out);
use strict;
use warnings;
no warnings qw(uninitialized);
our ($expected_setup_lines);
use Cwd;

our (
	$main,
	$this_track,
	%opts,
	$jack_running,
);

BEGIN { use_ok('::') };

diag ("TESTING $0\n");

# defeat namarc detection to force using $default namarc

push @ARGV, qw(-f /dev/null);

# set text mode (don't start gui)

push @ARGV, qw(-t); 

# use cwd as project root

push @ARGV, qw(-d .); 

# suppress loading Ecasound

push @ARGV, q(-E);

# fake jack client data

push @ARGV, q(-J);

# don't initialize terminal

push @ARGV, q(-T);

diag("working directory: ",cwd);

process_options();
initialize_interfaces();
diag "Check representative variable from default .namarc";

is( $::mix_to_disk_format, "s16_le,N,44100,i", "Read mix_to_disk_format");
=skip
# Ecasound dependent
diag "Check static effects data read";
is( $::e_bound{cop}{z} > 40, 1, "Verify Ecasound chain operator count");

diag "Check effect hinting and help";

my $want = q(---
code: epp
count: 1
display: scale
name: Pan
params:
  -
    begin: 0
    default: 50
    end: 100
    name: 'Level %'
    resolution: 0
...
);


package ::;
is( yaml_out($effects[$effect_i{epp}]) ,  $want , "Pan hinting");

is( $effects_help[0], 
	qq(dyn_compress_brutal,  -pn:dyn_compress_brutal:gain-%\n),
	'Preset help for dyn_compress_brutal');

my @result = ::Fade::spec_to_pairs([0,1,'out']);
my @expected = ( 0, 1, 0.95, 0.75, 1, 0 );

is_deeply(\@result, \@expected, "Fade::spec_to_pairs - fade-out");

@result = ::Fade::spec_to_pairs([0,1,'in']);
@expected = ( 0, 0, 0.05, 0.75, 1, 1 );

is_deeply(\@result, \@expected, "Fade::spec_to_pairs - fade-in");

=cut

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
	"loop,Master"			=> 'loop',
);

while( my($dest,$type) = splice @id_to_type, 0,2){
	is( dest_type($dest), $type, "$dest => $type");
}


is( ref $main, q(Audio::Nama::Bus), 'Bus initializtion');

# SKIP: { 
# my $cs_got = eval_iam('cs');
# my $cs_want = q(### Chain status (chainsetup 'command-line-setup') ###
# Chain "default" [selected] );
# is( $cs_got, $cs_want, "Evaluate Ecasound 'cs' command");
# }

my $test_project = 'test';

load_project(name => $test_project, create => 1);

#diag(map{ $_->dump} values %::Track::by_index );

is( project_dir(), "./$test_project", "establish project directory");

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
    full_path: test_dir/sax_1.wav
  ecs_string: -f:s16_le,1,44100,i -o:test_dir/sax_1.wav
-
  class: from_wav
  args:
    playat_output: playat,5
    select_output: select,1,4
    modifiers: []
    full_path: test_dir/sax_1.wav
  ecs_string: /-i:playat,5,select,1,4,.+sax_\d+.wav/
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
  class: to_soundcard_device
  ecs_string: -o:alsa,default
-
  class: from_soundcard_device
  ecs_string: -i:alsa,default
-
  class: from_soundcard
  args:
    width: 1
    source_id: 2
  ecs_string: -i:jack_multi,system:capture_2
-
  class: to_soundcard
  args:
    width: 2
    send_id: 5
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
	diag "IO.pm unit test $i";
	my $class = "Audio::Nama::IO::$t{class}";
	my $io = $class->new(%{$t{args}});
	my @keys = sort grep{ $_ ne 'class'} keys %t;
	if( $t{ecs_string} =~ m(^/)){
		like( $io->ecs_string, $t{ecs_string}, "$t{class} ecs_string");
	}else{
		is(   $io->ecs_string, $t{ecs_string}, "$t{class} ecs_string");
	}
}
	

force_alsa();

command_process('add sax');

like(ref $this_track, qr/Track/, "track creation"); 

is( $this_track->name, 'sax', "current track assignment");

command_process('source 2');


is( $this_track->source_type, 'soundcard', "set soundcard input");
is( $this_track->source_id,  2, "set input channel");

command_process('send 5');

# track sax, source 2, send 5

is( $this_track->send_type, 'soundcard', 'set soundcard output');
is( $this_track->send_id, 5, 'set soundcard output');

# this is ALSA dependent (i.e. no JACK running)

my $io = ::IO->new(track => 'sax');

like( ref $io, qr/IO$/, 'IO base class object');

$io = ::IO::to_soundcard_device->new(track => 'sax'); 

is($io->ecs_string, '-o:alsa,default', 'IO to_soundcard_device 1');
is($io->ecs_extra,  ' -chmove:1,5', 'IO to_soundcard_device 2');

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

command_process("sax; source Horgand; gen");
like( ::ChainSetup::ecasound_chain_setup(), qr/Horgand/, 'set JACK client as input');
command_process("sax; source jack; gen");
like( ::ChainSetup::ecasound_chain_setup(), qr/jack,,sax_in/, 'set JACK port for manual input');

command_process("sax; source 2");


force_alsa();

command_process('3; nosend; gen');

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3,R3 -i:alsa,default

# post-input processing

-a:R3 -chmove:2,1
-a:3 -chmove:2,1 -chcopy:1,2

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,Master_in
-a:R3 -f:s16_le,1,44100,i -o:test/.wav/sax_1.wav
EXPECTED

check_setup('ALSA basic setup' );

force_jack();
command_process('gen');
$expected_setup_lines = <<EXPECTED;

# audio inputs

-a:1 -i:loop,Master_in
-a:3,R3 -i:jack_multi,system:capture_2

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,Master_in
-a:R3 -f:s16_le,1,44100,i -o:test/.wav/sax_1.wav

EXPECTED

check_setup('JACK basic setup' );

command_process('3;rec_defeat; gen');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,Master_in
EXPECTED

check_setup('JACK rec_defeat setup' );

force_alsa(); command_process('gen');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:alsa,default

# post-input processing

-a:3 -chmove:2,1 -chcopy:1,2

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,Master_in

EXPECTED

check_setup('ALSA rec_defeat setup' );
command_process('Master; send 5;gen');

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:alsa,default

# post-input processing

-a:3 -chmove:2,1 -chcopy:1,2

# pre-output processing

-a:1  -chmove:2,6 -chmove:1,5

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,Master_in
EXPECTED

check_setup('ALSA send-Master-to-alternate-channel setup' );
force_jack(); command_process('gen');

$expected_setup_lines = <<EXPECTED;
-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_5,system:playback_6
-a:3 -o:loop,Master_in
EXPECTED
check_setup('JACK send-Master-to-alternate-channel setup' );

command_process('Mixdown; rec; gen');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2
-a:Mixdown,J1 -i:loop,Master_out

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:loop,Master_out
-a:3 -o:loop,Master_in
-a:J1 -o:jack_multi,system:playback_5,system:playback_6
-a:Mixdown -f:s16_le,2,44100,i -o:test/.wav/Mixdown_1.wav
EXPECTED

check_setup('JACK mixdown setup with main out' );
gen_alsa();

$expected_setup_lines = <<EXPECTED;
-a:1 -i:loop,Master_in
-a:3 -i:alsa,default
-a:Mixdown,J1 -i:loop,Master_out

# post-input processing

-a:3 -chmove:2,1 -chcopy:1,2

# pre-output processing

-a:J1  -chmove:2,6 -chmove:1,5

# audio outputs

-a:1 -o:loop,Master_out
-a:3 -o:loop,Master_in
-a:J1 -o:alsa,default
-a:Mixdown -f:s16_le,2,44100,i -o:test/.wav/Mixdown_1.wav
EXPECTED

check_setup('ALSA mixdown setup with main out' );

command_process('master_on');
$expected_setup_lines = <<EXPECTED;
-a:1 -i:loop,Master_in
-a:3 -i:alsa,default
-a:4 -i:loop,Master_out
-a:5,6,7 -i:loop,Eq_out
-a:8 -i:loop,Boost_in
-a:Mixdown,J8 -i:loop,Boost_out

# post-input processing

-a:3 -chmove:2,1 -chcopy:1,2

# pre-output processing

-a:J8  -chmove:2,6 -chmove:1,5

# audio outputs

-a:1 -o:loop,Master_out
-a:3 -o:loop,Master_in
-a:4 -o:loop,Eq_out
-a:5,6,7 -o:loop,Boost_in
-a:8 -o:loop,Boost_out
-a:J8 -o:alsa,default
-a:Mixdown -f:s16_le,2,44100,i -o:test/.wav/Mixdown_1.wav
EXPECTED
gen_alsa();
check_setup('Mixdown in mastering mode - ALSA');


command_process('Master; stereo'); # normal output width

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2
-a:4 -i:loop,Master_out
-a:5,6,7 -i:loop,Eq_out
-a:8 -i:loop,Boost_in
-a:Mixdown,J8 -i:loop,Boost_out

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:loop,Master_out
-a:3 -o:loop,Master_in
-a:4 -o:loop,Eq_out
-a:5,6,7 -o:loop,Boost_in
-a:8 -o:loop,Boost_out
-a:J8 -o:jack_multi,system:playback_5,system:playback_6
-a:Mixdown -f:s16_le,2,44100,i -o:test/.wav/Mixdown_1.wav
EXPECTED
gen_jack();
check_setup('Mixdown in mastering mode - JACK');

command_process('mixoff; master_off');
command_process('for 4 5 6 7 8; remove_track quiet');
command_process('Master; send 1');
command_process('asub Horns; sax move_to_bus Horns; sax stereo');

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:alsa,default
-a:4 -i:loop,sax_out

# post-input processing

-a:3 -chmove:2,1 -chmove:3,2

# audio outputs

-a:1 -o:alsa,default
-a:3 -o:loop,sax_out
-a:4 -o:loop,Master_in
EXPECTED
gen_alsa();
check_setup('Sub-bus - ALSA');
gen_jack();

$expected_setup_lines = <<EXPECTED;
-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2,system:capture_3
-a:4 -i:loop,sax_out

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,sax_out
-a:4 -o:loop,Master_in
EXPECTED
check_setup('Sub-bus - JACK');

command_process('remove_bus Horns');
command_process('add_send_bus_cooked Vo 5');
$expected_setup_lines = <<EXPECTED;

-a:1,4 -i:loop,sax_out
-a:3 -i:jack_multi,system:capture_2,system:capture_3

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,sax_out
-a:4 -o:jack_multi,system:playback_5,system:playback_6
EXPECTED
gen_jack();
check_setup('Send bus - soundcard - JACK');
command_process('remove_bus Vo');
command_process('sax mono');
=comment
command_process('add_insert post 5');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2
-a:4 -i:jack_multi,system:capture_7,system:capture_8
-a:J3,5 -i:loop,sax_insert_post

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,sax_insert_post
-a:4,5 -o:loop,Master_in
-a:J3 -o:jack_multi,system:playback_5,system:playback_6
EXPECTED
gen_jack();
check_setup('Insert via soundcard - JACK');
command_process('remove_insert'); 
command_process('add_send_bus_raw Vo 5');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3,4 -i:jack_multi,system:capture_2

# post-input processing

-a:3 -chcopy:1,2
-a:4 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,Master_in
-a:4 -o:jack_multi,system:playback_5,system:playback_6
EXPECTED
gen_jack();

check_setup('Send bus - raw - JACK');
=cut

{

diag "Edit mode playat and region endpoints adjustment";
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

	::set_edit_vars_testing( 
		$playat, 
		$region_start, 
		$region_end, 
		$edit_play_start,
		$edit_play_end,
		$length,
	);

		
	is( ::edit_case(), $case, "$index: $case $comment");
	is( ::new_playat(), $new_playat, "$index: new_playat: $case");
	is( ::new_region_start(), $new_region_start, "$index: new_region_start: $case");
	is( ::new_region_end(), $new_region_end, "$index: new_region_end: $case");
}
}

sub gen_alsa { force_alsa(); command_process('gen')}
sub gen_jack { force_jack(); command_process('gen')}
sub force_alsa { $opts{A} = 1; $opts{J} = 0; $jack_running = 0; }
sub force_jack{ $opts{A} = 0; $opts{J} = 1; $jack_running = 1; }
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
	is( yaml_out(setup_content(::ChainSetup::ecasound_chain_setup())), 
		yaml_out(setup_content($expected_setup_lines)), 
		$test_name);
}

sub cleanup { 	
		unlink './test/Setup.ecs';
		rmdir './test/.wav';
		rmdir './test';
		rmdir './untitled/.wav';
		rmdir './untitled';
		unlink './.effects_cache';
}

cleanup();
1;
__END__
