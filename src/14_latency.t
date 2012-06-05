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
cleanup();
make_path($test_dir);


diag ("TESTING $0\n");

diag("working directory: ",cwd);

apply_ecasound_test_harness();
push @ARGV, '-L','ECI';
diag "options: @ARGV";

bootstrap_environment();

diag "Check representative variable from default .namarc";

is( $config->{mix_to_disk_format}, "s16_le,N,44100,i", "Read mix_to_disk_format");

is( jack_port_latency('output','LinuxSampler:playback_1'), 
	2048, "get JACK port latency");

*cmd = \&command_process; # shortcut

# 'send null' doesn't work!! 
#cmd("Master; send null"); # so engine doesn't actually use JACK
cmd("sh");
cmd("add sine; source null; afx sine_fcac 220 0.1");
cmd("Mixdown rec"); # record the cooked signal
cmd("arm");
is(eval_iam("cs-is-valid"),1, 'Load a valid chain setup');
#diag(::ChainSetup::ecasound_chain_setup());
#limit_processing_time(3);
cmd("cs-set-length 3");
cmd("start");
sleeper(0.5);
sleeper(1) while engine_running();
rec_cleanup();
my $wav = join_path(this_wav_dir(),'Mixdown_1.wav');
is( abs((-s $wav) - 528_428) < 30_000, 1, "recorded WAV file, 3s");
is($this_track->rec_status, 'MON', 'Ready to play WAV file after mixdown');
diag(::ChainSetup::ecasound_chain_setup());
cmd("setpos 0.5");
diag(eval_iam("getpos"));
is( abs(eval_iam("getpos") - 0.5)<0.001, 1, 'Set position');
cmd("new_mark in1");
cmd("setpos 1.0");
cmd("new_mark out1");
cmd("setpos 1.5");
cmd("new_mark in2");
cmd("setpos 2.0");
cmd("new_mark out2");
is($this_track->monitor_version, 1, 'Find WAV file to play, normal track');
cmd("sine off");
cmd("link_track sinuous Mixdown");
cmd("sinuous");
is($this_track->monitor_version, 1, 'Find WAV file to play, link track');
cmd("arm");

symlink($wav, join_path(this_wav_dir(),'sinister.wav'));
cmd("scan");
cmd("add_track sinister; mon");
reconfigure_engine();
is($this_track->monitor_version, 1, 'Find WAV file to play, unnumbered WAV file');

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
#my $testfile = '/tmp/nama-test/untitled/.wav/Mixdown_1.wav';
#diag "$testfile: length ",-s $testfile;
#unlink $testfile;
#cleanup();
1;
__END__
