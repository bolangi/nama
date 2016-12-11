# ----------- Engine Setup and Teardown -----------

package ::;
use Modern::Perl;
no warnings 'uninitialized';

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

1
	

__END__
