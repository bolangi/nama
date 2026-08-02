use Test2::Bundle::More;
use strict;
use ::FadeEnvelope qw(clip_envelope_to_window);

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

done_testing();
__END__
