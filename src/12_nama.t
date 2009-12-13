package ::;
use Test::More qw(no_plan);
use strict;
use warnings;
no warnings qw(uninitialized);
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

diag(cwd);

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

my $cs_got = eval_iam('cs');
my $cs_want = q(### Chain status (chainsetup 'command-line-setup') ###
Chain "default" [selected] );
is( $cs_got, $cs_want, "Evaluate Ecasound 'cs' command");

my $test_project = 'test';

load_project(name => $test_project, create => 1);

is( project_dir(), "./$test_project", "establish project directory");

command_process('add sax');

like(ref $this_track, qr/Track/, "track creation"); 

is( $this_track->name, 'sax', "current track assignment");

command_process('r 2');

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
is ($io->ecs_extra, ' -chmove:2,6 -chmove:1,5', 'IO to_soundcard_device 2');

$io = ::IO::to_soundcard->new(track => 'sax'); 

is ($io->ecs_string, '-o:alsa,default', 'IO to_soundcard 1');
is ($io->ecs_extra, ' -chmove:2,6 -chmove:1,5', 'IO to_soundcard 2');
1;
__END__
	is( $foo, 2, "Scalar number assignment");
	is( $name, 'John', "Scalar string assignment");
	my $sum;
	map{ $sum += $_ } @face;
	is ($sum, 25, "Array assignment");
	is( $dict{fruit}, 'melon', "Hash assignment");
	is ($serialized, $expected, "Serialization round trip");
}
	my $nulls = { 
		foo => 2, 
		name => undef,
		face => [],
		dict => {},
	};	
	diag("scalar array: ",scalar @face, " scalar hash: ", scalar %dict); 
	assign (data => $nulls, class => 'main', vars => \@var_list);
	is( scalar @face, 0, "Null array assignment");
	is( scalar %dict, 0, "Null hash assignment");
	


1;
__END__
