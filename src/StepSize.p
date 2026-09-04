package ::StepSize;
use v5.36;

use Carp qw(croak);
use Exporter qw(import);
use POSIX qw(floor);
use Scalar::Util qw(looks_like_number);

our $VERSION = 1.0;
our @EXPORT_OK = qw(
	next_parameter_stepsize
	previous_parameter_stepsize
	next_time_stepsize
	previous_time_stepsize
);

my @parameter_mantissas = (1, 2, 5);
my @time_multipliers = (1, 2, 5, 10, 30, 60);
my @time_units = (1, 60, 60 * 60);
my $relative_epsilon = 1e-12;

my %seen_time_step;
my @time_steps = sort { $a <=> $b }
	grep { !$seen_time_step{$_}++ }
	map {
		my $unit = $_;
		map { $_ * $unit } @time_multipliers
	} @time_units;

sub next_parameter_stepsize ($current, $count = 1) {
	_validate_arguments($current, $count);
	$current = _next_parameter_step($current) for 1 .. $count;
	$current
}

sub previous_parameter_stepsize ($current, $count = 1) {
	_validate_arguments($current, $count);
	$current = _previous_parameter_step($current) for 1 .. $count;
	$current
}

sub next_time_stepsize ($current, $count = 1) {
	_validate_arguments($current, $count);
	$current = _next_time_step($current) for 1 .. $count;
	$current
}

sub previous_time_stepsize ($current, $count = 1) {
	_validate_arguments($current, $count);
	$current = _previous_time_step($current) for 1 .. $count;
	$current
}

sub _next_parameter_step ($current) {
	my @candidates = _parameter_candidates($current);
	for my $candidate (@candidates) {
		return $candidate
			if $candidate > $current
			and !_nearly_equal($candidate, $current);
	}
	croak "Unable to find parameter step above $current";
}

sub _previous_parameter_step ($current) {
	my @candidates = reverse _parameter_candidates($current);
	for my $candidate (@candidates) {
		return $candidate
			if $candidate < $current
			and !_nearly_equal($candidate, $current);
	}
	croak "Unable to find parameter step below $current";
}

sub _parameter_candidates ($current) {
	my $exponent = floor(log($current) / log(10));
	sort { $a <=> $b }
		map {
			my $power = $_;
			map { _normalized($_ * 10 ** $power) } @parameter_mantissas
		} $exponent - 3 .. $exponent + 3
}

sub _next_time_step ($current) {
	return _next_parameter_step($current) if $current < 1;

	for my $candidate (@time_steps) {
		return $candidate
			if $candidate > $current
			and !_nearly_equal($candidate, $current);
	}

	# Hours are the largest unit currently supported.  Stay at 60 hours.
	$current <= $time_steps[-1] ? $time_steps[-1] : $current
}

sub _previous_time_step ($current) {
	return _previous_parameter_step($current) if $current <= 1;

	for my $candidate (reverse @time_steps) {
		return $candidate
			if $candidate < $current
			and !_nearly_equal($candidate, $current);
	}

	_previous_parameter_step(1)
}

sub _validate_arguments ($current, $count) {
	croak 'Step size must be a positive number'
		unless looks_like_number($current) and $current > 0;
	croak 'Step count must be a non-negative integer'
		unless looks_like_number($count) and $count >= 0 and $count == int($count);
}

sub _nearly_equal ($left, $right) {
	my $scale = abs($left) > abs($right) ? abs($left) : abs($right);
	abs($left - $right) <= $relative_epsilon * $scale
}

sub _normalized ($value) { 0 + sprintf '%.14g', $value }

1;
