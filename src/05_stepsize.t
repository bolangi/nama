use Test2::Bundle::More;
use strict;
use warnings;

use ::StepSize qw(
	next_parameter_stepsize
	previous_parameter_stepsize
	next_time_stepsize
	previous_time_stepsize
);

is next_parameter_stepsize(0.01), 0.02,
	'parameter step advances from 1 to 2 within a decade';
is next_parameter_stepsize(0.02), 0.05,
	'parameter step advances from 2 to 5 within a decade';
is next_parameter_stepsize(0.05), 0.1,
	'parameter step advances from 5 to 1 in the next decade';
is previous_parameter_stepsize(0.1), 0.05,
	'parameter step moves into the previous decade';

is next_parameter_stepsize(1, 3), 10,
	'three parameter positions replace the former 10x operation';
is previous_parameter_stepsize(10, 3), 1,
	'three reverse parameter positions undo three forward positions';

is next_parameter_stepsize(0.03), 0.05,
	'next parameter step handles a manually entered value';
is previous_parameter_stepsize(0.03), 0.02,
	'previous parameter step handles a manually entered value';
is next_parameter_stepsize(2, 0), 2,
	'a zero position move leaves the parameter step unchanged';

is next_time_stepsize(0.02), 0.05,
	'fractional seconds use the 1, 2, 5 sequence';
is next_time_stepsize(0.5), 1,
	'fractional seconds advance to one second';
is previous_time_stepsize(1), 0.5,
	'one second moves back to half a second';

is next_time_stepsize(10), 30,
	'seconds include the 10 to 30 transition';
is next_time_stepsize(30), 60,
	'thirty seconds advances to one minute';
is next_time_stepsize(60), 120,
	'one minute advances to two minutes';
is next_time_stepsize(600), 1800,
	'ten minutes advances to thirty minutes';
is next_time_stepsize(1800), 3600,
	'thirty minutes advances to one hour';
is next_time_stepsize(3600), 7200,
	'one hour advances to two hours';

is next_time_stepsize(30, 3), 300,
	'three time positions cross from seconds into minutes';
is previous_time_stepsize(300, 3), 30,
	'three reverse time positions cross back into seconds';

is next_time_stepsize(45), 60,
	'next time step handles a manually entered value';
is previous_time_stepsize(45), 30,
	'previous time step handles a manually entered value';

is next_time_stepsize(216_000), 216_000,
	'time step remains at the current 60-hour upper boundary';
is previous_time_stepsize(216_000), 108_000,
	'time step can move down from the upper boundary';

for my $case (
	[ sub { next_parameter_stepsize(0) }, qr/positive number/, 'zero parameter step is rejected' ],
	[ sub { next_time_stepsize(-1) }, qr/positive number/, 'negative time step is rejected' ],
	[ sub { next_time_stepsize(1, 1.5) }, qr/non-negative integer/, 'fractional position count is rejected' ],
) {
	my ($code, $expected, $name) = @$case;
	my $error = eval { $code->(); q() };
	$error = $@ if $@;
	like $error, $expected, $name;
}

done_testing;
