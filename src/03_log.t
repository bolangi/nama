use Test2::Bundle::More;
use strict;
use warnings;

use ::Log qw(
	initialize_logger logit logpkg set_log_sink
	initialize_output emit_output set_output_sink
);
use File::Temp qw(tempfile);

my @output;
my $lazy_calls = 0;

initialize_logger('Foo,#Bar');
logit('Audio::Nama::Foo', 'debug', 'buffered');
logit('Audio::Nama::Bar', 'debug', 'excluded');
logit('Audio::Nama::Other', 'debug', sub { $lazy_calls++; 'disabled' });
set_log_sink(sub { push @output, @_ });

is scalar @output, 1, 'buffered enabled message is flushed to sink';
like $output[0], qr/Audio::Nama::Foo \(L \d+\) buffered\n\z/,
	'message contains category, source line and text';
is $lazy_calls, 0, 'disabled lazy message is not evaluated';

logit('Audio::Nama::Foo', 'debug', 'one', sub { $lazy_calls++; ' two' });
is $lazy_calls, 1, 'enabled lazy message is evaluated';
like $output[-1], qr/one two\n\z/, 'message arguments retain print-style concatenation';

logit('Audio::Nama::Foo', 'trace', 'hidden');
is scalar @output, 2, 'trace is hidden without NOISY';

initialize_logger('ALL,#Foo,NOISY');
set_log_sink(sub { push @output, @_ });
my $before = scalar @output;
logit('Audio::Nama::Foo', 'debug', 'excluded from ALL');
logit('SUB', 'debug', 'included by ALL');
logit('Audio::Nama::EffectsRegistry', 'trace', 'noisy output');
is scalar(@output) - $before, 2, 'ALL exclusion and NOISY are preserved';
like $output[-1], qr/noisy output\n\z/, 'NOISY enables trace messages';

initialize_logger('03_log');
set_log_sink(sub { push @output, @_ });
$before = scalar @output;
logpkg('debug', 'file-derived category');
is scalar(@output) - $before, 1, 'logpkg matches its file-derived category';
like $output[-1], qr/Audio::Nama::03_log .*file-derived category\n\z/,
	'logpkg normalizes the generated filename';

my ($log_fh, $logfile) = tempfile();
close $log_fh;
local $ENV{NAMA_LOGFILE} = $logfile;
initialize_output();

my ($immediate_stdout, $immediate_stderr, @displayed);
open my $stdout_fh, '>', \$immediate_stdout or die $!;
open my $stderr_fh, '>', \$immediate_stderr or die $!;
emit_output('stdout early', $stdout_fh);
emit_output('stderr early', $stderr_fh);
set_output_sink(sub { push @displayed, @_ });
emit_output('after startup', $stdout_fh);

is $immediate_stdout, 'stdout early', 'early stdout is displayed immediately';
is $immediate_stderr, 'stderr early', 'early stderr is displayed immediately';
is \@displayed, ['stdout early', 'stderr early', 'after startup'],
	'early output is replayed in order and later output uses the display sink';
open my $read_log, '<', $logfile or die $!;
my $logged = do { local $/; <$read_log> };
close $read_log;
is $logged, 'stdout earlystderr earlyafter startup',
	'logfile contains stdout, stderr and later output in dispatch order';

done_testing;
