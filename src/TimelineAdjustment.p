package ::TimelineAdjustment;
use v5.36;
our $VERSION = 1.0;
use Carp qw(carp);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(timeline_adjustment);

# Input values describe one track/region and one permanent-timeline window:
# has_region, playat, region_start, region_end, wav_length,
# timeline_play_start, and timeline_play_end.
# The result contains only values needed to configure the adjusted engine IO.
sub timeline_adjustment {
	my $args = shift;

	my $has_region = $args->{has_region};
	if ($has_region and (
		! defined $args->{region_start}
		or ! defined $args->{region_end}
	)) {
		carp "$args->{trackname}: improperly defined region";
		return
	}

	my $source_start = $has_region ? $args->{region_start} : 0;
	my $source_end   = $has_region ? $args->{region_end} : $args->{wav_length};
	my $track_start  = $args->{playat};
	my $track_end    = $track_start + $source_end - $source_start;
	my $window_start = $args->{timeline_play_start};
	my $window_end   = $args->{timeline_play_end};

	my $case;
	if ($window_end <= $track_start) {
		$case = 'out_of_bounds_near';
	}
	elsif ($window_start >= $track_end) {
		$case = 'out_of_bounds_far';
	}
	elsif ($window_start >= $track_start) {
		$case = $has_region
			? 'play_start_within_region'
			: 'no_region_play_start_after_playat_delay';
	}
	else {
		$case = $has_region
			? 'play_start_during_playat_delay'
			: 'no_region_play_start_during_playat_delay';
	}

	return ::TimelineAdjustmentResult->new(
		window_overlap_case => $case,
		adjusted_timeline_position => '*',
		adjusted_startpoint => '*',
		adjusted_endpoint => '*',
	) if $case =~ /out_of_bounds/;

	my $intersection_start = $window_start > $track_start
		? $window_start : $track_start;
	my $requested_endpoint = $source_start + $window_end - $track_start;
	my $adjusted_endpoint = $requested_endpoint < $args->{wav_length}
		? $requested_endpoint : $args->{wav_length};

	::TimelineAdjustmentResult->new(
		window_overlap_case => $case,
		adjusted_timeline_position => $intersection_start - $window_start,
		adjusted_startpoint => $source_start + $intersection_start - $track_start,
		# The active window may intentionally extend past the nominal
		# region to leave processing time for effect tails.
		adjusted_endpoint => $adjusted_endpoint,
	)
}

package ::TimelineAdjustmentResult;

sub new {
	my ($class, %args) = @_;
	bless \%args, $class
}
sub window_overlap_case        { $_[0]->{window_overlap_case} }
sub adjusted_timeline_position { $_[0]->{adjusted_timeline_position} }
sub adjusted_startpoint        { $_[0]->{adjusted_startpoint} }
sub adjusted_endpoint          { $_[0]->{adjusted_endpoint} }
sub is_playable                { $_[0]->window_overlap_case !~ /out_of_bounds/ }

1;
__END__
