# ------ Memoize subroutines ------
package ::;
use Modern::Perl;
use Memoize qw(memoize unmemoize);

BEGIN { # OPTMIZATION
my @wav_functions = qw(
	get_versions 
	candidates 
	_targets 
	_versions 
);
my @track_methods = qw(
	dir 
	basename 
	full_path 
	group_last 
	last 
	current_wav 
	current_version 
	playback_version 
	maybe_playback
	rec_status 
	region_start_time 
	region_end_time 
	playat_time 
	user_ops 
	input_path 
	waveform
);
sub track_memoize { # before generate_setup
	return unless $config->{memoize};
	map{package ::Track; memoize($_) } @track_methods;
}
sub track_unmemoize { # after generate_setup
	return unless $config->{memoize};
	map{package ::Track; unmemoize ($_)} @track_methods;
}
sub refresh_wav_cache {
	return unless $config->{memoize};
	map{package ::Wav; unmemoize ($_); memoize($_) } 
		@wav_functions;
}
sub latency_memoize { 
	map{ memoize($_) } ('::self_latency','::latency_of');
}
sub latency_unmemoize {
	map{ unmemoize($_) } ('::self_latency','::latency_of');
}
sub latency_rememoize { latency_unmemoize(); latency_memoize() }

sub init_wav_memoize {
	return unless $config->{memoize};
	map{package ::Wav; memoize($_) } @wav_functions;
}
}
1;
__END__

