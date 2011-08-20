# ------ Memoize subroutines ------

package ::;
use Modern::Perl;
our ( $memoize );

BEGIN { # OPTMIZATION
my @wav_functions = qw(
	get_versions 
	candidates 
	targets 
	versions 
	last 
);
my @track_functions = qw(
	dir 
	basename 
	full_path 
	group_last 
	last 
	current_wav 
	current_version 
	monitor_version 
	maybe_monitor 
	rec_status 
	region_start_time 
	region_end_time 
	playat_time 
	fancy_ops 
	input_path 
);
sub track_memoize { # before generate_setup
	return unless $memoize;
	map{package ::Track; memoize($_) } @track_functions;
}
sub track_unmemoize { # after generate_setup
	return unless $memoize;
	map{package ::Track; unmemoize ($_)} @track_functions;
}
sub rememoize {
	return unless $memoize;
	map{package ::Wav; unmemoize ($_); memoize($_) } 
		@wav_functions;
}
sub init_memoize {
	return unless $memoize;
	map{package ::Wav; memoize($_) } @wav_functions;
}
}
1;
__END__

