{
package ::TrackRegion;
use Role::Tiny;
use v5.36;
our $VERSION = 1.0;
use ::Globals qw(:all);
use Carp;

# these behaviors are associated with WAV playback

sub is_region { defined $_[0]->{region_start} }

sub startpoint {
	my $track = shift;
	return unless $track->is_region;
	#return if $track->rec_status ne PLAY;
	#carp $track->name, ": expected PLAY status" if $track->rec_status ne PLAY;
	::Mark::time_from_tag( $track->region_start )
}
sub endpoint {
	my $track = shift;
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
sub timeline_position {
	my $track = shift;
	#carp $track->name, ": expected PLAY status" if $track->rec_status ne PLAY;
	#return if $track->rec_status ne PLAY;
	::Mark::time_from_tag( $track->playat )
}

# the following methods adjust
# region start and playat values during edit mode

sub adjusted_duration {
	my $track = shift;
	my $duration;
	if ($track->region_start){
		$duration = 	$track->adjusted_endpoint
			  - $track->adjusted_startpoint
	} else {
		$duration = 	$track->wav_length;
	}
	$duration
}

sub adjusted_timeline_endpoint {
	my $track = shift;
	my $setup_length = $track->adjusted_duration;
	no warnings 'uninitialized';
	$setup_length += $track->adjusted_timeline_position;
}

sub adjusted_startpoint {
	my $track = shift;
	return $track->startpoint unless ::timeline_adjustment_active();
	::new_region_start(::timeline_adjustment_args($track));
	
}
sub adjusted_timeline_position {
	my $track = shift;
	return $track->timeline_position unless ::timeline_adjustment_active();
	::new_playat(::timeline_adjustment_args($track));
}
sub adjusted_endpoint {
	my $track = shift;
	return $track->endpoint unless ::timeline_adjustment_active();
	::new_region_end(::timeline_adjustment_args($track));
}

sub region_is_out_of_bounds {
	return unless ::timeline_adjustment_active();
	my $track = shift;
	::window_overlap_case(::timeline_adjustment_args($track)) =~ /out_of_bounds/
}

}
1
