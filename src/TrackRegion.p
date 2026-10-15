{
package ::TrackRegion;
use Role::Tiny;
use v5.36;
our $VERSION = 1.0;
use ::Globals ();
use ::TimelineAdjustment ();
use Carp ();

# these behaviors are associated with WAV playback

sub is_region { defined $_[0]->{region_start} }

sub startpoint ($track) {
	return unless $track->is_region;
	#return if $track->rec_status ne PLAY;
	#carp $track->name, ": expected PLAY status" if $track->rec_status ne PLAY;
	::Mark::time_from_tag( $track->region_start )
}
sub endpoint ($track) {
	return unless $track->is_region;
	#return if $track->rec_status ne PLAY;
	#carp $track->name, ": expected PLAY status" if $track->rec_status ne PLAY;
	no warnings 'uninitialized'; 
	if ( $track->region_end eq 'END' ){
		return $track->wav_length;
	} else {
		::Mark::time_from_tag( $track->region_end )
	}
}
sub timeline_position ($track) {
	#carp $track->name, ": expected PLAY status" if $track->rec_status ne PLAY;
	#return if $track->rec_status ne PLAY;
	::Mark::time_from_tag( $track->playat )
}

# the following methods adjust
# region start and playat values during edit mode

sub adjusted_duration ($track) {
	if (::timeline_adjustment_active()) {
		my $adjustment = $track->timeline_adjustment;
		return $adjustment->adjusted_endpoint
			 - $adjustment->adjusted_startpoint
	}
	my $duration;
	if ($track->region_start){
		$duration = 	$track->endpoint
			  - $track->startpoint
	} else {
		$duration = 	$track->wav_length;
	}
	$duration
}

sub adjusted_timeline_endpoint ($track) {
	my $adjustment = $track->timeline_adjustment
		if ::timeline_adjustment_active();
	my $setup_length = $adjustment
		? $adjustment->adjusted_endpoint - $adjustment->adjusted_startpoint
		: $track->adjusted_duration;
	no warnings 'uninitialized';
	$setup_length += $adjustment
		? $adjustment->adjusted_timeline_position
		: $track->adjusted_timeline_position;
}

sub timeline_adjustment ($track) {
	return ::timeline_adjustment(::timeline_adjustment_args($track))
		if ::timeline_adjustment_active();

	::TimelineAdjustmentResult->new(
		window_overlap_case => 'unadjusted',
		adjusted_timeline_position => $track->timeline_position,
		adjusted_startpoint => $track->startpoint,
		adjusted_endpoint => $track->endpoint,
	)
}

sub adjusted_startpoint ($track) {
	$track->timeline_adjustment->adjusted_startpoint
	
}
sub adjusted_timeline_position ($track) {
	$track->timeline_adjustment->adjusted_timeline_position
}
sub adjusted_endpoint ($track) {
	$track->timeline_adjustment->adjusted_endpoint
}

sub region_is_out_of_bounds ($track) {
	return unless ::timeline_adjustment_active();
	! $track->timeline_adjustment->is_playable
}

}
1
