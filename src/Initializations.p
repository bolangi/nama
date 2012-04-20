# ----------- Initialize --------

package ::;
use Modern::Perl; use Carp;

sub definitions {

	$| = 1;     # flush STDOUT buffer on every write

	$ui eq 'bullwinkle' or die "no \$ui, bullwinkle";

	[% qx(./strip_all ./var_types.pl) %]

	$text->{wrap} = new Text::Format {
		columns 		=> 75,
		firstIndent 	=> 0,
		bodyIndent		=> 0,
		tabstop			=> 4,
	};

	$debug2 = 0; # subroutine names
	$debug = 0; # debug statements

	####### Initialize singletons #######

	# Some of these "singletons" (imported by 'use Globals')
	# are just hashes, some have object behavior.
	#
	# $file belongs to class ::File, and uses
	# AUTOLOAD to generate methods to provide full path
	# to various system files, for example $file->state_store

	{
	package ::File;
		use Carp;
		sub logfile {
			my $self = shift;
			$ENV{NAMA_LOGFILE} || $self->_logfile
		}
		sub AUTOLOAD {
			my ($self, $filename) = @_;
			# get tail of method call
			my ($method) = $::File::AUTOLOAD =~ /([^:]+)$/;
			croak "$method: illegal method call" unless $self->{$method};
			my $dir_sub = $self->{$method}->[1];
			$filename ||= $self->{$method}->[0];
			my $path = ::join_path($dir_sub->(), $filename);
			$path;
		}
		1;
	}
	$file = bless 
	{
		effects_cache 			=> ['.effects_cache', 		\&project_root],
		gui_palette 			=> ['palette',        		\&project_root],
		state_store 			=> ['State',          		\&project_dir ],
		git_state_store 		=> ['State.json',      		\&project_dir ],
		effect_profile 			=> ['effect_profiles',		\&project_root],
		chain_setup 			=> ['Setup.ecs',      		\&project_dir ],
		user_customization 		=> ['custom.pl',      		\&project_root],
		project_effect_chains 	=> ['project_effect_chains',\&project_dir ],
		project_config			=> ['project_config', 		\&project_dir ],
		global_effect_chains  	=> ['global_effect_chains', \&project_root],
		old_effect_chains  		=> ['effect_chains', 		\&project_root],
		_logfile				=> ['nama.log',				\&project_root],

	}, '::File';


	$gui->{_save_id} = "State";
	$gui->{_seek_unit} = 1;
	$gui->{marks} = {};

	$config = bless {
		root_dir 						=> join_path( $ENV{HOME}, "nama"),
		soundcard_channels 				=> 10,
		memoize 						=> 1,
		use_pager 						=> 1,
		use_placeholders 				=> 1,
		volume_control_operator 		=> 'ea', # default to linear scale
		sync_mixdown_and_monitor_version_numbers => 1, # not implemented yet
		engine_fade_length_on_start_stop => 0.3, # when starting/stopping transport
		engine_fade_default_length 		=> 0.5, # for fade-in, fade-out
		engine_base_jack_seek_delay 	=> 0.1, # seconds
		edit_playback_end_margin 		=> 3,
		edit_crossfade_time 			=> 0.03,
		fade_down_fraction 				=> 0.75,
		fade_time1_fraction 			=> 0.9,
		fade_time2_fraction 			=> 0.1,
		fader_op 						=> 'ea',
		mute_level 						=> {ea => 0, 	eadb => -96}, 
		fade_out_level 					=> {ea => 0, 	eadb => -40},
		unity_level 					=> {ea => 100, 	eadb => 0}, 
		fade_resolution 				=> 20, # steps per second
		no_fade_mute_delay				=> 0.03,
		# for save_system_state()
		serialize_formats               => 'json',
	}, '::Config';

	{ package ::Config;
	use Carp;
	use ::Globals qw($debug :singletons);
	use Modern::Perl;
	our @ISA = '::Object'; #  for ->dump and ->as_hash methods

	# special handling of serialize formats to store them as 
	# space separate tags, must duplicate AUTOLOAD checking

	sub serialize_formats { 
			split " ", 
			(
				$project->{config}->{serialize_formats} 
			  || $_[0]->{serialize_formats}
			)
	}
	sub hardware_latency {
		no warnings 'uninitialized';
		$config->{devices}->{$config->{alsa_capture_device}}{hardware_latency} || 0
	}
	}

	$prompt = "nama ('h' for help)> ";

	$this_bus = 'Main';
	jack_update(); # determine if jackd is running

	$setup->{_old_snapshot} = {};
	$setup->{_last_rec_tracks} = [];

	$mastering->{track_names} = [ qw(Eq Low Mid High Boost) ];

	$mode->{mastering} = 0;

	init_memoize() if $config->{memoize};

	# JACK environment for testing

	$jack->{fake_ports_list} = get_data_section("fake_jack_lsp");

}

sub initialize_interfaces {
	
	$debug2 and print "&prepare\n";

	say
[% qx(cat ./banner.pl) %]

	if ($config->{opts}->{D}){
		$debug = 1;
		$debug2 = 1;
	}
	if ( ! $config->{opts}->{t} and ::Graphical::initialize_tk() ){ 
		$ui = ::Graphical->new();
	} else {
		say "Unable to load perl Tk module. Starting in console mode." if $config->{opts}->{g};
		$ui = ::Text->new();
		can_load( modules =>{ Event => undef})
			or die "Perl Module 'Event' not found. Please install it and try again. Stopping.";
;
		import Event qw(loop unloop unloop_all);
	}
	
	can_load( modules => {AnyEvent => undef})
			or die "Perl Module 'AnyEvent' not found. Please install it and try again. Stopping.";

	choose_sleep_routine();

	$project->{name} = shift @ARGV;
	$debug and print "project name: $project->{name}\n";

	$debug and print("$config->{opts}\n======\n", yaml_out($config->{opts})); ; 


	read_config(global_config());  # from .namarc if we have one
	
	initialize_logger();

	$debug and say "#### Config file ####";
	#$debug and say yaml_out($config); XX config is object now; needs a dump method
	
	setup_user_customization();	

	start_ecasound();

	$debug and print "reading config file\n";
	if ($config->{opts}->{d}){
		print "project_root $config->{opts}->{d} specified on command line\n";
		$config->{root_dir} = $config->{opts}->{d};
	}
	if ($config->{opts}->{p}){
		$config->{root_dir} = getcwd();
		print "placing all files in current working directory ($config->{root_dir})\n";
	}

	# set soundcard sample frequency from .namarc
	($config->{sample_rate}) = $config->{devices}->{jack}{signal_format} =~ /(\d+)(,i)?$/;

	# skip initializations if user (test) supplies project
	# directory
	
	first_run() unless $config->{opts}->{d}; 

	prepare_static_effects_data() unless $config->{opts}->{S};

	get_ecasound_iam_keywords();
	load_keywords(); # for autocompletion

	chdir $config->{root_dir} # for filename autocompletion
		or warn "$config->{root_dir}: chdir failed: $!\n";

	$ui->init_gui;
	$ui->transport_gui;
	$ui->time_gui;

	
	# fake JACK for testing environment

	if( $config->{opts}->{J}){
		%{$jack->{clients}} = %{ jack_ports($jack->{fake_ports_list}) };
		$jack->{jackd_running} = 1;
	}

	# periodically check if JACK is running, and get client/port list

	poll_jack() unless $config->{opts}->{J} or $config->{opts}->{A};

	sleeper(0.2); # allow time for first polling

	# we will start jack.plumbing only when we need it
	
	if(		$config->{use_jack_plumbing} 
	and $jack->{jackd_running} 
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
		
	start_midish() if $config->{use_midish};

	initialize_terminal() unless $config->{opts}->{T};

	# set default project to "untitled"
	
	#convert_project_format(); # mark with .conversion_completed file in ~/nama
	
	if (! $project->{name} ){
		$project->{name} = "untitled";
		$config->{opts}->{c}++; 
	}
	print "\nproject_name: $project->{name}\n";
	
	load_project( name => $project->{name}, create => $config->{opts}->{c}) ;
	restore_effect_chains();
	1;	
}
sub debugging_options {
	grep{$_} $debug, @{$config->{opts}}{qw(R D J A E T)};
}
sub start_ecasound {
 	my @existing_pids = split " ", qx(pgrep ecasound);
	select_ecasound_interface();
	sleeper(0.2);
	@{$engine->{pids}} = grep{ 	my $pid = $_; 
							! grep{ $pid == $_ } @existing_pids
						 }	split " ", qx(pgrep ecasound);
}
sub select_ecasound_interface {
	return if $config->{opts}->{E} or $config->{opts}->{A};
	if ( can_load( modules => { 'Audio::Ecasound' => undef } )
			and ! $config->{opts}->{n} ){ 
		say "\nUsing Ecasound via Audio::Ecasound (libecasoundc).";
		{ no warnings qw(redefine);
		*eval_iam = \&eval_iam_libecasoundc; }
		$engine->{ecasound} = Audio::Ecasound->new();
	} else { 

		no warnings qw(redefine);
		launch_ecasound_server($config->{engine_tcp_port});
		init_ecasound_socket($config->{engine_tcp_port}); 
		*eval_iam = \&eval_iam_neteci;
	}
}
	


sub choose_sleep_routine {
	if ( can_load(modules => {'Time::HiRes'=> undef} ) ) 
		 { *sleeper = *finesleep;
			$config->{hires_timer}++; }
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
	$engine->{socket} = new IO::Socket::INET (
		PeerAddr => 'localhost', 
		PeerPort => $port, 
		Proto => 'tcp', 
	); 
	die "Could not create socket: $!\n" unless $engine->{socket}; 
}

sub ecasound_pid {
	my ($ps) = grep{ /ecasound/ and /server/ } qx(ps ax);
	my ($pid) = split " ", $ps; 
	$pid if $engine->{socket}; # conditional on using socket i.e. Net-ECI
}

sub initialize_logger {

	my $layout = "[\%R] %m%n"; # backslash to protect from source filter
	my $logfile = $ENV{NAMA_ECI} || "$ENV{HOME}/nama.eci.log";
	my $conf = qq(
		#log4perl.rootLogger			= DEBUG, IAM
		#log4perl.category.ECI			= DEBUG, IAM, IAM_file
		log4perl.appender.IAM			= Log::Log4perl::Appender::Screen
		log4perl.appender.IAM_file		= Log::Log4perl::Appender::File
		log4perl.appender.IAM_file.filename	= $logfile
		log4perl.appender.IAM_file.layout	= Log::Log4perl::Layout::PatternLayout
		log4perl.appender.IAM_file.layout.ConversionPattern = $layout
		log4perl.appender.IAM.layout	= Log::Log4perl::Layout::PatternLayout
		log4perl.appender.IAM.layout.ConversionPattern = $layout
		#log4perl.additivity.IAM			= 0 # doesn't work... why?
	);
	Log::Log4perl::init(\$conf);

}

sub eval_iam { } # stub

sub eval_iam_neteci {
	my ($cmd) = @_;
	my $logger = get_logger('ECI');
	$logger->debug($cmd);
	$cmd =~ s/\s*$//s; # remove trailing white space
	$engine->{socket}->send("$cmd\r\n");
	my $buf;
	# get socket reply, restart ecasound on error
	my $result = $engine->{socket}->recv($buf, 65536);
	defined $result or restart_ecasound(), return;

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
	my $debug++;
	$debug and say "ECI command: $cmd";
	$debug and say "Ecasound reply (256 bytes): ", substr($buf,0,256);
	$debug and say qq(
length: $setup_length
type: $type
full return value: $return_value);
	say "illegal return value from ecasound engine: $return_value" ;
	restart_ecasound();

}
	$reply =~ s/\s+$//; 

	given($type){
		when ('e'){ carp $reply;
			restart_ecasound() if $reply =~ /in engine-status/;

}
		default{ return $reply }
	}

}

sub eval_iam_libecasoundc{
	#$debug2 and print "&eval_iam\n";
	my ($cmd) = @_;
	my $logger = get_logger('ECI');
	$logger->debug($cmd);
	$debug and print "iam command: $cmd\n";
	my (@result) = $engine->{ecasound}->eci($cmd);
	$debug and print "result: @result\n" unless $cmd =~ /register/;
	my $errmsg = $engine->{ecasound}->errmsg();
	if( $errmsg ){
		restart_ecasound() if $errmsg =~ /in engine-status/;
		$engine->{ecasound}->errmsg(''); 
		# ecasound already prints error on STDOUT
		# carp "ecasound reports an error:\n$errmsg\n"; 
	}
	"@result";
}
}
	
sub restart_ecasound {
	say "killing ecasound processes @{$engine->{pids}}";
	kill_my_ecasound_processes();
	say "restarting Ecasound engine - your may need to use the 'arm' command";
	select_ecasound_interface();
	#$setup->{changed}++;
	reconfigure_engine();
}
sub kill_my_ecasound_processes {
	my @signals = (15, 9);
	map{ kill $_, @{$engine->{pids}}; sleeper(1)} @signals;
}
sub log_msg {
	my $log = shift;
	if ( $log )
	{
		my $category 	= $log->{category};
		my $level		= $log->{level};	
		my $msg			= $log->{msg};
		my $cmd			= $log->{cmd};
		my $result		= $log->{result}; 
		my $logger = Log::Log4perl->get_logger($category);
		my @msg;
		push @msg, "command: $cmd" if $cmd;
		push @msg, "message: $msg" if $msg;
		push @msg, "result: $result" if $result;
		my $message = join q(, ), @msg;
		$logger->$level($message);
	}
}

1;
__END__
