sub main { 
#	setup_grammar(); # executes directly in body
	process_options();
	prepare(); 
	command_process($execute_on_project_load);
	reconfigure_engine();
	command_process($opts{X});
	$ui->loop;
}
sub prepare {
	
	$debug2 and print "&prepare\n";
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

	prepare_static_effects_data() unless $opts{e};

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
sub issue_first_prompt {
	$term->stuff_char(10); # necessary to respond to Ctrl-C at first prompt 
	&{$attribs->{'callback_read_char'}}();
	set_current_bus();
	print prompt();
	$attribs->{already_prompted} = 0;
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


sub initialize_terminal {
	$term = new Term::ReadLine("Ecasound/Nama");
	$attribs = $term->Attribs;
	$attribs->{attempted_completion_function} = \&complete;
	$attribs->{already_prompted} = 1;
	detect_spacebar(); # if $press_space_to_start_transport;

	revise_prompt();
	# handle Control-C from terminal

	$SIG{INT} = \&cleanup_exit;
	$SIG{USR1} = sub { save_state() };
	#$event_id{sigint} = AE::signal('INT', \&cleanup_exit);

}
{my $override;
sub revise_prompt {
	# hack to allow suppressing prompt
	$override = $_[0] eq "default" ? undef : $_[0] if defined $_[0];
    $term->callback_handler_install($override//prompt(), \&process_line);
}
}
sub prompt {
	"nama [". ($this_bus eq 'Main' ? '': "$this_bus/").  
		($this_track ? $this_track->name : '') . "] ('h' for help)> "
}
sub check_for_spacebar_hit {
	$event_id{stdin} = AE::io(*STDIN, 0, sub {
		&{$attribs->{'callback_read_char'}}();
		if ( $attribs->{line_buffer} eq " " ){

			toggle_transport();	
			$attribs->{line_buffer} = q();
			$attribs->{point} 		= 0;
			$attribs->{end}   		= 0;
			$term->stuff_char(10);
			&{$attribs->{'callback_read_char'}}();
		}
	});
}
sub detect_spacebar {
	$event_id{stdin} = undef; # clean up after get_edit_mark()
	check_for_spacebar_hit() if $press_space_to_start_transport;
}

sub toggle_transport {
	if (engine_running()){ stop_transport() } 
	else { start_transport() }
}
	
sub first_run {
	return if $opts{f};
	my $config = config_file();
	$config = "$ENV{HOME}/$config" unless -e $config;
	$debug and print "config: $config\n";
	if ( ! -e $config and ! -l $config  ) {

	# check for missing components

	my $missing;
	my @a = `which analyseplugin`;
	@a or print( <<WARN
LADSPA helper program 'analyseplugin' not found
in $ENV{PATH}, your shell's list of executable 
directories. You will probably have more fun with the LADSPA
libraries and executables installed. http://ladspa.org
WARN
	) and  sleeper (0.6) and $missing++;
	my @b = `which ecasound`;
	@b or print( <<WARN
Ecasound executable program 'ecasound' not found
in $ENV{PATH}, your shell's list of executable 
directories. This suite depends on the Ecasound
libraries and executables for all audio processing! 
WARN
	) and sleeper (0.6) and $missing++;
	if ( $missing ) {
	print "You lack $missing main parts of this suite.  
Do you want to continue? [N] ";
	$missing and 
	my $reply = <STDIN>;
	chomp $reply;
	print("Goodbye.\n"), exit unless $reply =~ /y/i;
	}
print <<HELLO;

Aloha. Welcome to Nama and Ecasound.

HELLO
	sleeper (0.6);
	print "Configuration file $config not found.

May I create it for you? [yes] ";
	my $make_namarc = <STDIN>;
	sleep 1;
	print <<PROJECT_ROOT;

Nama places all sound and control files under the
project root directory, by default $ENV{HOME}/nama.

PROJECT_ROOT
	print "Would you like to create $ENV{HOME}/nama? [yes] ";
	my $reply = <STDIN>;
	chomp $reply;
	if ($reply !~ /n/i){
		# write project root path into default namarc
		$default =~ s/^project_root.*$/project_root: $ENV{HOME}\/nama/m;
		
		# create path nama/untitled/.wav
		#
		# this creates directories for 
		#   - project root
		#   - project name 'untitled', the default project, and
		#   - project untitled's hidden directory for holding WAV files
		
		mkpath( join_path($ENV{HOME}, qw(nama untitled .wav)) );

		$custom_pl > io( user_customization_file() );
		
	} else {
		print <<OTHER;
Please make sure to set the project_root directory in
.namarc, or on the command line using the -d option.

OTHER
	}
	if ($make_namarc !~ /n/i){
		$default > io( $config );
	}
	sleep 1;
	print "\n.... Done!\n\nPlease edit $config and restart Nama.\n\n";
	print "Exiting.\n"; 
	exit;	
	}
}

sub process_options {

	my %options = qw(

        save-alsa  		a
		project-root=s  d
		use-pwd			p
		create-project  c
		config=s		f
		gui			  	g
		text			t
		no-state		m
		net-eci			n
		libecasoundc	l
		help			h
		regenerate-effects-cache	r
		no-static-effects-data		s
		no-static-effects-cache		e
		no-reconfigure-engine		R
		fake-jack					J
		fake-alsa					A
		fake-ecasound				E
		debugging-output			D
		execute-command=s			X
		no-terminal					T
        no-fade-on-transport-start  F
);

	map{$opts{$_} = ''} values %options;

	# long options

	Getopt::Long::Configure ("bundling");	
	my $getopts = 'GetOptions( ';
	map{ $getopts .= qq("$options{$_}|$_" => \\\$opts{$options{$_}}, \n)} keys %options;
	$getopts .= ' )' ;

	#say $getopts;

	eval $getopts or die "Stopped.\n";
	
	if ($opts{h}){
	say <<HELP; exit; }

USAGE: nama [options] [project_name]

--gui, -g                        Start Nama in GUI mode
--text, -t                       Start Nama in text mode
--config, -f                     Specify configuration file (default: ~/.namarc)
--project-root, -d               Specify project root directory
--use-pwd, -p                    Use current dir for all WAV and project files
--create-project, -c             Create project if it doesn't exist
--net-eci, -n                    Use Ecasound's Net-ECI interface
--libecasoundc, -l               Use Ecasound's libecasoundc interface
--save-alsa, -a                  Save/restore alsa state with project data
--help, -h                       This help display

Debugging options:

--no-static-effects-data, -s     Don't load effects data
--no-state, -m                   Don't load project state
--no-static-effects-cache, -e    Bypass effects data cache
--regenerate-effects-cache, -r   Regenerate the effects data cache
--no-reconfigure-engine, -R      Don't automatically configure engine
--debugging-output, -D           Emit debugging information
--fake-jack, -J                  Simulate JACK environment
--fake-alsa, -A                  Simulate ALSA environment
--no-ecasound, -E                Don't spawn Ecasound process
--execute-command, -X            Supply a command to execute
--no-terminal, -T                Don't initialize terminal
--no-fades, -F                   No fades on transport start/stop

HELP

#--no-ecasound, -E                Don't load Ecasound (for testing)

	say $banner;

	if ($opts{D}){
		$debug = 1;
		$debug2 = 1;
	}
	if ( ! $opts{t} and can_load( modules => { Tk => undef } ) ){ 
		$ui = ::Graphical->new;
	} else {
		say "Unable to load perl Tk module. Starting in console mode." if $opts{g};
		$ui = ::Text->new;
		can_load( modules =>{ Event => undef})
			or die "Perl Module 'Event' not found. Please install it and try again. Stopping.";
;
		import Event qw(loop unloop unloop_all);
	}
	
	can_load( modules => {AnyEvent => undef})
			or die "Perl Module 'AnyEvent' not found. Please install it and try again. Stopping.";

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
	say ("Using existing Ecasound server"), return 
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
sub setup_user_customization {
	my $file = user_customization_file();
	return unless -r $file;
	say "reading user customization file $user_customization_file";
	my @return;
	unless (@return = do $file) {
		say "couldn't parse $file: $@\n" if $@;
		return;
	}
	# convert key-value pairs to hash
	$debug and print join "\n",@return;
	my %custom = @return ; 
	my $prompt;
	$prompt = gen_coderef('prompt', $custom{prompt}) if $custom{prompt};
	{ no warnings 'redefine';
		*prompt = $prompt if $prompt;
	}
	my @commands = keys %{ $custom{commands} };
	for my $cmd(@commands){
		my $coderef = gen_coderef($cmd,$custom{commands}{$cmd}) or next;
		$user_command{$cmd} = $coderef;
	}
	%user_alias   = %{ $custom{aliases}  };
}
sub user_customization_file { join_path(project_root(),$user_customization_file) }

sub do_user_command {
	#say "args: @_";
	my($cmd, @args) = @_;
	$user_command{$cmd}->(@args);
}	
sub gen_coderef {
	my ($cmd,$code) = @_;
	my $coderef = eval "sub{ use feature ':5.10'; $code }";
	say("couldn't parse command $cmd: $@"), return if $@;
	$coderef
}

## project handling

sub list_projects {
	my $projects = join "\n", sort map{
			my ($vol, $dir, $lastdir) = File::Spec->splitpath($_); $lastdir
		} File::Find::Rule  ->directory()
							->maxdepth(1)
							->extras( { follow => 1} )
						 	->in( project_root());
	pager($projects);
}
sub list_plugins {}
		
sub load_project {
	$debug2 and print "&load_project\n";
	my %h = @_;
	$debug and print yaml_out \%h;
	print("no project name.. doing nothing.\n"),return 
		unless $h{name} or $project;
	$project_name = $h{name} if $h{name};

	if ( ! -d join_path( project_root(), $project_name) ){
		if ( $h{create} ){
			map{create_dir($_)} &project_dir, &this_wav_dir ;
		} else { 
			print qq(
Project "$project_name" does not exist. 
Loading project "untitled".
);
			load_project( qw{name untitled create 1} );
			return;
		}
	} 
	# we used to check each project dir for customized .namarc
	# read_config( global_config() ); 
	
	teardown_engine(); # initialize_ecasound_engine; 
	initialize_project_data();
	remove_riff_header_stubs(); 
	cache_wav_info();
	rememoize();

	restore_state( $h{settings} ? $h{settings} : $state_store_file) unless $opts{m} ;
	if (! $tn{Master}){

		::SimpleTrack->new( 
			group => 'Master', 
			name => 'Master',
			send_type => 'soundcard',
			send_id => 1,
			width => 2,
			rw => 'MON',
			source_type => undef,
			source_id => undef); 

		my $mixdown = ::MixDownTrack->new( 
			group => 'Mixdown', 
			name => 'Mixdown', 
			width => 2,
			rw => 'OFF',
			source_type => undef,
			source_id => undef); 

		#remove_effect($mixdown->vol);
		#remove_effect($mixdown->pan);
	}


	$opts{m} = 0; # enable 
	
	dig_ruins() unless scalar @::Track::all > 2;

	# possible null if Text mode
	
	$ui->global_version_buttons(); 
	$ui->refresh_group;

	$debug and print "project_root: ", project_root(), $/;
	$debug and print "this_wav_dir: ", this_wav_dir(), $/;
	$debug and print "project_dir: ", project_dir() , $/;

 1;
}	
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

sub process_is_running {
	my $name = shift;
	my @pids = split " ", qx(pgrep $name);
	my @ps_ax  = grep{   my $pid;
						/$name/ and ! /defunct/
						and ($pid) = /(\d+)/
						and grep{ $pid == $_ } @pids 
				} split "\n", qx(ps ax) ;
}
sub valid_engine_setup {
	eval_iam("cs-selected") and eval_iam("cs-is-valid");
}
sub engine_running {
	eval_iam("engine-status") eq "running"
};

sub initialize_project_data {
	$debug2 and print "&initialize_project_data\n";

	return if transport_running();
	$ui->destroy_widgets();
	$ui->project_label_configure(
		-text => uc $project_name, 
		-background => 'lightyellow',
		); 

	# effect variables - no object code (yet)
	
	$cop_id = "A"; # autoincrement counter
	%cops	= ();  # effect and controller objects (hashes)
	%copp   = ();  # chain operator parameters
	               # indexed by {$id}->[$param_no]
	               # zero-based {AB}->[0] (parameter 1)

	%old_vol = (); 

	@input_chains = ();
	@output_chains = ();

	%track_widget = ();
	%effects_widget = ();

	$markers_armed = 0;

	map{ $_->initialize() } qw(
							::Mark
							::Fade
							::Edit
							::Bus
							::Track
							::Insert
							);
	
	# volume settings
	
	%old_vol = ();
	@already_muted = ();

	# $is_armed = 0;
	
	$old_snapshot = {};
	$preview = $initial_user_mode;
	$mastering_mode = 0;
	$saved_version = 0; 
	
	%bunch = ();	
	
	create_system_buses();
	$this_bus = 'Main';

	%inputs = %outputs = ();
	
	%wav_info = ();
	
	clear_offset_run_vars();
	$offset_run_flag = 0;
	$this_edit = undef;

}
sub create_system_buses {
	$debug2 and say "&create_system_buses";

	my $buses = q(
			Master		# master fader track
			Mixdown		# mixdown track
			Mastering	# mastering network
			Insert		# auxiliary tracks for inserts
			Cooked		# for track caching
			Temp		# temp tracks while generating setup
			Main		# default mixer bus, new tracks assigned to Main
	);
	($buses) = strip_comments($buses); # need initial parentheses
	@system_buses = split " ", $buses;
	map{ $is_system_bus{$_}++ } @system_buses;
	delete $is_system_bus{Main}; # because we want to display it
	map{ ::Bus->new(name => $_ ) } @system_buses;
	
	# a bus should identify it's mix track
	$bn{Main}->set( send_type => 'track', send_id => 'Master');

	$main = $bn{Main};
	$null = $bn{null};
}

## track and wav file handling

# create read-only track pointing at WAV files of specified
# track name in a different project

sub add_track_alias_project {
	my ($name, $track, $project) = @_;
	my $dir =  join_path(project_root(), $project, '.wav'); 
	if ( -d $dir ){
		if ( glob "$dir/$track*.wav"){
			print "Found target WAV files.\n";
			my @params = (target => $track, project => $project);
			add_track( $name, @params );
		} else { print "No WAV files found.  Skipping.\n"; return; }
	} else { 
		print("$project: project does not exist.  Skipping.\n");
		return;
	}
}

sub discard_object {
	shift @_ if (ref $_[0]) =~ /Nama/;
	@_;
}

# usual track

sub add_track {

	@_ = discard_object(@_);
	$debug2 and print "&add_track\n";
	#return if transport_running();
	my ($name, @params) = @_;
	my %vals = (name => $name, @params);
	my $class = $vals{class} // '::Track';
	
	$debug and print "name: $name, ch_r: $ch_r, ch_m: $ch_m\n";
	
	say ("$name: track name already in use. Skipping."), return 
		if $::Track::by_name{$name};
	say ("$name: reserved track name. Skipping"), return
	 	if grep $name eq $_, @mastering_track_names; 

	my $track = $class->new(%vals);
	return if ! $track; 
	$this_track = $track;
	$debug and print "ref new track: ", ref $track; 
	$track->source($ch_r) if $ch_r;
#		$track->send($ch_m) if $ch_m;

	my $group = $bn{$track->group}; 
	command_process('for mon; mon') if $preview and $group->rw eq 'MON';
	$group->set(rw => 'REC') unless $track->target; # not if is alias

	# normal tracks default to 'REC'
	# track aliases default to 'MON'
	$track->set(rw => $track->target
					?  'MON'
					:  'REC') ;
	$track_name = $ch_m = $ch_r = undef;

	set_current_bus();
	$ui->track_gui($track->n);
	$debug and print "Added new track!\n", $track->dump;
	$track;
}

# create read-only track pointing at WAV files of specified
# name in current project

sub add_track_alias {
	my ($name, $track) = @_;
	my $target; 
	if 		( $tn{$track} ){ $target = $track }
	elsif	( $ti{$track} ){ $target = $ti{$track}->name }
	add_track(  $name, target => $target );
}
sub dig_ruins { # only if there are no tracks 
	
	$debug2 and print "&dig_ruins";
	return if ::Track::user();
	$debug and print "looking for WAV files\n";

	# look for wave files
		
	my $d = this_wav_dir();
	opendir my $wav, $d or carp "couldn't open $d: $!";

	# remove version numbers
	
	my @wavs = grep{s/(_\d+)?\.wav//i} readdir $wav;

	closedir $wav;

	my %wavs;
	
	map{ $wavs{$_}++ } @wavs;
	@wavs = keys %wavs;

	$debug and print "tracks found: @wavs\n";
 
	$ui->create_master_and_mix_tracks();

	map{add_track($_)}@wavs;

}

sub remove_riff_header_stubs {

	# 44 byte stubs left by a recording chainsetup that is 
	# connected by not started
	
	$debug2 and print "&remove_riff_header_stubs\n";
	

	$debug and print "this wav dir: ", this_wav_dir(), $/;
	return unless this_wav_dir();
         my @wavs = File::Find::Rule ->name( qr/\.wav$/i )
                                        ->file()
                                        ->size(44)
                                        ->extras( { follow => 1} )
                                     ->in( this_wav_dir() );
    $debug and print join $/, @wavs;

	map { unlink $_ } @wavs; 
}

sub add_volume_control {
	my $n = shift;
	return unless need_vol_pan($ti{$n}->name, "vol");
	
	my $vol_id = cop_add({
				chain => $n, 
				type => $volume_control_operator,
				cop_id => $ti{$n}->vol, # often undefined
				});
	
	$ti{$n}->set(vol => $vol_id);  # save the id for next time
	$vol_id;
}
sub add_pan_control {
	my $n = shift;
	return unless need_vol_pan($ti{$n}->name, "pan");

	my $pan_id = cop_add({
				chain => $n, 
				type => 'epp',
				cop_id => $ti{$n}->pan, # often undefined
				});
	
	$ti{$n}->set(pan => $pan_id);  # save the id for next time
	$pan_id;
}

# not used at present. we are probably going to offset the playat value if
# necessary

sub add_latency_compensation {
	print('LADSPA L/C/R Delay effect not found.
Unable to provide latency compensation.
'), return unless $effect_j{lcrDelay};
	my $n = shift;
	my $id = cop_add({
				chain => $n, 
				type => 'el:lcrDelay',
				cop_id => $ti{$n}->latency, # may be undef
				values => [ 0,0,0,50,0,0,0,0,0,50,1 ],
				# We will be adjusting the 
				# the third parameter, center delay (index  2)
				});
	
	$ti{$n}->set(latency => $id);  # save the id for next time
	$id;
}

## chain setup generation

# return file output entries, including Mixdown 
sub really_recording { 
	map{ /-o:(.+?\.wav)$/} grep{ /-o:/ and /\.wav$/} split "\n", $chain_setup
}

sub mixing_only {
	my $i;
	my $am_mixing;
	for (really_recording()){
		$i++;
		$am_mixing++ if /Mixdown/;
	}
	$i == 1 and $am_mixing
}
	
sub generate_setup { 
	# return 1 if successful
	# catch errors from generate_setup_try() and cleanup
	$debug2 and print "&generate_setup\n";
	# save current track
	$old_this_track = $this_track;

	# prevent engine from starting an old setup
	
	eval_iam('cs-disconnect') if eval_iam('cs-connected');

	::ChainSetup::initialize();
	local $@; # don't propagate errors
		# NOTE: it would be better to use try/catch
	track_memoize(); 			# freeze track state 

	# generate_setup_try() gets the @_ passed to generate_setup()
	my $success = eval { &::ChainSetup::generate_setup_try }; 
	remove_temporary_tracks();  # cleanup
	track_unmemoize(); 			# unfreeze track state
	$this_track = $old_this_track;
	if ($@){
		say("error caught while generating setup: $@");
		::ChainSetup::initialize() unless $debug;
		return
	}
	$success
}
sub remove_temporary_tracks {
	$debug2 and say "&remove_temporary_tracks";
	map { $_->remove  } grep{ $_->group eq 'Temp'} ::Track::all();
	$this_track = $old_this_track;
}

## transport functions
sub load_ecs {
	my $setup = setup_file();
	#say "setup file: $setup " . ( -e $setup ? "exists" : "");
	return unless -e $setup;
	#say "passed conditional";
	teardown_engine();
	eval_iam("cs-load $setup");
	eval_iam("cs-select $setup"); # needed by Audio::Ecasound, but not Net-ECI !!
	$debug and map{eval_iam($_)} qw(cs es fs st ctrl-status);
	1;
}
sub teardown_engine {
	eval_iam("cs-disconnect") if eval_iam("cs-connected");
	eval_iam("cs-remove") if eval_iam("cs-selected");
}

sub arm {

	# now that we have reconfigure_engine(), use is limited to 
	# - exiting preview
	# - automix	
	
	$debug2 and print "&arm\n";
	exit_preview_mode();
	#adjust_latency();
	$regenerate_setup++;
	generate_setup() and connect_transport();
}
sub set_preview_mode {

	# set preview mode, releasing doodle mode if necessary
	
	$debug2 and print "&preview\n";

	# do nothing if already in 'preview' mode
	
	if ( $preview eq 'preview' ){ return }

	# make an announcement if we were in rec-enabled mode

	$main->set(rw => $old_group_rw) if $old_group_rw;

	$preview = "preview";

	print "Setting preview mode.\n";
	print "Using both REC and MON inputs.\n";
	print "WAV recording is DISABLED.\n\n";
	print "Type 'arm' to enable recording.\n\n";
	# reconfigure_engine() will generate setup and start transport
}
sub set_doodle_mode {

	$debug2 and print "&doodle\n";
	return if engine_running() and really_recording();
	$preview = "doodle";

	# save rw setting of user tracks (not including null group)
	# and set those tracks to REC
	
	$old_group_rw = $main->rw;
	$main->set(rw => 'REC');
	$tn{Mixdown}->set(rw => 'OFF');
	
	# reconfigure_engine will generate setup and start transport
	
	print "Setting doodle mode.\n";
	print "Using live inputs only, with no duplicate inputs\n";
	print "Exit using 'preview' or 'arm' commands.\n";
}
{ my $old_offset_run_status;
sub reconfigure_engine {
	$debug2 and print "&reconfigure_engine\n";

	# skip if command line option is set
	return if $opts{R};

	return if $disable_auto_reconfigure;

	# don't disturb recording/mixing
	return if really_recording() and engine_running();

	rememoize(); # check if someone has snuck in some files
	
	find_duplicate_inputs(); # we will warn the user later

	# only act if change in configuration

	# skip check if regenerate_setup flag is already set
	if( $regenerate_setup ){ 
		$regenerate_setup = 0; # reset for next time
	} 
	else {
		my $current = yaml_out(status_snapshot());
		my $old = yaml_out($old_snapshot);
		if ( $current eq $old){
				$debug and print("no change in setup\n");
				return;
		}
	}
	$debug and print("setup change\n");

 	my $old_pos;
 	my $was_running;
	my $restore_position;
	my $previous_snapshot = $old_snapshot;

	# restore previous playback position unless 

	#  - doodle mode
	#  - change in global version (TODO)
	#  - change in project
	#  - new setup involves recording
	#  - change in edit mode
	
	if ( 	$preview eq 'doodle' 
		 or $old_snapshot->{project} ne $project_name
		 or $offset_run_flag != $old_offset_run_status
		# TODO: or change in global version
	){} # do nothing
	else
	{
		$old_pos = eval_iam('getpos') if eval_iam('cs-selected');
		$was_running = engine_running();
		$restore_position++;

# 		say "old_pos: $old_pos";
# 		say "was_running: $was_running";
# 		say "restore_position: $restore_position";

	}

	$old_snapshot = status_snapshot();
	$old_offset_run_status = $offset_run_flag;

	command_process('show_tracks');

	stop_transport('quiet') if $was_running;

	if ( generate_setup() ){
		
		#say "I generated a new setup";
		connect_transport('quiet');
		::Text::show_status();

		if( $restore_position and not really_recording()){
			eval_iam("setpos $old_pos") if $old_pos and $old_pos < $length;
 			start_transport('quiet') if $was_running;
		}
		transport_status();
		$ui->flash_ready;
	}
}
}
sub setup_file { join_path( project_dir(), $chain_setup_file) };

sub show_tracks_limited {

	# Master
	# Mixdown
	# Main bus
	# Current bus

}

		
sub exit_preview_mode { # exit preview and doodle modes

		$debug2 and print "&exit_preview_mode\n";
		return unless $preview;
		stop_transport() if engine_running();
		$debug and print "Exiting preview/doodle mode\n";
		$preview = 0;
		$main->set(rw => $old_group_rw) if $old_group_rw;

}

sub find_duplicate_inputs { # in Main bus only

	%duplicate_inputs = ();
	%already_used = ();
	$debug2 and print "&find_duplicate_inputs\n";
	map{	my $source = $_->source;
			$duplicate_inputs{$_->name}++ if $already_used{$source} ;
		 	$already_used{$source} //= $_->name;
	} 
	grep { $_->rw eq 'REC' }
	map{ $tn{$_} }
	$main->tracks(); # track names;
}


sub adjust_latency {

	$debug2 and print "&adjust_latency\n";
	map { $copp{$_->latency}[0] = 0  if $_->latency() } 
		::Track::all();
	set_preview_mode();
	exit_preview_mode();
	my $cop_status = eval_iam('cop-status');
	$debug and print $cop_status;
	my $chain_re  = qr/Chain "(\d+)":\s+(.*?)(?=Chain|$)/s;
	my $latency_re = qr/\[\d+\]\s+latency\s+([\d\.]+)/;
	my %chains = $cop_status =~ /$chain_re/sg;
	$debug and print yaml_out(\%chains);
	my %latency;
	map { my @latencies = $chains{$_} =~ /$latency_re/g;
			$debug and print "chain $_: latencies @latencies\n";
			my $chain = $_;
		  map{ $latency{$chain} += $_ } @latencies;
		 } grep { $_ > 2 } sort keys %chains;
	$debug and print yaml_out(\%latency);
	my $max;
	map { $max = $_ if $_ > $max  } values %latency;
	$debug and print "max: $max\n";
	map { my $adjustment = ($max - $latency{$_}) /
			$cfg{abbreviations}{frequency} * 1000;
			$debug and print "chain: $_, adjustment: $adjustment\n";
			effect_update_copp_set($ti{$_}->latency, 2, $adjustment);
			} keys %latency;
}

sub connect_transport {
	$debug2 and print "&connect_transport\n";
	my $quiet = shift;
	remove_riff_header_stubs();
	load_ecs() or say("No chain setup, engine not ready."), return;
	valid_engine_setup()
		or say("Invalid chain setup, engine not ready."),return;
	find_op_offsets(); 
	eval_iam('cs-connect');
		#or say("Failed to connect setup, engine not ready"),return;
	apply_ops();
	apply_fades();
	my $status = eval_iam("engine-status");
	if ($status ne 'not started'){
		print("Invalid chain setup, cannot connect engine.\n");
		return;
	}
	eval_iam('engine-launch');
	$status = eval_iam("engine-status");
	if ($status ne 'stopped'){
		print "Failed to launch engine. Engine status: $status\n";
		return;
	}
	$length = eval_iam('cs-get-length'); 
	$ui->length_display(-text => colonize($length));
	# eval_iam("cs-set-length $length") unless @record;
	$ui->clock_config(-text => colonize(0));
	sleeper(0.2); # time for ecasound engine to launch
	{ # set delay for seeking under JACK
	my $track_count; map{ $track_count++ } engine_tracks();
	$seek_delay = $jack_seek_delay || 0.1 + 0.1 * $track_count / 20;
	}
	connect_jack_ports_list();
	transport_status() unless $quiet;
	$ui->flash_ready();
	#print eval_iam("fs");
	1;
	
}
sub jack_plumbing_conf {
	join_path( $ENV{HOME} , '.jack.plumbing' )
}

{ 
  my $fh;
  my $plumbing_tag = q(BEGIN NAMA CONNECTIONS LIST);
  my $plumbing_header = qq(;### $plumbing_tag
;## The following lines are automatically generated.
;## DO NOT place any connection data below this line!!
;
); 
sub initialize_jack_plumbing_conf {  # remove nama lines

		return unless -f -r jack_plumbing_conf();

		# read in file
		my $user_plumbing = io(jack_plumbing_conf())->all;

		# keep user data, deleting below tag
		$user_plumbing =~ s/;[# ]*$plumbing_tag.*//gs;

		# write out file
		$user_plumbing > io(jack_plumbing_conf());
}

my $jack_plumbing_code = sub 
	{
		my ($port1, $port2) = @_;
		my $debug++;
		my $config_line = qq{(connect $port1 $port2)};
		say $fh $config_line; # $fh in lexical scope
		$debug and say $config_line;
	};
my $jack_connect_code = sub
	{
		my ($port1, $port2) = @_;
		my $debug++;
		my $cmd = qq(jack_connect $port1 $port2);
		$debug and say $cmd;
		system $cmd;
	};
sub connect_jack_ports_list {

	my @source_tracks = 
		grep{ 	$_->source_type eq 'jack_ports_list' and
	  	  		$_->rec_status  eq 'REC' 
			} engine_tracks();

	my @send_tracks = 
		grep{ $_->send_type eq 'jack_ports_list' } engine_tracks();

	# we need JACK
	return if ! $jack_running;

	# We need tracks to configure
	return if ! @source_tracks and ! @send_tracks;

	sleeper(0.3); # extra time for ecasound engine to register JACK ports

	if( $use_jack_plumbing )
	{

		# write config file
		initialize_jack_plumbing_conf();
		open $fh, ">>", jack_plumbing_conf();
		print $fh $plumbing_header;
		make_connections($jack_plumbing_code, \@source_tracks, 'in' );
		make_connections($jack_plumbing_code, \@send_tracks,   'out');
		close $fh; 

		# run jack.plumbing
		start_jack_plumbing();
		sleeper(3); # time for jack.plumbing to launch and poll
		kill_jack_plumbing();
		initialize_jack_plumbing_conf();
	}
	else 
	{
		make_connections($jack_connect_code, \@source_tracks, 'in' );
		make_connections($jack_connect_code, \@send_tracks,   'out');
	}
}
}
sub quote { $_[0] =~ /^"/ ? $_[0] : qq("$_[0]")}

sub make_connections {
	my ($code, $tracks, $direction) = @_;
	my $ports_list = $direction eq 'in' ? 'source_id' : 'send_id';
	map{  
		my $track = $_; 
 		my $name = $track->name;
 		my $ecasound_port = "ecasound:$name\_$direction\_";
		my $file = join_path(project_root(), $track->$ports_list);
		say($track->name, 
			": JACK ports file $file not found. No sources connected."), 
			return if ! -e -r $file;
		my $line_number = 0;
		my @lines = io($file)->slurp;
		for my $external_port (@lines){   
			# $external_port is the source port name
			chomp $external_port;
			$debug and say "port file $file, line $line_number, port $external_port";
			# setup shell command
			
			if(! $jack{$external_port}){
				say $track->name, qq(: port "$external_port" not found. Skipping.);
				next
			}
		
			# ecasound port index
			
			my $index = $track->width == 1
				?  1 
				: $line_number % $track->width + 1;

		my @ports = map{quote($_)} $external_port, $ecasound_port.$index;

			  $code->(
						$direction eq 'in'
							? @ports
							: reverse @ports
					);
			$line_number++;
		};
 	 } @$tracks
}
	

sub transport_status {
	
	map{ 
		say("Warning: $_: input ",$tn{$_}->source,
		" is already used by track ",$already_used{$tn{$_}->source},".")
		if $duplicate_inputs{$_};
	} grep { $tn{$_}->rec_status eq 'REC' } $main->tracks;


	# assume transport is stopped
	# print looping status, setup length, current position
	my $start  = ::Mark::loop_start();
	my $end    = ::Mark::loop_end();
	#print "start: $start, end: $end, loop_enable: $loop_enable\n";
	if (%cooked_record_pending){
		say join(" ", keys %cooked_record_pending), ": ready for caching";
	}
	if ($loop_enable and $start and $end){
		#if (! $end){  $end = $start; $start = 0}
		say "looping from ", heuristic_time($start),
				 	"to ",   heuristic_time($end);
	}
	say "\nNow at: ", current_position();
	say "Engine is ". ( engine_running() ? "running." : "ready.");
	say "\nPress SPACE to start or stop engine.\n"
		if $press_space_to_start_transport;
}

sub heuristic_time {
	my $sec = shift;
	d1($sec) .  ( $sec > 120 ? " (" . colonize( $sec ) . ") "  : " " )
}

sub start_transport { 

	my $quiet = shift;

	# set up looping event if needed
	# mute unless recording
	# start
	# wait 0.5s
	# unmute
	# start heartbeat
	# report engine status
	# sleep 1s

	$debug2 and print "&start_transport\n";
	say("\nCannot start. Engine is not configured.\n"),return 
		unless eval_iam("cs-connected");

	say "\n\nStarting at ", current_position() unless $quiet;
	schedule_wraparound();
	mute();
	eval_iam('start');
	limit_processing_time($run_time) 
		if mixing_only() or edit_mode() or defined $run_time;
		# TODO and live processing
 	#$event_id{post_start_unmute} = AE::timer(0.5, 0, sub{unmute()});
	sleeper(0.5);
	unmute();
	sleeper(0.5);
	$ui->set_engine_mode_color_display();
	start_heartbeat();
	engine_status() unless $quiet;
}
sub stop_transport { 

	my $quiet = shift;
	$debug2 and print "&stop_transport\n"; 
	mute();
	my $pos = eval_iam('getpos');
	eval_iam('stop');	
	disable_length_timer();
	if ( ! $quiet ){
		sleeper(0.5);
		engine_status(current_position(),2,0);
	}
	unmute();
	stop_heartbeat();
	$ui->project_label_configure(-background => $old_bg);
	eval_iam("setpos $pos");
}

sub transport_running { eval_iam('engine-status') eq 'running'  }

sub disconnect_transport {
	return if transport_running();
	teardown_engine();
}
sub engine_is {
	my $pos = shift;
	"Engine is ". eval_iam("engine-status"). ( $pos ? " at $pos" : "" )
}
sub engine_status { 
	my ($pos, $before_newlines, $after_newlines) = @_;
	say "\n" x $before_newlines, engine_is($pos), "\n" x $after_newlines;
}
sub current_position { colonize(int eval_iam("getpos")) }

sub start_heartbeat {
 	$event_id{poll_engine} = AE::timer(0, 1, \&::heartbeat);
}

sub stop_heartbeat {
	$event_id{poll_engine} = undef; 
	$ui->reset_engine_mode_color_display();
	rec_cleanup() }

sub heartbeat {

	#	print "heartbeat fired\n";

	my $here   = eval_iam("getpos");
	my $status = eval_iam('engine-status');
	if( $status =~ /finished|error/ ){
		engine_status(current_position(),2,1);
		revise_prompt();
		stop_heartbeat();
		sleeper(0.2);
		eval_iam('setpos 0');
	}
		#if $status =~ /finished|error|stopped/;
	#print join " ", $status, colonize($here), $/;
	my ($start, $end);
	$start  = ::Mark::loop_start();
	$end    = ::Mark::loop_end();
	schedule_wraparound() 
		if $loop_enable 
		and defined $start 
		and defined $end 
		and ! really_recording();

	update_clock_display();

}

sub update_clock_display { 
	$ui->clock_config(-text => current_position());
}
sub schedule_wraparound {

	return unless $loop_enable;
	my $here   = eval_iam("getpos");
	my $start  = ::Mark::loop_start();
	my $end    = ::Mark::loop_end();
	my $diff = $end - $here;
	$debug and print "here: $here, start: $start, end: $end, diff: $diff\n";
	if ( $diff < 0 ){ # go at once
		eval_iam("setpos ".$start);
		cancel_wraparound();
	} elsif ( $diff < 3 ) { #schedule the move
	$ui->wraparound($diff, $start);
		
		;
	}
}
sub cancel_wraparound {
	$event_id{wraparound} = undef;
}
sub limit_processing_time {
	my $length = shift // $length;
 	$event_id{processing_time} 
		= AE::timer($length, 0, sub { ::stop_transport(); print prompt() });
}
sub disable_length_timer {
	$event_id{processing_time} = undef; 
	undef $run_time;
}
sub wraparound {
	package ::;
	@_ = discard_object(@_);
	my ($diff, $start) = @_;
	#print "diff: $diff, start: $start\n";
	$event_id{wraparound} = undef;
	$event_id{wraparound} = AE::timer($diff,0, sub{set_position($start)});
}
sub schedule_autosave { 
	# one-time timer 
	my $seconds = (shift || $autosave_interval) * 60;
	$event_id{autosave} = undef; # cancel any existing timer
	return unless $seconds;
	$event_id{autosave} = AE::timer($seconds,0, \&autosave);
}
sub debugging_options {
	grep{$_} $debug, @opts{qw(R D J A E T)};
}
sub mute {
	return if $opts{F};
	return if $tn{Master}->rw eq 'OFF' or really_recording();
	$tn{Master}->mute;
}
sub unmute {
	return if $opts{F};
	return if $tn{Master}->rw eq 'OFF' or really_recording();
	$tn{Master}->unmute;
}

# for GUI transport controls

sub toggle_unit {
	if ($unit == 1){
		$unit = 60;
		
	} else{ $unit = 1; }
}
sub show_unit { $time_step->configure(
	-text => ($unit == 1 ? 'Sec' : 'Min') 
)}

# Mark routines

sub drop_mark {
	$debug2 and print "drop_mark()\n";
	my $name = shift;
	my $here = eval_iam("getpos");

	if( my $mark = $::Mark::by_name{$name}){
		say "$name: a mark with this name exists already at: ", 
			colonize($mark->time);
		return
	}
	if( my ($mark) = grep { $_->time == $here} ::Mark::all()){
		say q(This position is already marked by "),$mark->name,q(");
		 return 
	}

	my $mark = ::Mark->new( time => $here, 
							name => $name);

	$ui->marker($mark); # for GUI
}
sub mark { # GUI_CODE
	$debug2 and print "mark()\n";
	my $mark = shift;
	my $pos = $mark->time;
	if ($markers_armed){ 
			$ui->destroy_marker($pos);
			$mark->remove;
		    arm_mark_toggle(); # disarm
	}
	else{ 

		set_position($pos);
	}
}

sub next_mark {
	my $jumps = shift;
	$jumps and $jumps--;
	my $here = eval_iam("cs-get-position");
	my @marks = ::Mark::all();
	for my $i ( 0..$#marks ){
		if ($marks[$i]->time - $here > 0.001 ){
			$debug and print "here: $here, future time: ",
			$marks[$i]->time, $/;
			eval_iam("setpos " .  $marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
sub previous_mark {
	my $jumps = shift;
	$jumps and $jumps--;
	my $here = eval_iam("getpos");
	my @marks = ::Mark::all();
	for my $i ( reverse 0..$#marks ){
		if ($marks[$i]->time < $here ){
			eval_iam("setpos " .  $marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
	

## jump recording head position

sub to_start { 
	return if really_recording();
	set_position( 0 );
}
sub to_end { 
	# ten seconds shy of end
	return if really_recording();
	my $end = eval_iam('cs-get-length') - 10 ;  
	set_position( $end);
} 
sub jump {
	return if really_recording();
	my $delta = shift;
	$debug2 and print "&jump\n";
	my $here = eval_iam('getpos');
	$debug and print "delta: $delta\nhere: $here\nunit: $unit\n\n";
	my $new_pos = $here + $delta * $unit;
	$new_pos = $new_pos < $length ? $new_pos : $length - 10;
	set_position( $new_pos );
	sleeper( 0.6) if engine_running();
}
## post-recording functions
sub rec_cleanup {  
	$debug2 and print "&rec_cleanup\n";
	$debug && print("transport still running, can't cleanup"),return if transport_running();
	if( my (@files) = new_files_were_recorded() ){
		say join $/, "Now reviewing your recorded files...", (@files);
		(grep /Mixdown/, @files) 
			? command_process('mixplay') 
			: post_rec_configure();
		undef $offset_run_flag if ! defined $this_edit;
		reconfigure_engine();
	}
}
sub adjust_offset_recordings {
	map {
		$_->set(playat => $offset_mark);
		say $_->name, ": offsetting to $offset_mark";
	} engine_wav_out_tracks();
}
sub post_rec_configure {

		$ui->global_version_buttons(); # recreate
		adjust_offset_recordings();
		# toggle buses of recorded tracks to MON
		map{ $bn{$_->group}->set(rw => 'MON') } engine_wav_out_tracks();
		#map{ $_->set(rw => 'MON')} ::Bus::all();
		$ui->refresh();
	#	reconfigure_engine(); # redundant
}
sub new_files_were_recorded {
 	return unless my @files = really_recording();
	$debug and print join $/, "intended recordings:", @files;
	my @recorded =
		grep { 	my ($name, $version) = /([^\/]+)_(\d+).wav$/;
				if (-e ) {
					if (-s  > 44100) { # 0.5s x 16 bits x 44100/s
						$debug and print "found bigger than 44100 bytes:\n";
						$debug and print "$_\n";
						$tn{$name}->set(version => undef) if $tn{$name};
						$ui->update_version_button($tn{$name}->n, $version);
					1;
					}
					else { unlink $_; 0 }
				}
		} @files;
	if(@recorded){
		rememoize();
		say join $/,"recorded:",@recorded;
	}
	map{ get_wav_info($_) } @recorded;
	@recorded 
} 

	
sub fade {
	my ($id, $param, $from, $to, $seconds) = @_;

	# no fade without Timer::HiRes
	# no fade unless engine is running
	if ( ! engine_running() or ! $hires ){
		effect_update_copp_set ( $id, $param, $to );
		return;
	}

	my $steps = $seconds * $fade_resolution;
	my $wink  = 1/$fade_resolution;
	my $size = ($to - $from)/$steps;
	$debug and print "id: $id, param: $param, from: $from, to: $to, seconds: $seconds\n";
	for (1..$steps - 1){
		modify_effect( $id, $param, '+', $size);
		sleeper( $wink );
	}		
	effect_update_copp_set( 
		$id, 
		$param, 
		$to);
	
}

sub fadein {
	my ($id, $to) = @_;
	my $from  = $fade_out_level{$cops{$id}->{type}};
	fade( $id, 0, $from, $to, $fade_time);
}
sub fadeout {
	my $id    = shift;
	my $from  =	$copp{$id}[0];
	my $to	  = $fade_out_level{$cops{$id}->{type}};
	fade( $id, 0, $from, $to, $fade_time );
}

sub find_op_offsets {

	$debug2 and print "&find_op_offsets\n";
	my @op_offsets = grep{ /"\d+"/} split "\n",eval_iam("cs");
	$debug and print join "\n\n",@op_offsets; 
	for my $output (@op_offsets){
		my $chain_id;
		($chain_id) = $output =~ m/Chain "(\w*\d+)"/;
		# print "chain_id: $chain_id\n";
		next if $chain_id =~ m/\D/; # skip id's containing non-digits
									# i.e. M1
		my $quotes = $output =~ tr/"//;
		$debug and print "offset: $quotes in $output\n"; 
		$offset{$chain_id} = $quotes/2 - 1;  
	}
}
sub apply_ops {  # in addition to operators in .ecs file
	
	$debug2 and print "&apply_ops\n";
	for my $n ( map{ $_->n } ::Track::all() ) {
	$debug and print "chain: $n, offset: ", $offset{$n}, "\n";
 		next unless $is_ecasound_chain{$n};

		#next if $n == 2; # no volume control for mix track
		#next if ! defined $offset{$n}; # for MIX
 		#next if ! $offset{$n} ;

	# controllers will follow ops, so safe to apply all in order
		for my $id ( @{ $ti{$n}->ops } ) {
		apply_op($id);
		}
	}
	ecasound_select_chain($this_track->n) if defined $this_track;
}
sub apply_op {
	$debug2 and print "&apply_op\n";
	my $id = shift;
	my $selected = shift;
	$debug and print "id: $id\n";
	my $code = $cops{$id}->{type};
	my $dad = $cops{$id}->{belongs_to};
	$debug and print "chain: $cops{$id}->{chain} type: $cops{$id}->{type}, code: $code\n";
	#  if code contains colon, then follow with comma (preset, LADSPA)
	#  if code contains no colon, then follow with colon (ecasound,  ctrl)
	
	$code = '-' . $code . ($code =~ /:/ ? q(,) : q(:) );
	my @vals = @{ $copp{$id} };
	$debug and print "values: @vals\n";

	# we start to build iam command

	my $add = $dad ? "ctrl-add " : "cop-add "; 
	
	$add .= $code . join ",", @vals;

	# if my parent has a parent then we need to append the -kx  operator

	$add .= " -kx" if $cops{$dad}->{belongs_to};
	$debug and print "command:  ", $add, "\n";

	eval_iam("c-select $cops{$id}->{chain}") 
		if $selected != $cops{$id}->{chain};

	if ( $dad ) {
	eval_iam("cop-select " . ecasound_effect_index($dad));
	}

	eval_iam($add);
	$debug and print "children found: ", join ",", "|",@{$cops{$id}->{owns}},"|\n";
	my $ref = ref $cops{$id}->{owns} ;
	$ref =~ /ARRAY/ or croak "expected array";
	my @owns = @{ $cops{$id}->{owns} };
	$debug and print "owns: @owns\n";  
	#map{apply_op($_)} @owns;

}

sub prepare_effects_help {

	# presets
	map{	s/^.*? //; 				# remove initial number
					$_ .= "\n";				# add newline
					my ($id) = /(pn:\w+)/; 	# find id
					s/,/, /g;				# to help line breaks
					push @effects_help,    $_;  #store help

				}  split "\n",eval_iam("preset-register");

	# LADSPA
	my $label;
	map{ 

		if (  my ($_label) = /-(el:[-\w]+)/  ){
				$label = $_label;
				s/^\s+/ /;				 # trim spaces 
				s/'//g;     			 # remove apostrophes
				$_ .="\n";               # add newline
				push @effects_help, $_;  # store help

		} else { 
				# replace leading number with LADSPA Unique ID
				s/^\d+/$ladspa_unique_id{$label}/;

				s/\s+$/ /;  			# remove trailing spaces
				substr($effects_help[-1],0,0) = $_; # join lines
				$effects_help[-1] =~ s/,/, /g; # 
				$effects_help[-1] =~ s/,\s+$//;
				
		}

	} reverse split "\n",eval_iam("ladspa-register");


#my @lines = reverse split "\n",eval_iam("ladspa-register");
#pager( scalar @lines, $/, join $/,@lines);
	
	#my @crg = map{s/^.*? -//; $_ .= "\n" }
	#			split "\n",eval_iam("control-register");
	#pager (@lrg, @prg); exit;
}

sub prepare_static_effects_data{
	
	$debug2 and print "&prepare_static_effects_data\n";

	my $effects_cache = join_path(&project_root, $effects_cache_file);

	#print "newplugins: ", new_plugins(), $/;
	if ($opts{r} or new_plugins()){ 

		eval { unlink $effects_cache};
		print "Regenerating effects data cache\n";
	}

	if (-f $effects_cache and ! $opts{s}){  
		$debug and print "found effects cache: $effects_cache\n";
		assign_var($effects_cache, @effects_static_vars);
	} else {
		
		$debug and print "reading in effects data, please wait...\n";
		read_in_effects_data();  
		# cop-register, preset-register, ctrl-register, ladspa-register
		get_ladspa_hints();     
		integrate_ladspa_hints();
		integrate_cop_hints();
		sort_ladspa_effects();
		prepare_effects_help();
		serialize (
			file => $effects_cache, 
			vars => \@effects_static_vars,
			class => '::',
			format => 'storable');
	}

	prepare_effect_index();
}

sub ladspa_plugin_list {
	my @plugins;
	my %seen;
	for my $dir ( split ':', ladspa_path()){
		next unless -d $dir;
		opendir my $dirh, $dir;
		push @plugins,  
			map{"$dir/$_"} 						# full path
			grep{ ! $seen{$_} and ++$seen{$_}}  # skip seen plugins
			grep{ /\.so$/} readdir $dirh;			# get .so files
		closedir $dirh;
	}
	@plugins
}

sub new_plugins {
	my $effects_cache = join_path(&project_root, $effects_cache_file);
	my @filenames = ladspa_plugin_list();	
	push @filenames, '/usr/local/share/ecasound/effect_presets',
                 '/usr/share/ecasound/effect_presets',
                 "$ENV{HOME}/.ecasound/effect_presets";
	my $effects_cache_stamp = modified_stamp($effects_cache);
	my $latest;
	map{ my $mod = modified_stamp($_);
		 $latest = $mod if $mod > $latest } @filenames;

	$latest > $effects_cache_stamp;
}

sub modified_stamp {
	# timestamp that file was modified
	my $filename = shift;
	#print "file: $filename\n";
	my @s = stat $filename;
	$s[9];
}
sub prepare_effect_index {
	$debug2 and print "&prepare_effect_index\n";
	%effect_j = ();
	map{ 
		my $code = $_;
		my ($short) = $code =~ /:([-\w]+)/;
		if ( $short ) { 
			if ($effect_j{$short}) { warn "name collision: $_\n" }
			else { $effect_j{$short} = $code }
		}else{ $effect_j{$code} = $code };
	} keys %effect_i;
	#print yaml_out \%effect_j;
}
sub extract_effects_data {
	$debug2 and print "&extract_effects_data\n";
	my ($lower, $upper, $regex, $separator, @lines) = @_;
	carp ("incorrect number of lines ", join ' ',$upper-$lower,scalar @lines)
		if $lower + @lines - 1 != $upper;
	$debug and print"lower: $lower upper: $upper  separator: $separator\n";
	#$debug and print "lines: ". join "\n",@lines, "\n";
	$debug and print "regex: $regex\n";
	
	for (my $j = $lower; $j <= $upper; $j++) {
		my $line = shift @lines;
	
		$line =~ /$regex/ or carp("bad effect data line: $line\n"),next;
		my ($no, $name, $id, $rest) = ($1, $2, $3, $4);
		$debug and print "Number: $no Name: $name Code: $id Rest: $rest\n";
		my @p_names = split $separator,$rest; 
		map{s/'//g}@p_names; # remove leading and trailing q(') in ladspa strings
		$debug and print "Parameter names: @p_names\n";
		$effects[$j]={};
		$effects[$j]->{number} = $no;
		$effects[$j]->{code} = $id;
		$effects[$j]->{name} = $name;
		$effects[$j]->{count} = scalar @p_names;
		$effects[$j]->{params} = [];
		$effects[$j]->{display} = qq(field);
		map{ push @{$effects[$j]->{params}}, {name => $_} } @p_names
			if @p_names;
;
	}
}
sub sort_ladspa_effects {
	$debug2 and print "&sort_ladspa_effects\n";
#	print yaml_out(\%e_bound); 
	my $aa = $e_bound{ladspa}{a};
	my $zz = $e_bound{ladspa}{z};
#	print "start: $aa end $zz\n";
	map{push @ladspa_sorted, 0} ( 1 .. $aa ); # fills array slice [0..$aa-1]
	splice @ladspa_sorted, $aa, 0,
		 sort { $effects[$a]->{name} cmp $effects[$b]->{name} } ($aa .. $zz) ;
	$debug and print "sorted array length: ". scalar @ladspa_sorted, "\n";
}		
sub read_in_effects_data {
	
	$debug2 and print "&read_in_effects_data\n";

	my $lr = eval_iam("ladspa-register");

	#print $lr; 
	
	my @ladspa =  split "\n", $lr;
	
	# join the two lines of each entry
	my @lad = map { join " ", splice(@ladspa,0,2) } 1..@ladspa/2; 

	my @preset = grep {! /^\w*$/ } split "\n", eval_iam("preset-register");
	my @ctrl  = grep {! /^\w*$/ } split "\n", eval_iam("ctrl-register");
	my @cop = grep {! /^\w*$/ } split "\n", eval_iam("cop-register");

	$debug and print "found ", scalar @cop, " Ecasound chain operators\n";
	$debug and print "found ", scalar @preset, " Ecasound presets\n";
	$debug and print "found ", scalar @ctrl, " Ecasound controllers\n";
	$debug and print "found ", scalar @lad, " LADSPA effects\n";

	# index boundaries we need to make effects list and menus
	$e_bound{cop}{a}   = 1;
	$e_bound{cop}{z}   = @cop; # scalar
	$e_bound{ladspa}{a} = $e_bound{cop}{z} + 1;
	$e_bound{ladspa}{b} = $e_bound{cop}{z} + int(@lad/4);
	$e_bound{ladspa}{c} = $e_bound{cop}{z} + 2*int(@lad/4);
	$e_bound{ladspa}{d} = $e_bound{cop}{z} + 3*int(@lad/4);
	$e_bound{ladspa}{z} = $e_bound{cop}{z} + @lad;
	$e_bound{preset}{a} = $e_bound{ladspa}{z} + 1;
	$e_bound{preset}{b} = $e_bound{ladspa}{z} + int(@preset/2);
	$e_bound{preset}{z} = $e_bound{ladspa}{z} + @preset;
	$e_bound{ctrl}{a}   = $e_bound{preset}{z} + 1;
	$e_bound{ctrl}{z}   = $e_bound{preset}{z} + @ctrl;

	my $cop_re = qr/
		^(\d+) # number
		\.    # dot
		\s+   # spaces+
		(\w.+?) # name, starting with word-char,  non-greedy
		# (\w+) # name
		,\s*  # comma spaces* 
		-(\w+)    # cop_id 
		:?     # maybe colon (if parameters)
		(.*$)  # rest
	/x;

	my $preset_re = qr/
		^(\d+) # number
		\.    # dot
		\s+   # spaces+
		(\w+) # name
		,\s*  # comma spaces* 
		-(pn:\w+)    # preset_id 
		:?     # maybe colon (if parameters)
		(.*$)  # rest
	/x;

	my $ladspa_re = qr/
		^(\d+) # number
		\.    # dot
		\s+  # spaces
		(.+?) # name, starting with word-char,  non-greedy
		\s+     # spaces
		-(el:[-\w]+),? # ladspa_id maybe followed by comma
		(.*$)        # rest
	/x;

	my $ctrl_re = qr/
		^(\d+) # number
		\.     # dot
		\s+    # spaces
		(\w.+?) # name, starting with word-char,  non-greedy
		,\s*    # comma, zero or more spaces
		-(k\w+):?    # ktrl_id maybe followed by colon
		(.*$)        # rest
	/x;

	extract_effects_data(
		$e_bound{cop}{a},
		$e_bound{cop}{z},
		$cop_re,
		q(','),
		@cop,
	);


	extract_effects_data(
		$e_bound{ladspa}{a},
		$e_bound{ladspa}{z},
		$ladspa_re,
		q(','),
		@lad,
	);

	extract_effects_data(
		$e_bound{preset}{a},
		$e_bound{preset}{z},
		$preset_re,
		q(,),
		@preset,
	);
	extract_effects_data(
		$e_bound{ctrl}{a},
		$e_bound{ctrl}{z},
		$ctrl_re,
		q(,),
		@ctrl,
	);



	for my $i (0..$#effects){
		 $effect_i{ $effects[$i]->{code} } = $i; 
		 $debug and print "i: $i code: $effects[$i]->{code} display: $effects[$i]->{display}\n";
	}

	$debug and print "\@effects\n======\n", yaml_out(\@effects); ; 
}

sub integrate_cop_hints {

	my @cop_hints = @{ yaml_in( $cop_hints_yml ) };
	for my $hashref ( @cop_hints ){
		#print "cop hints ref type is: ",ref $hashref, $/;
		my $code = $hashref->{code};
		$effects[ $effect_i{ $code } ] = $hashref;
	}
}
sub ladspa_path {
	$ENV{LADSPA_PATH} || q(/usr/lib/ladspa);
}
sub get_ladspa_hints{
	$debug2 and print "&get_ladspa_hints\n";
	my @dirs =  split ':', ladspa_path();
	my $data = '';
	my %seen = ();
	my @plugins = ladspa_plugin_list();
	#pager join $/, @plugins;

	# use these regexes to snarf data
	
	my $pluginre = qr/
	Plugin\ Name:       \s+ "([^"]+)" \s+
	Plugin\ Label:      \s+ "([^"]+)" \s+
	Plugin\ Unique\ ID: \s+ (\d+)     \s+
	[^\x00]+(?=Ports) 		# swallow maximum up to Ports
	Ports: \s+ ([^\x00]+) 	# swallow all
	/x;

	my $paramre = qr/
	"([^"]+)"   #  name inside quotes
	\s+
	(.+)        # rest
	/x;
		
	my $i;

	for my $file (@plugins){
		my @stanzas = split "\n\n", qx(analyseplugin $file);
		for my $stanza (@stanzas) {

			my ($plugin_name, $plugin_label, $plugin_unique_id, $ports)
			  = $stanza =~ /$pluginre/ 
				or carp "*** couldn't match plugin stanza $stanza ***";
			$debug and print "plugin label: $plugin_label $plugin_unique_id\n";

			my @lines = grep{ /input/ and /control/ } split "\n",$ports;

			my @params;  # data
			my @names;
			for my $p (@lines) {
				next if $p =~ /^\s*$/;
				$p =~ s/\.{3}/10/ if $p =~ /amplitude|gain/i;
				$p =~ s/\.{3}/60/ if $p =~ /delay|decay/i;
				$p =~ s(\.{3})($ladspa_sample_rate/2) if $p =~ /frequency/i;
				$p =~ /$paramre/;
				my ($name, $rest) = ($1, $2);
				my ($dir, $type, $range, $default, $hint) = 
					split /\s*,\s*/ , $rest, 5;
				$debug and print join( 
				"|",$name, $dir, $type, $range, $default, $hint) , $/; 
				#  if $hint =~ /logarithmic/;
				if ( $range =~ /toggled/i ){
					$range = q(0 to 1);
					$hint .= q(toggled);
				}
				my %p;
				$p{name} = $name;
				$p{dir} = $dir;
				$p{hint} = $hint;
				my ($beg, $end, $default_val, $resolution) 
					= range($name, $range, $default, $hint, $plugin_label);
				$p{begin} = $beg;
				$p{end} = $end;
				$p{default} = $default_val;
				$p{resolution} = $resolution;
				push @params, { %p };
			}

			$plugin_label = "el:" . $plugin_label;
			$ladspa_help{$plugin_label} = $stanza;
			$effects_ladspa_file{$plugin_unique_id} = $file;
			$ladspa_unique_id{$plugin_label} = $plugin_unique_id; 
			$ladspa_unique_id{$plugin_name} = $plugin_unique_id; 
			$ladspa_label{$plugin_unique_id} = $plugin_label;
			$effects_ladspa{$plugin_label}->{name}  = $plugin_name;
			$effects_ladspa{$plugin_label}->{id}    = $plugin_unique_id;
			$effects_ladspa{$plugin_label}->{params} = [ @params ];
			$effects_ladspa{$plugin_label}->{count} = scalar @params;
			$effects_ladspa{$plugin_label}->{display} = 'scale';
		}	#	pager( join "\n======\n", @stanzas);
		#last if ++$i > 10;
	}

	$debug and print yaml_out(\%effects_ladspa); 
}

sub srate_val {
	my $input = shift;
	my $val_re = qr/(
			[+-]? 			# optional sign
			\d+				# one or more digits
			(\.\d+)?	 	# optional decimal
			(e[+-]?\d+)?  	# optional exponent
	)/ix;					# case insensitive e/E
	my ($val) = $input =~ /$val_re/; #  or carp "no value found in input: $input\n";
	$val * ( $input =~ /srate/ ? $ladspa_sample_rate : 1 )
}
	
sub range {
	my ($name, $range, $default, $hint, $plugin_label) = @_; 
	my $multiplier = 1;;
	my ($beg, $end) = split /\s+to\s+/, $range;
	$beg = 		srate_val( $beg );
	$end = 		srate_val( $end );
	$default = 	srate_val( $default );
	$default = $default || $beg;
	$debug and print "beg: $beg, end: $end, default: $default\n";
	if ( $name =~ /gain|amplitude/i ){
		$beg = 0.01 unless $beg;
		$end = 0.01 unless $end;
	}
	my $resolution = ($end - $beg) / 100;
	if    ($hint =~ /integer|toggled/i ) { $resolution = 1; }
	elsif ($hint =~ /logarithmic/ ) {

		$beg = round ( log $beg ) if $beg;
		$end = round ( log $end ) if $end;
		$resolution = ($end - $beg) / 100;
		$default = $default ? round (log $default) : $default;
	}
	
	$resolution = d2( $resolution + 0.002) if $resolution < 1  and $resolution > 0.01;
	$resolution = dn ( $resolution, 3 ) if $resolution < 0.01;
	$resolution = int ($resolution + 0.1) if $resolution > 1 ;
	
	($beg, $end, $default, $resolution)

}
sub integrate_ladspa_hints {
	$debug2 and print "&integrate_ladspa_hints\n";
	map{ 
		my $i = $effect_i{$_};
		# print("$_ not found\n"), 
		if ($i) {
			$effects[$i]->{params} = $effects_ladspa{$_}->{params};
			# we revise the number of parameters read in from ladspa-register
			$effects[$i]->{count} = scalar @{$effects_ladspa{$_}->{params}};
			$effects[$i]->{display} = $effects_ladspa{$_}->{display};
		}
	} keys %effects_ladspa;

my %L;
my %M;

map { $L{$_}++ } keys %effects_ladspa;
map { $M{$_}++ } grep {/el:/} keys %effect_i;

for my $k (keys %L) {
	$M{$k} or $debug and print "$k not found in ecasound listing\n";
}
for my $k (keys %M) {
	$L{$k} or $debug and print "$k not found in ladspa listing\n";
}


$debug and print join "\n", sort keys %effects_ladspa;
$debug and print '-' x 60, "\n";
$debug and print join "\n", grep {/el:/} sort keys %effect_i;

#print yaml_out \@effects; exit;

}
sub d1 {
	my $n = shift;
	sprintf("%.1f", $n)
}
sub d2 {
	my $n = shift;
	sprintf("%.2f", $n)
}
sub dn {
	my ($n, $places) = @_;
	sprintf("%." . $places . "f", $n);
}
sub round {
	my $n = shift;
	return 0 if $n == 0;
	$n = int $n if $n > 10;
	$n = d2($n) if $n < 10;
	$n;
}
sub colonize { # convert seconds to hours:minutes:seconds 
	my $sec = shift || 0;
	my $hours = int ($sec / 3600);
	$sec = $sec % 3600;
	my $min = int ($sec / 60);
	$sec = $sec % 60;
	$sec = "0$sec" if $sec < 10;
	$min = "0$min" if $min < 10 and $hours;
	($hours ? "$hours:" : "") . qq($min:$sec);
}



sub time_tag {
	my @time = localtime time;
	$time[4]++;
	$time[5]+=1900;
	@time = @time[5,4,3,2,1,0];
	sprintf "%4d.%02d.%02d-%02d:%02d:%02d", @time
}

sub autosave {
	if (engine_running()){ 
		schedule_autosave(1); # try again in 60s
		return;
	}
 	my $file = 'State-autosave-' . time_tag();
 	save_system_state($file);
	my @saved = autosave_files();
	my ($next_last, $last) = @saved[-2,-1];
	schedule_autosave(); # standard interval
	return unless defined $next_last and defined $last;
	if(files_are_identical($next_last, $last)){
		unlink $last;
		undef; 
	} else { 
		$last 
	}
}
sub autosave_files {
	sort File::Find::Rule  ->file()
						->name('State-autosave-*')
							->maxdepth(1)
						 	->in( project_dir());
}
sub files_are_identical {
	my ($filea,$fileb) = @_;
	my $a = io($filea)->slurp;
	my $b = io($fileb)->slurp;
	$a eq $b
}

sub process_control_inputs { }


sub set_position {

    return if really_recording(); # don't allow seek while recording

    my $seconds = shift;
    my $coderef = sub{ eval_iam("setpos $seconds") };

    if( $jack_running and eval_iam('engine-status') eq 'running')
			{ engine_stop_seek_start( $coderef ) }
	else 	{ $coderef->() }
	update_clock_display();
}

sub engine_stop_seek_start {
	my $coderef = shift;
	eval_iam('stop');
	$coderef->();
	sleeper($seek_delay);
	eval_iam('start');
}

sub forward {
	my $delta = shift;
	my $here = eval_iam('getpos');
	my $new = $here + $delta;
	set_position( $new );
}

sub rewind {
	my $delta = shift;
	forward( -$delta );
}
sub solo {
	my @args = @_;

	# get list of already muted tracks if I haven't done so already
	
	if ( ! @already_muted ){
		@already_muted = grep{ $_->old_vol_level} 
                         map{ $tn{$_} } 
						 ::Track::user();
	}

	$debug and say join " ", "already muted:", map{$_->name} @already_muted;

	# convert bunches to tracks
	my @names = map{ bunch_tracks($_) } @args;

	# use hashes to store our list
	
	my %to_mute;
	my %not_mute;
	
	# get dependent tracks
	
	my @d = map{ $tn{$_}->bus_tree() } @names;

	# store solo tracks and dependent tracks that we won't mute

	map{ $not_mute{$_}++ } @names, @d;

	# find all siblings tracks not in depends list

	# - get buses list corresponding to our non-muting tracks
	
	my %buses;
	$buses{Main}++; 				# we always want Main
	
	map{ $buses{$_}++ } 			# add to buses list
	map { $tn{$_}->group } 			# corresponding bus (group) names
	keys %not_mute;					# tracks we want

	# - get sibling tracks we want to mute

	map{ $to_mute{$_}++ }			# add to mute list
	grep{ ! $not_mute{$_} }			# those we *don't* want
	map{ $bn{$_}->tracks }			# tracks list
	keys %buses;					# buses list

	# mute all tracks on our mute list (do we skip already muted tracks?)
	
	map{ $tn{$_}->mute('nofade') } keys %to_mute;

	# unmute all tracks on our wanted list
	
	map{ $tn{$_}->unmute('nofade') } keys %not_mute;
	
	$soloing = 1;
}

sub nosolo {
	# unmute all except in @already_muted list

	# unmute all tracks
	map { $tn{$_}->unmute('nofade') } ::Track::user();

	# re-mute previously muted tracks
	if (@already_muted){
		map { $_->mute('nofade') } @already_muted;
	}

	# remove listing of muted tracks
	@already_muted = ();
	
	$soloing = 0;
}
sub all {

	# unmute all tracks
	map { $tn{$_}->unmute('nofade') } ::Track::user();

	# remove listing of muted tracks
	@already_muted = ();
	
	$soloing = 0;
}

sub pager {
	$debug2 and print "&pager\n";
	my @output = @_;
	my ($screen_lines, $columns) = $term->get_screen_size();
	my $line_count = 0;
	map{ $line_count += $_ =~ tr(\n)(\n) } @output;
	if ( $use_pager and $line_count > $screen_lines - 2) { 
		my $fh = File::Temp->new();
		my $fname = $fh->filename;
		print $fh @output;
		file_pager($fname);
	} else {
		print @output;
	}
	print "\n\n";
}
sub file_pager {
	$debug2 and print "&file_pager\n";
	my $fname = shift;
	if (! -e $fname or ! -r $fname ){
		carp "file not found or not readable: $fname\n" ;
		return;
    }
	my $pager = $ENV{PAGER} || "/usr/bin/less";
	my $cmd = qq($pager $fname); 
	system $cmd;
}
sub dump_all {
	my $tmp = ".dump_all";
	my $fname = join_path( project_root(), $tmp);
	save_state($fname);
	file_pager("$fname.yml");
}


sub show_io {
	my $output = yaml_out( \%inputs ). yaml_out( \%outputs ); 
	pager( $output );
}

# command line processing routines

sub get_ecasound_iam_keywords {

	my %reserved = map{ $_,1 } qw(  forward
									fw
									getpos
									h
									help
									rewind
									quit
									q
									rw
									s
									setpos
									start
									stop
									t
									?	);
	
	local $debug = 0;
	%iam_cmd = map{$_,1 } 
				grep{ ! $reserved{$_} } split /[\s,]/, eval_iam('int-cmd-list');
}

sub process_line {
	$debug2 and print "&process_line\n";
	my ($user_input) = @_;
	$debug and print "user input: $user_input\n";
	if (defined $user_input and $user_input !~ /^\s*$/) {
		$term->addhistory($user_input) 
			unless $user_input eq $previous_text_command;
		$previous_text_command = $user_input;
		command_process( $user_input );
		reconfigure_engine();
		revise_prompt();
	}
}
sub command_process {
	my $input = shift;
	my $input_was = $input;

	# parse repeatedly until all input is consumed
	
	while ($input =~ /\S/) { 
		$debug and say "input: $input";
		$parser->meta(\$input) or print("bad command: $input_was\n"), last;
	}
	$ui->refresh; # in case we have a graphic environment
	set_current_bus();
}


sub leading_track_spec {
	my $cmd = shift;
	if( my $track = $tn{$cmd} || $ti{$cmd} ){
		$debug and print "Selecting track ",$track->name,"\n";
		$this_track = $track;
		set_current_bus();
		ecasound_select_chain( $this_track->n );
		1;
	}
		
}
sub ecasound_select_chain {
	my $n = shift;
	my $cmd = "c-select $n";

	if( 

		# specified chain exists in the chain setup
		$is_ecasound_chain{$n}

		# engine is configured
		and eval_iam( 'cs-connected' ) =~ /$chain_setup_file/

	){ 	eval_iam($cmd); 
		return 1 

	} else { 
		$debug and carp 
			"c-select $n: attempted to select non-existing Ecasound chain\n"; 
		return 0
	}
}
sub set_current_bus {
	my $track = shift || ($this_track ||= $tn{Master});
	#say "track: $track";
	#say "this_track: $this_track";
	#say "master: $tn{Master}";
	if( $track->name =~ /Master|Mixdown/){ $this_bus = 'Main' }
	elsif( $bn{$track->name} ){$this_bus = $track->name }
	else { $this_bus = $track->group }
}
sub eval_perl {
	my $code = shift;
	my (@result) = eval $code;
	print( "Perl command failed: $@\n") if $@;
	pager(join "\n", @result) unless $@;
	print "\n";
}	

sub is_bunch {
	my $name = shift;
	$bn{$name} or $bunch{$name}
}
my %set_stat = ( 
				 (map{ $_ => 'rw' } qw(rec mon off) ), 
				 map{ $_ => 'rec_status' } qw(REC MON OFF)
				 );

sub bunch_tracks {
	my $bunchy = shift;
	my @tracks;
	if ( my $bus = $bn{$bunchy}){
		@tracks = $bus->tracks;
	} elsif ( $bunchy eq 'bus' ){
		$debug and print "special bunch: bus\n";
		@tracks = grep{ ! $bn{$_} } $bn{$this_bus}->tracks;
	} elsif ($bunchy =~ /\s/  # multiple identifiers
		or $tn{$bunchy} 
		or $bunchy !~ /\D/ and $ti{$bunchy}){ 
			$debug and print "multiple tracks found\n";
			# verify all tracks are correctly named
			my @track_ids = split " ", $bunchy;
			my @illegal = grep{ ! track_from_name_or_index($_) } @track_ids;
			if ( @illegal ){
				say("Invalid track ids: @illegal.  Skipping.");
			} else { @tracks = map{ $_->name} 
							   map{ track_from_name_or_index($_)} @track_ids; }

	} elsif ( my $method = $set_stat{$bunchy} ){
		$debug and say "special bunch: $bunchy, method: $method";
		$bunchy = uc $bunchy;
		@tracks = grep{$tn{$_}->$method eq $bunchy} 
				$bn{$this_bus}->tracks
	} elsif ( $bunch{$bunchy} and @tracks = @{$bunch{$bunchy}}  ) {
		$debug and print "bunch tracks: @tracks\n";
	} else { say "$bunchy: no matching bunch identifier found" }
	@tracks;
}
sub track_from_name_or_index { /\D/ ? $tn{$_[0]} : $ti{$_[0]}  }
	
sub load_keywords {
	@keywords = keys %commands;
	push @keywords, grep{$_} map{split " ", $commands{$_}->{short}} @keywords;
	push @keywords, keys %iam_cmd;
	push @keywords, keys %effect_j;
	push @keywords, keys %midish_command if $midish_enable;
	push @keywords, "Audio::Nama::";
}

sub complete {
    my ($text, $line, $start, $end) = @_;
#	print join $/, $text, $line, $start, $end, $/;
    return $term->completion_matches($text,\&keyword);
};

{ 	my $i;
sub keyword {
        my ($text, $state) = @_;
        return unless $text;
        if($state) {
            $i++;
        }
        else { # first call
            $i = 0;
        }
        for (; $i<=$#keywords; $i++) {
            return $keywords[$i] if $keywords[$i] =~ /^\Q$text/;
        };
        return undef;
} };

# JACK related functions

sub poll_jack { $event_id{poll_jack} = AE::timer(0,5,\&jack_update) }

sub jack_update {
	# cache current JACK status
	return if engine_running();
	if( $jack_running =  process_is_running('jackd') ){
		my $jack_lsp = qx(jack_lsp -Ap 2> /dev/null); 
		%jack = %{jack_ports($jack_lsp)}
	} else { %jack = () }
}

sub jack_client {

	# returns array of ports if client and direction exist
	
	my ($name, $direction)  = @_;
	$jack{$name}{$direction} // []
}

sub jack_ports {
	my $j = shift || $jack_lsp; 
	#say "jack_lsp: $j";

	# convert to single lines

	$j =~ s/\n\s+/ /sg;

	# system:capture_1 alsa_pcm:capture_1 properties: output,physical,terminal,
	#fluidsynth:left properties: output,
	#fluidsynth:right properties: output,
	my %jack = ();

	map{ 
		my ($direction) = /properties: (input|output)/;
		s/properties:.+//;
		my @port_aliases = /
			\s* 			# zero or more spaces
			([^:]+:[^:]+?) # non-colon string, colon, non-greedy non-colon string
			(?=[-+.\w]+:|\s+$) # zero-width port name or spaces to end-of-string
		/gx;
		map { 
				s/ $//; # remove trailing space
				push @{ $jack{ $_ }{ $direction } }, $_;
				my ($client, $port) = /(.+?):(.+)/;
				push @{ $jack{ $client }{ $direction } }, $_; 

		 } @port_aliases;

	} 
	grep{ ! /^jack:/i } # skip spurious jackd diagnostic messages
	split "\n",$j;
	#print yaml_out \%jack;
	\%jack
}
	
sub automix {

	# get working track set
	
	my @tracks = grep{
					$tn{$_}->rec_status eq 'MON' or
					$bn{$_} and $tn{$_}->rec_status eq 'REC'
				 } $main->tracks;

	say "tracks: @tracks";

	## we do not allow automix if inserts are present	

	say("Cannot perform automix if inserts are present. Skipping."), return
		if grep{$tn{$_}->prefader_insert || $tn{$_}->postfader_insert} @tracks;

	#use Smart::Comments '###';
	# add -ev to summed signal
	my $ev = add_effect( { chain => $tn{Master}->n, type => 'ev' } );
	### ev id: $ev

	# turn off audio output
	
	$main_out = 0;

	### Status before mixdown:

	command_process('show');

	
	### reduce track volume levels  to 10%

	## accommodate ea and eadb volume controls

	my $vol_operator = $cops{$tn{$tracks[0]}->vol}{type};

	my $reduce_vol_command  = $vol_operator eq 'ea' ? 'vol / 10' : 'vol - 10';
	my $restore_vol_command = $vol_operator eq 'ea' ? 'vol * 10' : 'vol + 10';

	### reduce vol command: $reduce_vol_command

	for (@tracks){ command_process("$_  $reduce_vol_command") }

	command_process('show');

	generate_setup('automix') # pass a bit of magic
		or say("automix: generate_setup failed!"), return;
	connect_transport();
	
	# start_transport() does a rec_cleanup() on transport stop
	
	eval_iam('start'); # don't use heartbeat
	sleep 2; # time for engine to stabilize
	while( eval_iam('engine-status') ne 'finished'){ 
		print q(.); sleep 1; update_clock_display()}; 
	print " Done\n";

	# parse cop status
	my $cs = eval_iam('cop-status');
	### cs: $cs
	my $cs_re = qr/Chain "1".+?result-max-multiplier ([\.\d]+)/s;
	my ($multiplier) = $cs =~ /$cs_re/;

	### multiplier: $multiplier

	remove_effect($ev);

	# deal with all silence case, where multiplier is 0.00000
	
	if ( $multiplier < 0.00001 ){

		say "Signal appears to be silence. Skipping.";
		for (@tracks){ command_process("$_  $restore_vol_command") }
		$main_out = 1;
		return;
	}

	### apply multiplier to individual tracks

	for (@tracks){ command_process( "$_ vol*$multiplier" ) }

	# $main_out = 1; # unnecessary: mixdown will turn off and turn on main out
	
	### mixdown
	command_process('mixdown; arm; start');

	### turn on audio output

	# command_process('mixplay'); # rec_cleanup does this automatically

	#no Smart::Comments;
	
}

sub master_on {

	return if $mastering_mode;
	
	# set $mastering_mode	
	
	$mastering_mode++;

	# create mastering tracks if needed
	
	if ( ! $tn{Eq} ){  
	
		my $old_track = $this_track;
		add_mastering_tracks();
		add_mastering_effects();
		$this_track = $old_track;
	} else { 
		unhide_mastering_tracks();
		map{ $ui->track_gui($tn{$_}->n) } @mastering_track_names;
	}

}
	
sub master_off {

	$mastering_mode = 0;
	hide_mastering_tracks();
	map{ $ui->remove_track_gui($tn{$_}->n) } @mastering_track_names;
	$this_track = $tn{Master} if grep{ $this_track->name eq $_} @mastering_track_names;
;
}


sub add_mastering_tracks {

	map{ 
		my $track = ::MasteringTrack->new(
			name => $_,
			rw => 'MON',
			group => 'Mastering', 
		);
		$ui->track_gui( $track->n );

 	} grep{ $_ ne 'Boost' } @mastering_track_names;
	my $track = ::SlaveTrack->new(
		name => 'Boost', 
		rw => 'MON',
		group => 'Mastering', 
		target => 'Master',
	);
	$ui->track_gui( $track->n );

	
}

sub add_mastering_effects {
	
	$this_track = $tn{Eq};

	command_process("add_effect $eq");

	$this_track = $tn{Low};

	command_process("add_effect $low_pass");
	command_process("add_effect $compressor");
	command_process("add_effect $spatialiser");

	$this_track = $tn{Mid};

	command_process("add_effect $mid_pass");
	command_process("add_effect $compressor");
	command_process("add_effect $spatialiser");

	$this_track = $tn{High};

	command_process("add_effect $high_pass");
	command_process("add_effect $compressor");
	command_process("add_effect $spatialiser");

	$this_track = $tn{Boost};
	
	command_process("add_effect $limiter"); # insert after vol
}

sub unhide_mastering_tracks {
	command_process("for Mastering; set hide 0");
}

sub hide_mastering_tracks {
	command_process("for Mastering; set hide 1");
 }
		
# vol/pan requirements of mastering and mixdown tracks

{ my %volpan = (
	Eq => {},
	Low => {},
	Mid => {},
	High => {},
	Boost => {vol => 1},
	Mixdown => {},
);

sub need_vol_pan {

	# this routine used by 
	#
	# + add_track() to determine whether a new track _will_ need vol/pan controls
	# + add_track_gui() to determine whether an existing track needs vol/pan  
	
	my ($track_name, $type) = @_;

	# $type: vol | pan
	
	# Case 1: track already exists
	
	return 1 if $tn{$track_name} and $tn{$track_name}->$type;

	# Case 2: track not yet created

	if( $volpan{$track_name} ){
		return($volpan{$track_name}{$type}	? 1 : 0 )
	}
	return 1;
}
}
sub pan_check {
	my $new_position = shift;
	my $current = $copp{ $this_track->pan }->[0];
	$this_track->set(old_pan_level => $current)
		unless defined $this_track->old_pan_level;
	effect_update_copp_set(
		$this_track->pan,	# id
		0, 					# parameter
		$new_position,		# value
	);
}

# track width in words

sub width {
	my $count = shift;
	return 'mono' if $count == 1;
	return 'stereo' if $count == 2;
	return "$count channels";
}

sub effect_code {
	# get text effect code from user input, which could be
	# - LADSPA Unique ID (number)
	# - LADSPA Label (el:something)
	# - abbreviated LADSPA label (something)
	# - Ecasound operator (something)
	# - abbreviated Ecasound preset (something)
	# - Ecasound preset (pn:something)
	
	# there is no interference in these labels at present,
	# so we offer the convenience of using them without
	# el: and pn: prefixes.
	
	my $input = shift;
	my $code;
    if ($input !~ /\D/){ # i.e. $input is all digits
		$code = $ladspa_label{$input} 
			or carp("$input: LADSPA plugin not found.  Aborting.\n"), return;
	}
	elsif ( $effect_i{$input} ) { $code = $input } 
	elsif ( $effect_j{$input} ) { $code = $effect_j{$input} }
	else { warn "$input: effect code not found\n";}
	$code;
}

sub effect_index {
	my $code = shift;
	my $i = $effect_i{effect_code($code)};
	defined $i or warn "$code: effect index not found\n";
	$i
}



	# status_snapshot() 
	#
	# hashref output for detecting if we need to reconfigure engine
	# compared as YAML strings
	#
{
	my @sense_reconfigure = qw(
		name
		width
		group 
		playat
		region_start	
		region_end
		looping
		source_id
		source_type
		send_id
		send_type
		rec_defeat
		rec_status
		current_version
 );
sub status_snapshot {

	
	my %snapshot = ( project 		=> 	$project_name,
					 mastering_mode => $mastering_mode,
					 preview        => $preview,
					 main_out 		=> $main_out,
					 jack_running	=> $jack_running,
					 tracks			=> [], );
	map { push @{$snapshot{tracks}}, $_->snapshot(\@sense_reconfigure) }
	::Track::all();
	\%snapshot;
}
}
sub set_region {
	my ($beg, $end) = @_;
	$this_track->set(region_start => $beg);
	$this_track->set(region_end => $end);
	::Text::show_region();
}
sub new_region {
	my ($beg, $end, $name) = @_;
	$name ||= new_region_name();
	add_track_alias($name, $this_track->name);	
	set_region($beg,$end);
}
sub new_region_name {
	my $name = $this_track->name . '_region_';
	my $i;
	map{ my ($j) = /_(\d+)$/; $i = $j if $j > $i; }
		grep{/$name/} keys %::Track::by_name;
	$name . ++$i
}
sub remove_region {
	if (! $this_track->region_start){
		say $this_track->name, ": no region is defined. Skipping.";
		return;
	} elsif ($this_track->target ){
		say $this_track->name, ": looks like a region...  removing.";
		$this_track->remove;
	} else { undefine_region() }
}
	
sub undefine_region {
	$this_track->set(region_start => undef );
	$this_track->set(region_end => undef );
	print $this_track->name, ": Region definition removed. Full track will play.\n";
}

sub add_sub_bus {
	my ($name, @args) = @_; 
	
	::SubBus->new( 
		name => $name, 
		send_type => 'track',
		send_id	 => $name,
		) unless $::Bus::by_name{$name};

	# create mix track
	@args = ( 
		width 		=> 2,     # default to stereo 
		rec_defeat	=> 1,     # set to rec_defeat (don't record signal)
		rw 			=> 'REC', # set to REC (accept other track signals)
		@args
	);

	$tn{$name} and say qq($name: setting as mix track for bus "$name");

	my $track = $tn{$name} // add_track($name);

	# convert host track to mix track
	
	$track->set(was_class => ref $track); # save the current track (sub)class
	$track->set_track_class('::MixTrack'); 
	$track->set( @args );
	
}
	
sub add_send_bus {

	my ($name, $dest_id, $bus_type) = @_;
	my $dest_type = dest_type( $dest_id );

	# dest_type: soundcard | jack_client | loop | jack_port | jack_multi
	
	print "name: $name: dest_type: $dest_type dest_id: $dest_id\n";
	if ($bn{$name} and (ref $bn{$name}) !~ /SendBus/){
		say($name,": bus name already in use. Aborting."), return;
	}
	if ($bn{$name}){
		say qq(monitor bus "$name" already exists. Updating with new tracks.");
	} else {
	my @args = (
		name => $name, 
		send_type => $dest_type,
		send_id	 => $dest_id,
	);

	my $class = $bus_type eq 'cooked' ? '::SendBusCooked' : '::SendBusRaw';
	my $bus = $class->new( @args );

	$bus or carp("can't create bus!\n"), return;

	}
	map{ ::SlaveTrack->new(	name => "$name\_$_", # BusName_TrackName
							rw => 'MON',
							target => $_,
							group  => $name,
						)
   } $main->tracks;
		
}

sub dest_type {
	my $dest = shift;
	my $type;
	given( $dest ){
		when( undef )       {} # do nothing

		# non JACK related

		when('bus')			   { $type = 'bus'             }
		when('null')           { $type = 'null'            }
		when(/^loop,/)         { $type = 'loop'            }

		when(! /\D/)           { $type = 'soundcard'       } # digits only

		# JACK related

		when(/^man/)           { $type = 'jack_manual'     }
		when('jack')           { $type = 'jack_manual'     }
		when(/(^\w+\.)?ports/) { $type = 'jack_ports_list' }
		default                { $type = 'jack_client'     } 

	}
	$type
}
	
sub update_send_bus {
	my $name = shift;
		add_send_bus( $name, 
						 $bn{$name}->send_id),
						 "dummy",
}

sub private_effect_chain_name {
	my $name = "_$project_name/".$this_track->name.'_';
	my $i;
	map{ my ($j) = /_(\d+)$/; $i = $j if $j > $i; }
	@{ $this_track->effect_chain_stack }, 
		grep{/$name/} keys %effect_chain;
	$name . ++$i
}
sub profile_effect_chain_name {
	my ($profile, $track_name) = @_;
	"_$profile\:$track_name";
}

# too many functions in push and pop!!

sub push_effect_chain {
	$debug2 and say "&push_effect_chain";
	my ($track, %vals) = @_; 

	# use supplied ops list, or default to user-applied (fancy) ops
	
	my @ops = $vals{ops} ? @{$vals{ops}} : $track->fancy_ops;
	say("no effects to store"), return unless @ops;

	# use supplied name, or default to private name that will now show 
	# in listing
	
	my $save_name   = $vals{save} || private_effect_chain_name();
	$debug and say "save name: $save_name"; 

	# create a new effect-chain definition
	
	new_effect_chain( $track, $save_name, @ops ); # current track effects

	# store effect-chain name on track effect-chain stack
	
	push @{ $track->effect_chain_stack }, $save_name;

	# remove stored effects
	
	map{ remove_effect($_)} @ops;

	# return name

	$save_name;
}

sub pop_effect_chain { # restore previous
	$debug2 and say "&pop_effect_chain";
	my $track = shift;
	my $previous = pop @{$track->effect_chain_stack};
	say ("no previous effect chain"), return unless $previous;
	map{ remove_effect($_)} $track->fancy_ops;
	add_effect_chain($track, $previous);
	delete $effect_chain{$previous};
}
sub overwrite_effect_chain {
	$debug2 and say "&overwrite_effect_chain";
	my ($track, $name) = @_;
	print("$name: unknown effect chain.\n"), return if !  $effect_chain{$name};
	push_effect_chain($track) if $track->fancy_ops;
	add_effect_chain($track,$name); 
}
sub new_effect_profile {
	$debug2 and say "&new_effect_profile";
	my ($bunch, $profile) = @_;
	my @tracks = bunch_tracks($bunch);
	say qq(effect profile "$profile" created for tracks: @tracks);
	map { new_effect_chain($tn{$_}, profile_effect_chain_name($profile, $_)); 
	} @tracks;
	$effect_profile{$profile}{tracks} = [ @tracks ];
	save_effect_chains();
	save_effect_profiles();
}
sub delete_effect_profile { 
	$debug2 and say "&delete_effect_profile";
	my $name = shift;
	say qq(deleting effect profile: $name);
	my @tracks = $effect_profile{$name};
	delete $effect_profile{$name};
	map{ delete $effect_chain{profile_effect_chain_name($name,$_)} } @tracks;
}

sub apply_effect_profile {  # overwriting current effects
	$debug2 and say "&apply_effect_profile";
	my ($function, $profile) = @_;
	my @tracks = @{ $effect_profile{$profile}{tracks} };
	my @missing = grep{ ! $tn{$_} } @tracks;
	@missing and say(join(',',@missing), ": tracks do not exist. Aborting."),
		return;
	@missing = grep { ! $effect_chain{profile_effect_chain_name($profile,$_)} } @tracks;
	@missing and say(join(',',@missing), ": effect chains do not exist. Aborting."),
		return;
	map{ $function->( $tn{$_}, profile_effect_chain_name($profile,$_)) } @tracks;
}
sub list_effect_profiles { 
	my @results;
	while( my $name = each %effect_profile){
		push @results, "effect profile: $name\n";
		push @results, list_effect_chains("_$name:");
	}
	@results;
}

sub restore_effects { pop_effect_chain($_[0])}

sub new_effect_chain {
	my ($track, $name, @ops) = @_;
#	say "name: $name, ops: @ops";
	@ops or @ops = $track->fancy_ops;
	say $track->name, qq(: creating effect chain "$name") unless $name =~ /^_/;
	$effect_chain{$name} = { 
					ops 	=> \@ops,
					type 	=> { map{$_ => $cops{$_}{type} 	} @ops},
					params	=> { map{$_ => $copp{$_} 		} @ops},
	};
	save_effect_chains();
}

sub add_effect_chain {
	my ($track, $name) = @_;
	#say "track: $track name: ",$track->name, " effect chain: $name";
	say ("$name: effect chain does not exist"), return 
		if ! $effect_chain{$name};
	say $track->name, qq(: adding effect chain "$name") unless $name =~ /^_/;
	my $before = $track->vol;
	map {  $magical_cop_id = $_ unless $cops{$_}; # try to reuse cop_id
		if ($before){
			::Text::t_insert_effect(
				$before, 
				$effect_chain{$name}{type}{$_}, 
				$effect_chain{$name}{params}{$_});
		} else { 
			::Text::t_add_effect(
				$track, 
				$effect_chain{$name}{type}{$_}, 
				$effect_chain{$name}{params}{$_});
		}
		$magical_cop_id = undef;
	} @{$effect_chain{$name}{ops}};
}	
sub list_effect_chains {
	my @frags = @_; # fragments to match against effect_chain names
    # we don't list chain_ids starting with underscore
    # except when searching for particular chains
    my @ids = grep{ @frags or ! /^_/ } keys %::effect_chain;
	if (@frags){
		@ids = grep{ my $id = $_; grep{ $id =~ /$_/} @frags} @ids; 
	}
	my @results;
	map{ my $name = $_;
		push @results, join ' ', "$name:", 
		map{$effect_chain{$name}{type}{$_},
			@{$effect_chain{$name}{params}{$_}}
		} @{$effect_chain{$name}{ops}};
		push @results, "\n";
	} @ids;
	@results;
}
sub cleanup_exit {
 	remove_riff_header_stubs();
	# for each process: 
	# - SIGINT (1st time)
	# - allow time to close down
	# - SIGINT (2nd time)
	# - allow time to close down
	# - SIGKILL
	map{ my $pid = $_; 
		 map{ my $signal = $_; 
			  kill $signal, $pid; 
			  sleeper(0.2) 
			} (2,2,9)
	} @ecasound_pids;
 	#kill 15, ecasound_pid() if $sock;  	
	close_midish() if $midish_enable;
	$term->rl_deprep_terminal() if defined $term;
	exit; 
}
END { cleanup_exit() }

sub do_script {

	my $name = shift;
	my $file;
	# look in project_dir() and project_root()
	# if filename provided does not contain slash
	if( $name =~ m!/!){ $file = $name }
	else {
		$file = join_path(project_dir(),$name);
		if(-e $file){}
		else{ $file = join_path(project_root(),$name) }
	}
	-e $file or say("$file: file not found. Skipping"), return;
	my @lines = split "\n",read_file($file);
	my $old_opt_r = $opts{R};
	$opts{R} = 1; # turn off auto reconfigure
	for my $input (@lines) { process_line($input)};
	$opts{R} = $old_opt_r;
}
sub import_audio {

	my ($track, $path, $frequency) = @_;
	
	$this_track->import_audio($path, $frequency);

	# check that track is audible
	
	my $bus = $bn{$this_track->group};

	# set MON status unless track _is_ audible
	
	$this_track->set(rw => 'MON') 
		unless $bus->rw eq 'MON' and $this_track->rw eq 'REC';

	# warn if bus is OFF
	
	print("You must set bus to MON (i.e. \"bus_mon\") to hear this track.\n") 
		if $bus->rw eq 'OFF';
}
sub destroy_current_wav {
	my $old_group_status = $main->rw;
	$main->set(rw => 'MON');
	$this_track->current_version or
		say($this_track->name, 
			": No current version (track set to OFF?) Skipping."), return;
	my $wav = $this_track->full_path;
	my $reply = $term->readline("delete WAV file $wav? [n] ");
	#my $reply = chr($term->read_key()); 
	if ( $reply =~ /y/i ){
		# remove version comments, if any
		delete $this_track->{version_comment}{$this_track->current_version};
		print "Unlinking.\n";
		unlink $wav or warn "couldn't unlink $wav: $!\n";
		rememoize();
	}
	$term->remove_history($term->where_history);
	$main->set(rw => $old_group_status);
	1;
}

# the following routines are used only by the GUI
sub some_user_tracks {
	my $which = shift;
	my @user_tracks = ::Track::all();
	splice @user_tracks, 0, 2; # drop Master and Mixdown tracks
	return unless @user_tracks;
	my @selected_user_tracks = grep { $_->rec_status eq $which } @user_tracks;
	return unless @selected_user_tracks;
	map{ $_->n } @selected_user_tracks;
}
sub user_rec_tracks { some_user_tracks('REC') }
sub user_mon_tracks { some_user_tracks('MON') }


sub new_project_template {
	my ($template_name, $template_description) = @_;

	my @tracks = ::Track::all();

	# skip if project is empty

	say("No user tracks found, aborting.\n",
		"Cannot create template from an empty project."), 
		return if scalar @tracks < 3;

	# save current project status to temp state file 
	
	my $previous_state = '_previous_state.yml';
	save_state($previous_state);

	# edit current project into a template
	
	# No tracks are recorded, so we'll remove 
	#	- version (still called 'active')
	# 	- track caching
	# 	- region start/end points
	# 	- effect_chain_stack
	# Also
	# 	- unmute all tracks
	# 	- throw away any pan caching

	map{ my $track = $_;
		 $track->unmute;
		 map{ $track->set($_ => undef)  } 
			qw( version	
				old_pan_level
				region_start
				region_end
			);
		 map{ $track->set($_ => [])  } 
			qw(	effect_chain_stack      
			);
		 map{ $track->set($_ => {})  } 
			qw( cache_map 
			);
		
	} @tracks;

	# Throw away command history
	
	$term->SetHistory();
	
	# Buses needn't set version info either
	
	map{$_->set(version => undef)} values %bn;
	
	# create template directory if necessary
	
	mkdir join_path(project_root(), "templates");

	# save to template name
	
	save_state( join_path(project_root(), "templates", "$template_name.yml"));

	# add description, but where?
	
	# recall temp name
	
 	load_project(  # restore_state() doesn't do the whole job
 		name     => $project_name,
 		settings => $previous_state,
	);

	# remove temp state file
	
	unlink join_path( project_dir(), "$previous_state.yml") ;
	
}
sub use_project_template {
	my $name = shift;
	my @tracks = ::Track::all();

	# skip if project isn't empty

	say("User tracks found, aborting. Use templates in an empty project."), 
		return if scalar @tracks > 2;

	# load template
	
 	load_project(
 		name     => $project_name,
 		settings => join_path(project_root(),"templates",$name),
	);
	save_state();
}
sub list_project_templates {
	my $io = io(join_path(project_root(), "templates"));
	push my @templates, "\nTemplates:\n", map{ m|([^/]+).yml$|; $1, "\n"} $io->all;        
	pager(@templates);
}
sub remove_project_template {
	map{my $name = $_; 
		say "$name: removing template";
		$name .= ".yml" unless $name =~ /\.yml$/;
		unlink join_path( project_root(), "templates", $name);
	} @_;
	
}
sub kill_jack_plumbing {
	qx(killall jack.plumbing >/dev/null 2>&1)
	unless $opts{A} or $opts{J};
}
sub start_jack_plumbing {
	
	if ( 	$use_jack_plumbing				# not disabled in namarc
			and ! ($opts{J} or $opts{A})	# we are not testing   

	){ system('jack.plumbing >/dev/null 2>&1 &') }
}
{

my($error,$answer)=('','');
my ($pid, $sel);

sub start_midish {
	my $executable = qx(which midish);
	chomp $executable;
	$executable or say("Midish not found!"), return;
	$pid = open3(\*MIDISH_WRITE, \*MIDISH_READ,\*MIDISH_ERROR,"$executable -v")
		or warn "Midish failed to start!";

	$sel = new IO::Select();

	$sel->add(\*MIDISH_READ);
	$sel->add(\*MIDISH_ERROR);
	midish_command( qq(print "Welcome to Nama/Midish!"\n) );
}

sub midish_command {
	my $query = shift;
	print "\n";
	#$midish_enable or say( qq($query: cannot execute Midish command 
#unless you set "midish_enable: 1" in .namarc)), return;
	#$query eq 'exit' and say("Will exit Midish on closing Nama."), return;

	#send query to midish
	print MIDISH_WRITE "$query\n";

	foreach my $h ($sel->can_read)
	{
		my $buf = '';
		if ($h eq \*MIDISH_ERROR)
		{
			sysread(MIDISH_ERROR,$buf,4096);
			if($buf){print "MIDISH ERR-> $buf\n"}
		}
		else
		{
			sysread(MIDISH_READ,$buf,4096);
			if($buf){map{say "MIDISH-> $_"} grep{ !/\+ready/ } split "\n", $buf}
		}
	}
	print "\n";
}

sub close_midish {
	midish_command('exit');
	sleeper(0.1);
	kill 15,$pid;
	sleeper(0.1);
	kill 9,$pid;
	sleeper(0.1);
	waitpid($pid, 1);
# It is important to waitpid on your child process,  
# otherwise zombies could be created. 
}	
}

