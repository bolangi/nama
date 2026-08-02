package ::FadeEnvelope;
use v5.36;
our $VERSION = 1.0;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(clip_envelope_to_window);

sub interpolated_point {
	my ($left, $right, $time) = @_;
	my ($left_time, $left_level) = @$left;
	my ($right_time, $right_level) = @$right;
	my $level = $left_level
		+ ($time - $left_time) / ($right_time - $left_time)
		* ($right_level - $left_level);
	[$time, $level]
}

sub clip_envelope_to_window {
	my ($window_start, $window_end, @pairs) = @_;
	my @points;
	push @points, [splice @pairs, 0, 2] while @pairs;
	return () if ! @points;
	return () if $points[-1]->[0] < $window_start;
	return () if $points[0]->[0] > $window_end;

	if ($points[0]->[0] < $window_start){
		my $first_inside = 0;
		$first_inside++ while $points[$first_inside]->[0] < $window_start;
		if ($points[$first_inside]->[0] == $window_start){
			splice @points, 0, $first_inside;
		} else {
			my $boundary = interpolated_point(
				$points[$first_inside - 1],
				$points[$first_inside],
				$window_start,
			);
			splice @points, 0, $first_inside, $boundary;
		}
	}

	if ($points[-1]->[0] > $window_end){
		my $last_inside = $#points;
		$last_inside-- while $points[$last_inside]->[0] > $window_end;
		if ($points[$last_inside]->[0] == $window_end){
			splice @points, $last_inside + 1;
		} else {
			my $boundary = interpolated_point(
				$points[$last_inside],
				$points[$last_inside + 1],
				$window_end,
			);
			splice @points, $last_inside + 1,
				@points - $last_inside - 1, $boundary;
		}
	}

	map { @$_ } @points
}

1;
__END__
