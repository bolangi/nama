use Test2::Bundle::More;
use strict;
use warnings;

use ::Log qw(initialize_logger logit logpkg set_log_sink);

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

done_testing;
