package ::StatusSnapshot;

use Role::Tiny;
use Modern::Perl '2020';
our $VERSION = 1.0;
{
package ::;

	# these track fields will be inspected
	
	my @relevant_track_fields = qw(
		name
		n
		width
		group 
		playat
		region_start	
		region_end
		looping
		source_id
		source_type
		send_id
		send_type
		rec_status
		current_version
 );
sub status_snapshot {

	#
	# hashref output for detecting if we need to reconfigure engine
	# compared as YAML strings


	# %status_snaphot indicates Nama's internal
	# state. It consists of 
	# - the values of selected global variables
	# - selected field values of each track
	
	my %snapshot = ( project 		=> 	$project->{name},
					 mastering_mode => $mode->mastering,
					 preview        => $mode->{preview},
					 doodle			=> $mode->{doodle},
					 jack_running	=> $jack->{jackd_running},
					 tracks			=> [], );
	map { push @{$snapshot{tracks}}, $_->snapshot(\@relevant_track_fields) }
	grep{ $_->rec_status ne OFF } grep { $_->group ne 'Temp' } ::all_tracks();
	\%snapshot;
}
sub status_snapshot_string { 
	my $json = json_out(status_snapshot());
	$json =~ s/: "(\d+)"/: $1/g; 
	$json
}
}
	
1;
