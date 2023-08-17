# ----------- Engine Setup and Teardown -----------

package ::;
use Modern::Perl; use Carp;

sub reconfigure_engine {

	logsub((caller(0))[3]);

	# skip if command line option is set
	
	return if $config->{opts}->{R};
	refresh_wav_cache();
	update_jack_client_list();
	refresh_tempo_map() if $config->{use_metronome};
	project_snapshot();
	::Engine::sync_action('configure');
}

sub request_setup { 
	my ($package, $filename, $line) = caller();
    logpkg('debug',"reconfigure requested in file $filename:$line");
	$setup->{changed}++
} 

sub generate_setup {::Engine::sync_action('setup') }

sub start_transport { 
	logsub((caller(0))[3]);
	::Engine::sync_action('start');

}

sub stop_transport { 

	logsub((caller(0))[3]); 
	::Engine::sync_action('stop');
}
	
1;
__END__
