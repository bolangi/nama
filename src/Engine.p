{
package ::Engine;
our $VERSION = 1.0;
use Modern::Perl;
use Carp;
our @ISA;
our %by_name;
our @ports = (57000..57050);
our %port = (
	fof => 57201,
	bus => 57202,
);
use ::Globals qw(:all);
use ::Object qw( 
				name
				port
				jack_seek_delay
				jack_transport_mode
				events
				socket
				pids
				ecasound
				buffersize
				on_reconfigure
    			on_exit
				 );

sub new {
	my $class = shift;	
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	::pager_newline("$vals{name}: returning existing engine"), 
		return $by_name{$vals{name}} if $by_name{$vals{name}};
	my $self = bless { name => 'default', %vals }, $class;
	#print "object class: $class, object type: ", ref $self, $/;
	$by_name{ $self->name } = $self;
	$self->initialize_ecasound();
	$this_engine = $self;
}
sub initialize_ecasound { 
	my $self = shift;
 	my @existing_pids = split " ", qx(pgrep ecasound);
	$self->launch_ecasound_server;
	$self->{pids} = [ 
		grep{ 	my $pid = $_; ! grep{ $pid == $_ } @existing_pids }	
		split " ", qx(pgrep ecasound) 
	];
}
sub launch_ecasound_server {}

### class methods

sub engines { values %by_name }
}
sub sync_action {
	my ($method, @args) = @_;
	$_->$method(@args) for engines()
}

{
package ::NetEngine;
our $VERSION = 1.0;
use Modern::Perl;
use ::Log qw(logpkg);
use ::Globals qw(:all);
use ::Log qw(logit);
use Carp qw(carp);
our @ISA = '::Engine';

sub init_ecasound_socket {
	my $self = shift;
	my $port = $self->port;
	::pager_newline("Creating socket on port $port.");
	$self->{socket} = new IO::Socket::INET (
		PeerAddr => 'localhost', 
		PeerPort => $port, 
		Proto => 'tcp', 
	); 
	die "Could not create socket: $!\n" unless $self->{socket}; 
}
sub launch_ecasound_server {
	my $self = shift;
	my $port = $self->port;
	
	# we'll try to communicate with an existing ecasound
	# process provided:
	#
	# started with --server option
	# --server-tcp-port option matches 
	
	my $command = "ecasound -K -C --server --server-tcp-port=$port";
	my $redirect = ">/dev/null &";
	my $ps = qx(ps ax);
	if ( $ps =~ /ecasound/ and $ps =~ /--server/ and ($ps =~ /tcp-port=$port/) )
	{ 
		::pager_newline("Found existing Ecasound server on port $port") 
	}
	else 
	{ 
		
		::pager_newline("Starting Ecasound server on port $port");
		system("$command $redirect") == 0 or carp("system $command failed: $?\n")
	}
	sleep 1;
	$self->init_ecasound_socket();
}
sub ecasound {
	my $self = shift;
	my $cmd = shift;
	#my $category = ::munge_category(shift());
	my $category = "ECI";

	logit($category, 'debug', "Net-ECI sent: $cmd");

	$cmd =~ s/\s*$//s; # remove trailing white space
	$this_engine->{socket}->send("$cmd\r\n");
	my $buf;
	# get socket reply, restart ecasound on error
	my $result = $this_engine->{socket}->recv($buf, $config->{engine_command_output_buffer_size});
	defined $result or ::throw("Ecasound failed to respond"), return;

	my ($return_value, $setup_length, $type, $reply) =
		$buf =~ /(\d+)# digits
				 \    # space
				 (\d+)# digits
				 \    # space
 				 ([^\r\n]+) # a line of text, probably one character 
				\r\n    # newline
				(.+)  # rest of string
				/sx;  # s-flag: . matches newline

if(	! $return_value == 256 ){
	logit($category,'error',"Net-ECI bad return value: $return_value (expected 256)");

}
	no warnings 'uninitialized';
	$reply =~ s/\s+$//; 

	if( $type eq 'e')
	{
		logit($category,'error',"ECI error! Command: $cmd. Reply: $reply");
	}
	else
	{ 	logit($category,'debug',"Net-ECI  got: $reply");
		$reply
	}
	
}
sub configure {
	package ::;
	my $self = shift;
	my $force = shift;

	# don't disturb recording/mixing
	
	return if ::ChainSetup::really_recording() and engine_running();
	
	# store a lists of wav-recording tracks for the rerecord
	# function
	
	restart_wav_memoize(); # check if someone has snuck in some files
	
	find_duplicate_inputs(); # we will warn the user later

	if( $force or $setup->{changed} ){ 
		logpkg('debug',"reconfigure requested");
		$setup->{_old_snapshot} = status_snapshot_string();
} 
	else {
		my $old = $setup->{_old_snapshot};
		my $current = $setup->{_old_snapshot} = status_snapshot_string();	
		if ( $current eq $old){
				logpkg('debug',"no change in setup");
				return;
		}
		logpkg('debug',"detected configuration change");
		logpkg('debug', diff(\$old, \$current));
	}
	$setup->{changed} = 0 ; # reset for next time

	nama('show_tracks');

	{ local $quiet = 1; stop_transport() }

	trigger_rec_cleanup_hooks();
	trigger_rec_setup_hooks();
	$setup->{_old_rec_status} = { 
		map{$_->name => $_->rec_status } rec_hookable_tracks()
	};
	if ( generate_setup() ){
	
		reset_latency_compensation() if $config->{opts}->{Q};
		
		logpkg('debug',"I generated a new setup");
		
		{ local $quiet = 1; connect_transport() }
		propagate_latency() if $config->{opts}->{Q} and $jack->{jackd_running};
		show_status();

		if ( ::ChainSetup::really_recording() )
		{
			$project->{playback_position} = 0
		}
		else 
		{ 
			set_position($project->{playback_position}) if $project->{playback_position} 
		}
		start_transport('quiet') if $mode->eager 
								and ($mode->doodle or $mode->preview);
		transport_status();
		$ui->flash_ready;
		1
	}
}
} # end package
{
package ::LibEngine;
our $VERSION = 1.0;
use Modern::Perl;
use ::Globals qw(:all);
use ::Log qw(logit);
our @ISA = '::Engine';
sub launch_ecasound_server {
	my $self = shift;
	::pager_newline("Using Ecasound via Audio::Ecasound (libecasoundc)");
	$self->{ecasound} = Audio::Ecasound->new();
}
sub ecasound {
	#logsub("&ecasound");
	my $self = shift;
	my $cmd = shift;
	my $category = ::munge_category(shift());
	
	logit($category,'debug',"ECI sent: $cmd");

	my (@result) = $this_engine->{ecasound}->eci($cmd);
	logit($category, 'debug',"ECI  got: @result") 
		if $result[0] and not $cmd =~ /register/ and not $cmd =~ /int-cmd-list/; 
	my $errmsg = $this_engine->{ecasound}->errmsg();
	if( $errmsg ){
		::throw("Ecasound error: $errmsg") if $errmsg =~ /in engine-status/;
		$this_engine->{ecasound}->errmsg(''); 
	}
	"@result";
}
}
{ package ::MidishEngine;
} # end package 
1

__END__

