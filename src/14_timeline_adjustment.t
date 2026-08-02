use Test2::Bundle::More;
use strict;
use ::TimelineAdjustment qw(timeline_adjustment);

my @tests = split "\n", <<TEST_DATA;
1  1 12 5 15 4   8  *  *  * 30 out_of_bounds_near region
2  1 12 5 15 23 26  *  *  * 30 out_of_bounds_far region
3  1 12 5 15 10 17  2  5 10 30 play_start_during_playat_delay region
4  1 12 5 15 13 21  0  6 14 30 play_start_within_region region
5  1 12 5 15 21 26  0 14 19 30 play_start_within_region region
6  1  0 5 15  5  9  0 10 14 30 play_start_within_region region
7  0  0 -  -  5  9  0  5  9 30 no_region_play_start_after_playat_delay no_playat
8  0  2 -  -  5  9  0  3  7 30 no_region_play_start_after_playat_delay
9  0  6 -  -  5  9  1  0  3 30 no_region_play_start_during_playat_delay
10 0  6 -  -  3  5  *  *  * 30 out_of_bounds_near no_region
11 0  6 -  - 40 49  *  *  * 30 out_of_bounds_far no_region
12 0  6 -  - 34 40  0 28 30 30 no_region_play_start_after_playat_delay end_after_wav_length
TEST_DATA

for (@tests){
	my (
		$index,
		$has_region,
		$playat,
		$region_start,
		$region_end,
		$timeline_play_start,
		$timeline_play_end,
		$adjusted_timeline_position,
		$adjusted_startpoint,
		$adjusted_endpoint,
		$wav_length,
		$case,
		$comment,
	) = split;
	$region_start = undef if $region_start eq '-';
	$region_end = undef if $region_end eq '-';

	my $adjustment = timeline_adjustment({
		has_region => $has_region,
		playat => $playat,
		region_start => $region_start,
		region_end => $region_end,
		timeline_play_start => $timeline_play_start,
		timeline_play_end => $timeline_play_end,
		wav_length => $wav_length,
	});

	is($adjustment->window_overlap_case, $case,
		"$index: $case $comment");
	is($adjustment->adjusted_timeline_position, $adjusted_timeline_position,
		"$index: adjusted timeline position");
	is($adjustment->adjusted_startpoint, $adjusted_startpoint,
		"$index: adjusted source startpoint");
	is($adjustment->adjusted_endpoint, $adjusted_endpoint,
		"$index: adjusted source endpoint");
}

done_testing();
__END__
