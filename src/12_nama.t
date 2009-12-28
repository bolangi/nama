package ::;
use Test::More qw(no_plan);
use strict;
use warnings;
no warnings qw(uninitialized);
our ($expected_setup_lines);
use Cwd;

BEGIN { use_ok('::') };

diag ("TESTING $0\n");

[% qx(cat ./declarations.pl) %] 
 
[% qx(cat ./var_types.pl) %]

# defeat namarc detection to force using $default namarc

push @ARGV, qw(-f dummy);

# set text mode (don't start gui)

push @ARGV, qw(-t); 

# use cwd as project root

push @ARGV, qw(-d .); 

# suppress loading Ecasound

push @ARGV, q(-E);

diag("working directory: ",cwd);

process_options();

prepare();
diag "Check representative variable from default .namarc";
is ( $::mix_to_disk_format, "s16_le,N,44100,i", "Read mix_to_disk_format");

diag "Check static effects data read";
is ( $::e_bound{cop}{z} > 40, 1, "Verify Ecasound chain operator count");

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

is( ref $main_bus, q(Audio::Nama::Bus), 'Bus initializtion');

# SKIP: { 
# my $cs_got = eval_iam('cs');
# my $cs_want = q(### Chain status (chainsetup 'command-line-setup') ###
# Chain "default" [selected] );
# is( $cs_got, $cs_want, "Evaluate Ecasound 'cs' command");
# }

my $test_project = 'test';

load_project(name => $test_project, create => 1);

is( project_dir(), "./$test_project", "establish project directory");

command_process('Master; mono'); # so older tests work

force_alsa();

command_process('add sax');

like(ref $this_track, qr/Track/, "track creation"); 

is( $this_track->name, 'sax', "current track assignment");

command_process('source 2');

is( $this_track->source_type, 'soundcard', "set soundcard input");
is( $this_track->source_id,  2, "set input channel");

command_process('send 5');

is( $this_track->send_type, 'soundcard', 'set soundcard output');
is( $this_track->send_id, 5, 'set soundcard output');

# this is ALSA dependent (i.e. no JACK running)

my $io = ::IO->new(track => 'sax');

like( ref $io, qr/IO$/, 'IO base class object');

$io = ::IO::from_soundcard_device->new(track => 'sax'); 

is ($io->ecs_string, '-i:alsa,default', 'IO from_soundcard_device 1');
is ($io->ecs_extra, '-chmove:2,1 -chcopy:1,2', 'IO from_soundcard_device 2');

$io = ::IO::from_soundcard->new(track => 'sax'); 

is ($io->ecs_string, '-i:alsa,default', 'IO from_soundcard 1');
is ($io->ecs_extra, '-chmove:2,1 -chcopy:1,2', 'IO from_soundcard 2');


$io = ::IO::to_soundcard_device->new(track => 'sax'); 

is ($io->ecs_string, '-o:alsa,default', 'IO to_soundcard_device 1');
like ($io->ecs_extra, qr/-chmove:2,6 -chmove:1,5/, 'IO to_soundcard_device 2');

$io = ::IO::to_soundcard->new(track => 'sax'); 

is ($io->ecs_string, '-o:alsa,default', 'IO to_soundcard 1');
like ($io->ecs_extra, qr/-chmove:2,6 -chmove:1,5/, 'IO to_soundcard 2');

force_jack();


$io = ::IO::from_soundcard->new(track => 'sax'); 
like (ref $io, qr/from_jack_multi/, 'sound system ALSA/JACK detection: input');
is ($io->ecs_string, '-i:jack_multi,system:capture_2', 'IO from_soundcard: jack 1');
is ($io->ecs_extra, '-chcopy:1,2', 'IO from_soundcard: jack 2');


$io = ::IO::to_soundcard->new(track => 'sax'); 
like (ref $io, qr/to_jack_multi/, 'sound system ALSA/JACK detection: output');

is ($io->ecs_string, '-o:jack_multi,system:playback_5', 'IO to_soundcard: jack 1');
ok (! $io->ecs_extra, 'IO to_soundcard: jack 2');

$io = ::IO::to_null->new(track => 'sax', device_id => 'alsa,default');

is ($io->device_id, 'alsa,default', 'value overrides method call');

command_process("sax; source Horgand; gen");
like( $chain_setup, qr/Horgand/, 'set JACK client as input');
command_process("sax; source jack; gen");
like( $chain_setup, qr/jack,,sax_in/, 'set JACK port for manual input');

command_process("sax; source 2");


force_alsa();

command_process('3; nosend; gen');

$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3,R3 -i:alsa,default

# post-input processing

-a:R3 -chmove:2,1 -chcopy:1,2
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

-a:R3 -chcopy:1,2
-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1
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

-a:1 -o:jack_multi,system:playback_1
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

-a:1 -o:jack_multi,system:playback_5
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
-a:J1 -o:jack_multi,system:playback_5
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
command_process('for 4 5 6 7 8; remove_track');
command_process('Master; send 1');
command_process('asub Horns; sax set bus Horns; sax stereo');

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
command_process('add_insert_cooked 5');
$expected_setup_lines = <<EXPECTED;

-a:1 -i:loop,Master_in
-a:3 -i:jack_multi,system:capture_2
-a:4 -i:jack_multi,system:capture_7,system:capture_8
-a:J3,5 -i:loop,sax_insert

# post-input processing

-a:3 -chcopy:1,2

# audio outputs

-a:1 -o:jack_multi,system:playback_1,system:playback_2
-a:3 -o:loop,sax_insert
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

sub gen_alsa { force_alsa(); command_process('gen')}
sub gen_jack { force_jack(); command_process('gen')}
sub force_alsa { $opts{A} = 1; $opts{J} = 0; jack_update(); }
sub force_jack{ $opts{A} = 0; $opts{J} = 1; jack_update(); }
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
	is( yaml_out(setup_content($chain_setup)), 
		yaml_out(setup_content($expected_setup_lines)), 
		$test_name);
}

1;
__END__
