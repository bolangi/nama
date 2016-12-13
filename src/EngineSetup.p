# ----------- Engine Setup and Teardown -----------

package ::;
use Modern::Perl; use Carp;

sub reconfigure_engine {

	logsub("&reconfigure_engine");
	my $force = shift;

	# skip if command line option is set
	# don't skip if $force argument given
	
	return if ($config->{opts}->{R} or $config->{disable_auto_reconfigure})
		and not $force;
	::Engine::sync_action('configure',$force);
}

sub request_setup { 
	my ($package, $filename, $line) = caller();
    logpkg('debug',"reconfigure requested in file $filename:$line");
	$setup->{changed}++
} 

sub generate_setup {::Engine::sync_action('setup') }

sub start_transport { 
	logsub("&start_transport");
	::Engine::sync_action('start');

}

sub stop_transport { 

	logsub("&stop_transport"); 
	::Engine::sync_action('stop');
}
	
1;
__END__
