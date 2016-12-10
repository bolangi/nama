# ------------- Realtime control routines -----------

## loading and running the Ecasound engine

package ::;
use Modern::Perl; use Carp;

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
