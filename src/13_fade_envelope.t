use Test2::Bundle::More;
use strict;
use ::FadeEnvelope qw(clip_envelope_to_window envelope_level_at_time);

my $window_start = 0;
my $window_end = 10;

is_deeply(
	[clip_envelope_to_window($window_start, $window_end, 2, 0, 4, 1)],
	[2, 0, 4, 1],
	'a fade entirely inside the window is unchanged',
);

is_deeply(
	[clip_envelope_to_window(
		$window_start, $window_end,
		-2, 0,
		 2, 1,
		 8, 1,
		12, 0,
	)],
	[0, 0.5, 2, 1, 8, 1, 10, 0.5],
	'a fade crossing both window boundaries is interpolated',
);

is_deeply(
	[clip_envelope_to_window($window_start, $window_end, -4, 0, -2, 1)],
	[],
	'an envelope entirely before the window is skipped',
);

is_deeply(
	[clip_envelope_to_window($window_start, $window_end, 12, 0, 14, 1)],
	[],
	'an envelope entirely after the window is skipped',
);

my @fade_out = (2, 1, 4, 0);
is(
	envelope_level_at_time(1, @fade_out),
	1,
	'the level before a fade-out is unity',
);
is(
	envelope_level_at_time(5, @fade_out),
	0,
	'the level after a fade-out is silent',
);

my @fade_in = (2, 0, 4, 1);
is(
	envelope_level_at_time(1, @fade_in),
	0,
	'the level before a fade-in is silent',
);
is(
	envelope_level_at_time(5, @fade_in),
	1,
	'the level after a fade-in is unity',
);

my @fade_out_then_in = (@fade_out, 6, 0, 8, 1);
is(
	envelope_level_at_time(5, @fade_out_then_in),
	0,
	'the level between a fade-out and fade-in is silent',
);

done_testing();
__END__
