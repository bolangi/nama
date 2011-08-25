# ----------- Initialize --------

package ::;
use Modern::Perl; use Carp;
our (
[% qx(cat ./singletons.pl) %]
	$ui,
	%opts,
	%jack,
	$jack_running,
	$midish_enable,
	$project_name,
	$debug,
	$debug2,
	$banner,
	$project_root,
	$ladspa_sample_rate,
	%devices,
	$fake_jack_lsp,
	$use_jack_plumbing,
	@ecasound_pids,
	$e,
	$user_customization_file,
	$sock,
	$ecasound_tcp_port,
	$hires,
	$waveform_viewer,

);
sub initialize_interfaces {
	
	$debug2 and print "&prepare\n";

	say $banner;

	if ($opts{D}){
		$debug = 1;
		$debug2 = 1;
	}
	if ( ! $opts{t} and ::Graphical::initialize_tk() ){ 
		$ui = ::Graphical->new();
	} else {
		say "Unable to load perl Tk module. Starting in console mode." if $opts{g};
		$ui = ::Text->new();
		can_load( modules =>{ Event => undef})
			or die "Perl Module 'Event' not found. Please install it and try again. Stopping.";
;
		import Event qw(loop unloop unloop_all);
	}
	
	can_load( modules => {AnyEvent => undef})
			or die "Perl Module 'AnyEvent' not found. Please install it and try again. Stopping.";

	choose_sleep_routine();

	$project_name = shift @ARGV;
	$debug and print "project name: $project_name\n";

	$debug and print("\%opts\n======\n", yaml_out(\%opts)); ; 


	read_config(global_config());  # from .namarc if we have one

	setup_user_customization();	

	start_ecasound();


	$debug and print "reading config file\n";
	if ($opts{d}){
		print "project_root $opts{d} specified on command line\n";
		$project_root = $opts{d};
	}
	if ($opts{p}){
		$project_root = getcwd();
		print "placing all files in current working directory ($project_root)\n";
	}

	# capture the sample frequency from .namarc
	($ladspa_sample_rate) = $devices{jack}{signal_format} =~ /(\d+)(,i)?$/;

	# skip initializations if user (test) supplies project
	# directory
	
	first_run() unless $opts{d}; 

	prepare_static_effects_data() unless $opts{S};

	get_ecasound_iam_keywords();
	load_keywords(); # for autocompletion

	chdir $project_root # for filename autocompletion
		or warn "$project_root: chdir failed: $!\n";

	$ui->init_gui;
	$ui->transport_gui;
	$ui->time_gui;

	
	# fake JACK for testing environment

	if( $opts{J}){
		%jack = %{ jack_ports($fake_jack_lsp) };
		$jack_running = 1;
	}

	# periodically check if JACK is running, and get client/port list

	poll_jack() unless $opts{J} or $opts{A};

	sleeper(0.2); # allow time for first polling

	# we will start jack.plumbing only when we need it
	
	if(		$use_jack_plumbing 
	and $jack_running 
	and process_is_running('jack.plumbing')
	){

		say "\nJack.plumbing daemon detected!";
		print "\nAttempting to stop it (will restart as needed)... ";

		kill_jack_plumbing();
		sleeper(0.2);
		if( process_is_running('jack.plumbing') )
		{
		say qq(\n\nUnable to stop jack.plumbing daemon.

Please do one of the following, then restart Nama:

 - kill the jack.plumbing daemon ("killall jack.plumbing")
 - set "use_jack_plumbing: 0" in .namarc

Exiting.);
exit;
		}
		else { say "Stopped." }
	}
		
	start_midish() if $midish_enable;

	# set up autosave
	
    schedule_autosave() unless debugging_options();

	initialize_terminal() unless $opts{T};

	# set default project to "untitled"
	
	if (! $project_name ){
		$project_name = "untitled";
		$opts{c}++; 
	}
	print "\nproject_name: $project_name\n";
	
	load_project( name => $project_name, create => $opts{c}) ;
	restore_effect_chains();
	restore_effect_profiles();
	1;	
}
sub debugging_options {
	grep{$_} $debug, @opts{qw(R D J A E T)};
}
sub start_ecasound {
 	my @existing_pids = split " ", qx(pgrep ecasound);
	select_ecasound_interface();
	sleeper(0.2);
	@ecasound_pids = grep{ 	my $pid = $_; 
							! grep{ $pid == $_ } @existing_pids
						 }	split " ", qx(pgrep ecasound);
}
sub select_ecasound_interface {
	return if $opts{E} or $opts{A};
	if ( can_load( modules => { 'Audio::Ecasound' => undef } )
			and ! $opts{n} ){ 
		say "\nUsing Ecasound via Audio::Ecasound (libecasoundc).";
		{ no warnings qw(redefine);
		*eval_iam = \&eval_iam_libecasoundc; }
		$e = Audio::Ecasound->new();
	} else { 

		no warnings qw(redefine);
		launch_ecasound_server($ecasound_tcp_port);
		init_ecasound_socket($ecasound_tcp_port); 
		*eval_iam = \&eval_iam_neteci;
	}
}
	


sub choose_sleep_routine {
	if ( can_load(modules => {'Time::HiRes'=> undef} ) ) 
		 { *sleeper = *finesleep;
			$hires++; }
	else { *sleeper = *select_sleep }
}
sub finesleep {
	my $sec = shift;
	Time::HiRes::usleep($sec * 1e6);
}
sub select_sleep {
   my $seconds = shift;
   select( undef, undef, undef, $seconds );
}

sub toggle_transport {
	if (engine_running()){ stop_transport() } 
	else { start_transport() }
}
	
{
my $default_port = 2868; # Ecasound's default
sub launch_ecasound_server {

	# we'll try to communicate with an existing ecasound
	# process provided:
	#
	# started with --server option
	# --server-tcp-port option matches --or--
	# nama is using Ecasound's default port 2868
	
	my $port = shift // $default_port;
	my $command = "ecasound -K -C --server --server-tcp-port=$port";
	my $redirect = ">/dev/null &";
	my $ps = qx(ps ax);
	say("Using existing Ecasound server"), return 
		if  $ps =~ /ecasound/
		and $ps =~ /--server/
		and ($ps =~ /tcp-port=$port/ or $port == $default_port);
	say "Starting Ecasound server";
 	system("$command $redirect") == 0 or carp "system $command failed: $?\n";
	sleep 1;
}


sub init_ecasound_socket {
	my $port = shift // $default_port;
	say "Creating socket on port $port.";
	$sock = new IO::Socket::INET (
		PeerAddr => 'localhost', 
		PeerPort => $port, 
		Proto => 'tcp', 
	); 
	die "Could not create socket: $!\n" unless $sock; 
}

sub ecasound_pid {
	my ($ps) = grep{ /ecasound/ and /server/ } qx(ps ax);
	my ($pid) = split " ", $ps; 
	$pid if $sock; # conditional on using socket i.e. Net-ECI
}

sub eval_iam { } # stub

sub eval_iam_neteci {
	my $cmd = shift;
	$cmd =~ s/\s*$//s; # remove trailing white space
	$sock->send("$cmd\r\n"); 
	my $buf;
	$sock->recv($buf, 65536);

	my ($return_value, $length, $type, $reply) =
		$buf =~ /(\d+)# digits
				 \    # space
				 (\d+)# digits
				 \    # space
 				 ([^\r\n]+) # a line of text, probably one character 
				\r\n    # newline
				(.+)  # rest of string
				/sx;  # s-flag: . matches newline

if(	! $return_value == 256 ){
	my $debug++;
	$debug and say "ECI command: $cmd";
	$debug and say "Ecasound reply (256 bytes): ", substr($buf,0,256);
	$debug and say qq(
length: $length
type: $type
full return value: $return_value);
	die "illegal return value, stopped" ;

}
	$reply =~ s/\s+$//; 

	given($type){
		when ('e'){ carp $reply }
		default{ return $reply }
	}

}
}

sub eval_iam_libecasoundc{
	#$debug2 and print "&eval_iam\n";
	my $command = shift;
	$debug and print "iam command: $command\n";
	my (@result) = $e->eci($command);
	$debug and print "result: @result\n" unless $command =~ /register/;
	my $errmsg = $e->errmsg();
	if( $errmsg ){
		$e->errmsg(''); 
		# ecasound already prints error on STDOUT
		# carp "ecasound reports an error:\n$errmsg\n"; 
	}
	"@result";
}

	
1;
__END__
