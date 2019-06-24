{
package ::TrackRegion;
use Role::Tiny;
use Modern::Perl;
use ::Globals qw(:all);
use Carp;

# these behaviors are associated with WAV playback

sub is_region { defined $_[0]->{region_start} }

sub region_start_time {
	my $track = shift;
	return unless $track->is_region;
	#return if $track->rec_status ne PLAY;
	carp $track->name, ": expected PLAY status" if $track->rec_status ne PLAY;
	::Mark::time_from_tag( $track->region_start )
}
sub region_end_time {
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
sub playat_time {
	my $track = shift;
	carp $track->name, ": expected PLAY status" if $track->rec_status ne PLAY;
	#return if $track->rec_status ne PLAY;
	::Mark::time_from_tag( $track->playat )
}

# the following methods adjust
# region start and playat values during edit mode

sub shifted_length {
	my $track = shift;
	my $setup_length;
	if ($track->region_start){
		$setup_length = 	$track->shifted_region_end_time
				  - $track->shifted_region_start_time
	} else {
		$setup_length = 	$track->wav_length;
	}
	no warnings 'uninitialized';
	$setup_length += $track->shifted_playat_time;
}

sub shifted_region_start_time {
	my $track = shift;
	return $track->region_start_time unless $mode->{offset_run};
	::new_region_start(::edit_vars($track));
	
}
sub shifted_playat_time { 
	my $track = shift;
	return $track->playat_time unless $mode->{offset_run};
	::new_playat(::edit_vars($track));
}
sub shifted_region_end_time {
	my $track = shift;
	return $track->region_end_time unless $mode->{offset_run};
	::new_region_end(::edit_vars($track));
}

sub region_is_out_of_bounds {
	return unless $mode->{offset_run};
	my $track = shift;
	::case(::edit_vars($track)) =~ /out_of_bounds/
}

}
1
