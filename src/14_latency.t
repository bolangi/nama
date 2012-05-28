package ::; 
use ::;
use Test::More qw(no_plan);
use Cwd;
use File::Path qw(make_path remove_tree);

use strict;
use warnings;
no warnings qw(uninitialized);

our ($expected_setup_lines);
our $test_dir = "/tmp/nama-test";
make_path($test_dir);


diag ("TESTING $0\n");

diag("working directory: ",cwd);

apply_ecasound_test_harness();
diag "options: @ARGV";

bootstrap_environment();

diag "Check representative variable from default .namarc";

is( $config->{mix_to_disk_format}, "s16_le,N,44100,i", "Read mix_to_disk_format");

is( jack_port_latency('output','LinuxSampler:playback_1'), 
	2048, "get JACK port latency");

*cmd = \&command_process; # shortcut

cmd("add piano");



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

sub cleanup { 	remove_tree($test_dir) }

chdir "/tmp";
cleanup();
1;
__END__
