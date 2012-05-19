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

# defeat namarc detection to force using $config->{default} namarc

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

definitions();
process_command_line_options();
start_logging();
initialize_interfaces();
setup_grammar();
diag "Check representative variable from default .namarc";

is( $config->{mix_to_disk_format}, "s16_le,N,44100,i", "Read mix_to_disk_format");

is( jack_port_latency('output','LinuxSampler:playback_1'), 
	2048, "get JACK port latency");



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
