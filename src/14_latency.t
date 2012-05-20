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
use ::;

use ::Globals qw(:all);

BEGIN { use_ok('::') };

diag ("TESTING $0\n");

push @ARGV, qw(-f /dev/null), # force to use internal namarc

			qw(-t), # set text mode 

			qw(-d .), # use cwd as project root

			q(-E), # suppress loading Ecasound

			q(-J), # fake jack client data

			q(-T), # don't initialize terminal
;

diag("working directory: ",cwd);

bootstrap_environment();

diag "Check representative variable from default .namarc";

is( $config->{mix_to_disk_format}, "s16_le,N,44100,i", "Read mix_to_disk_format");

is( jack_port_latency('output','LinuxSampler:playback_1'), 
	2048, "get JACK port latency");

=comment
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

#=comment
  class: to_jack_port
  args:
    width: 1
    port_name: sax
  ecs_string: -f:f32_le,1,44100 -o:jack,,sax_out

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

=cut


sub gen_alsa { force_alsa(); command_process('gen')}
sub gen_jack { force_jack(); command_process('gen')}
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
