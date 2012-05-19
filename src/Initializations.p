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
		enforce_channel_bounds			=> 1,
		# for save_system_state()
		serialize_formats               => 'json',
	}, '::Config';

	{ package ::Config;
	use Carp;
	use ::Globals qw(:singletons);
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
	
	$setup->{_old_snapshot} = {};
	$setup->{_last_rec_tracks} = [];

	$mastering->{track_names} = [ qw(Eq Low Mid High Boost) ];

	$mode->{mastering} = 0;

	init_memoize() if $config->{memoize};

}

sub initialize_interfaces {
	
	logsub("&prepare");

	say
[% qx(cat ./banner.pl) %]

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
	can_load( modules => {jacks => undef})
		and $jack->{use_jacks}++;

	choose_sleep_routine();
	$config->{want_logging} = initialize_logger($config->{opts}->{L});

	$project->{name} = shift @ARGV;
	{no warnings 'uninitialized';
	logit('::Config','debug',"project name: $project->{name}");
	}

	logit('::Config','debug',
		sub{"Command line options\n".  yaml_out($config->{opts})});

	read_config(global_config());  # from .namarc if we have one
	
	logit('::Config','debug',sub{"Config data\n".Dumper $config});
	

	start_ecasound();

	logit('::Config','debug',"reading config file");
	if ($config->{opts}->{d}){
		print "project_root $config->{opts}->{d} specified on command line\n";
		$config->{root_dir} = $config->{opts}->{d};
	}
	if ($config->{opts}->{p}){
		$config->{root_dir} = getcwd();
		print "placing all files in current working directory ($config->{root_dir})\n";
	}

	# skip initializations if user (test) supplies project
	# directory
	
	first_run() unless $config->{opts}->{d}; 

	prepare_static_effects_data() unless $config->{opts}->{S};
	setup_user_customization();	# depends on effect_index() in above

	get_ecasound_iam_keywords();
	load_keywords(); # for autocompletion

	chdir $config->{root_dir} # for filename autocompletion
		or warn "$config->{root_dir}: chdir failed: $!\n";

	$ui->init_gui;
	$ui->transport_gui;
	$ui->time_gui;

	
	# fake JACK for testing environment

	if( $config->{opts}->{J}){
		parse_ports_list(get_data_section("fake_jack_lsp"));
		parse_port_latency(get_data_section("fake_jack_latency"));
		$jack->{jackd_running} = 1;
	}

	# periodically check if JACK is running, and get client/port/latency list

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
sub start_ecasound {
 	my @existing_pids = split " ", qx(pgrep ecasound);
	select_ecasound_interface();
	sleeper(0.2);
	@{$engine->{pids}} = grep{ 	my $pid = $_; 
							! grep{ $pid == $_ } @existing_pids
						 }	split " ", qx(pgrep ecasound);
}
sub select_ecasound_interface {
	logit('::Engine','info','Not initializing engine: options E or A are set.'),
			return if $config->{opts}->{E} or $config->{opts}->{A};

	# Net-ECI if requested by option, or as fallback 
	
	start_ecasound_net_eci(), return if $config->{opts}->{n}
		or !  can_load( modules => { 'Audio::Ecasound' => undef });

	start_ecasound_libecasoundc();
}

sub start_ecasound_libecasoundc {
	logit('::Engine','info',"Using Ecasound via Audio::Ecasound (libecasoundc)");
	no warnings qw(redefine);
	*eval_iam = \&eval_iam_libecasoundc;
	$engine->{ecasound} = Audio::Ecasound->new();
}
	
sub start_ecasound_net_eci {
	logit('::Engine','info',"Using Ecasound via Net-ECI"); 
	no warnings qw(redefine);
	launch_ecasound_server($config->{engine_tcp_port});
	init_ecasound_socket($config->{engine_tcp_port}); 
	*eval_iam = \&eval_iam_neteci;
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


sub eval_iam { } # stub

sub eval_iam_neteci {
	my $cmd = shift;
	my $category = munge_category(shift());

	logit($category, 'debug', "Net-ECI sent: $cmd");

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
	logit($category,'error',"Net-ECI bad return value: $return_value (expected 256)");
	restart_ecasound();

}
	$reply =~ s/\s+$//; 

	if( $type eq 'e')
	{
		logit($category,'error',"ECI error! Command: $cmd. Reply: $reply");
		#restart_ecasound() if $reply =~ /in engine-status/;
	}
	else
	{ 	logit($category,'debug',"Net-ECI  got: $reply");
		$reply
	}
	
}

sub eval_iam_libecasoundc {
	#logsub("&eval_iam");
	my $cmd = shift;
	my $category = munge_category(shift());
	
	logit($category,'debug',"ECI sent: $cmd");

	my (@result) = $engine->{ecasound}->eci($cmd);
	logit($category, 'debug',"ECI  got: @result") 
		if $result[0] and not $cmd =~ /register/ and not $cmd =~ /int-cmd-list/; 
	my $errmsg = $engine->{ecasound}->errmsg();
	if( $errmsg ){
		restart_ecasound() if $errmsg =~ /in engine-status/;
		$engine->{ecasound}->errmsg(''); 
		# Audio::Ecasound already prints error
	}
	"@result";
}
sub munge_category {
	
	my $cat = shift;
	
	# override undefined category by magical global setting
	# default to 'ECI_OTHER'
	
	$cat  ||= ($config->{category} || 'ECI_OTHER');

	# force all categories to 'ECI' if 'ECI' is selected for logging
	# (exception: ECI_WAVINFO, which is too noisy)
	
	no warnings 'uninitialized';
	return 'ECI' if $config->{want_logging}->{ECI} and not $cat eq 'ECI_WAVINFO';

	$cat
}

}
sub start_logging { 
	$config->{want_logging} = initialize_logger($config->{opts}->{L})
}

1;
__END__
