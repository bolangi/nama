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

	start_ecasound();


	$debug and print "reading config file\n";
	if ($opts{d}){
		print "found command line project_root flag\n";
		$project_root = $opts{d};
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

	# start jack.plumbing daemon
	# if allowable and not yet started
	
	if ( 	$use_jack_plumbing				# not disabled in namarc
			and ! ($opts{J} or $opts{A})	# we are not testing   
			and $jack_running
			and $jack_plumbing

	){ system('jack.plumbing >/dev/null 2>&1 &') }

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
		$default =~ s/^project_root.*$/project_root: $ENV{HOME}\/nama/m;
		mkpath( join_path($ENV{HOME}, qw(nama untitled .wav)) );
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
--no-terminal, -T				 Don't initialize terminal

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
## configuration file

{ # OPTIMIZATION

  # we allow for the (admitted rare) possibility that
  # $project_root may change

my %proot;
sub project_root { 
	$proot{$project_root} ||= resolve_path($project_root)
}
}

sub config_file { $opts{f} ? $opts{f} : ".namarc" }

{ # OPTIMIZATION
my %wdir; 
sub this_wav_dir {
	$project_name and
	$wdir{$project_name} ||= resolve_path(
		join_path( project_root(), $project_name, q(.wav) )  
	);
}
}

sub project_dir {$project_name and join_path( project_root(), $project_name) }


sub global_config {

	# return text of config file, in the following order
	# or priority:
	#
	# 1. the file designated by the -f command line argument
	# 2. .namarc in the current project directory, i.e. ~/nama/untitled/.namarc
	# 3. .namarc in the home directory, i.e. ~/.namarc
	# 4. .namarc in the project root directory, i.e. ~/nama/.namarc
	if( $opts{f} ){
		print("reading config file $opts{f}\n");
		return read_file($opts{f});
	}
	my @search_path = (project_dir(), $ENV{HOME}, project_root() );
	my $c = 0;
		map{ 
				if (-d $_) {
					my $config = join_path($_, config_file());
					if( -f $config or -l $config){ 
						say "Found config file: $config";
						my $yml = read_file($config);
						return $yml;
					}
				}
			} ( @search_path) 
}

# sub global_config {
# 	io( join_path($ENV{HOME}, config_file()))->all;
# }

sub read_config {

	# read and process the configuration file
	#
	# use the embedded default file if none other is present
	
	$debug2 and print "&read_config\n";
	
	my $config = shift;
	my $yml = length $config > 100 ? $config : $default;
	strip_all( $yml );
	%cfg = %{  yaml_in($yml) };
	*subst = \%{ $cfg{abbreviations} }; # alias
	walk_tree(\%cfg);
	walk_tree(\%cfg); # second pass completes substitutions
	assign_var( \%cfg, @config_vars);
	$project_root = $opts{d} if $opts{d};
	$project_root = expand_tilde($project_root);

}
sub walk_tree {
	#$debug2 and print "&walk_tree\n";
	my $ref = shift;
	map { substitute($ref, $_) } 
		grep {$_ ne q(abbreviations)} 
			keys %{ $ref };
}
sub substitute{
	my ($parent, $key)  = @_;
	my $val = $parent->{$key};
	#$debug and print qq(key: $key val: $val\n);
	ref $val and walk_tree($val)
		or map{$parent->{$key} =~ s/$_/$subst{$_}/} keys %subst;
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

 	::Mark::initialize();
	::Fade::initialize();
	::Edit::initialize();
	
	# volume settings
	
	%old_vol = ();

	# $is_armed = 0;
	
	$old_snapshot = {};
	$preview = $initial_user_mode;
	$mastering_mode = 0;
	$saved_version = 0; 
	
	%bunch = ();	
	
	::Bus->initialize();
	create_system_buses();
	$this_bus = 'Main';
	::Track->initialize();

	%inputs = %outputs = ();
	
	%wav_info = ();
	
	$edit_mode = 0;
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
	$debug and print "name: $name, ch_r: $ch_r, ch_m: $ch_m\n";
	
	say ("$name: track name already in use. Skipping."), return 
		if $::Track::by_name{$name};
	say ("$name: reserved track name. Skipping"), return
	 	if grep $name eq $_, @mastering_track_names; 

	my $track = ::Track->new(
		name => $name,
		@params
	);
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


	initialize_chain_setup_vars();
	local $@; # don't propagate errors
		# NOTE: it would be better to use try/catch
	track_memoize(); 			# freeze track state 

	# generate_setup_try() gets the @_ passed to generate_setup()
	my $success = eval { &generate_setup_try }; 
	remove_temporary_tracks();  # cleanup
	track_unmemoize(); 			# unfreeze track state
	$this_track = $old_this_track;
	if ($@){
		say("error caught while generating setup: $@");
		initialize_chain_setup_vars() unless $debug;
		return
	}
	$success
}
sub generate_setup_try {  # TODO: move operations below to buses
	$debug2 and print "&generate_setup_try\n";

	# in an ideal CS world, all of the following routing
	# routines (add_paths_for_*) would be accomplished by
	# the track or bus itself, rather than the Hand of God, as
	# appears below.
	#
	# On the other hand (or Hand!), one can't complain if
	# the Hand of God happens to be doing exactly the
	# right things. :-)

	my $automix = shift; # route Master to null_out if present
	add_paths_for_main_tracks();
	$debug and say "The graph is:\n$g";
	add_paths_for_recording();
	$debug and say "The graph is:\n$g";
	add_paths_for_aux_sends();
	$debug and say "The graph is:\n$g";
	map{ $_->apply() } grep{ (ref $_) =~ /Send|Sub/ } ::Bus::all();
	$debug and say "The graph is:\n$g";
	add_paths_from_Master(); # do they affect automix?
	$debug and say "The graph is:\n$g";

	# re-route Master to null for automix
	if( $automix){
		$g->delete_edges(map{@$_} $g->edges_from('Master')); 
		$g->add_edge(qw[Master null_out]);
		$debug and say "The graph is:\n$g";
	}
	add_paths_for_mixdown_handling();
	$debug and say "The graph is:\n$g";
	prune_graph();
	$debug and say "The graph is:\n$g";

	::Graph::expand_graph($g); 

	$debug and say "The expanded graph is:\n$g";

	# insert handling
	::Graph::add_inserts($g);

	$debug and say "The expanded graph with inserts is\n$g";

	# create IO lists %inputs and %outputs

	if ( process_routing_graph() ){
		write_chains(); 
		1
	} else { 
		say("No tracks to record or play.");
		0
	}
}
sub remove_temporary_tracks {
	$debug2 and say "&remove_temporary_tracks";
	map { $_->remove  } grep{ $_->group eq 'Temp'} ::Track::all();
	$this_track = $old_this_track;
}
sub initialize_chain_setup_vars {

	@io = (); 			# IO object list
	$g = Graph->new(); 	
	%inputs = %outputs = %post_input = %pre_output = ();
	@input_chains = @output_chains = @post_input = @pre_output = ();
	undef $chain_setup;
	reset_aux_chain_counter();
	$length = 0;
	{no autodie; unlink setup_file()}
}
sub add_paths_for_main_tracks {
	$debug2 and say "&add_paths_for_main_tracks";
	map{ 

		# connect signal sources to tracks
		
		my @path = $_->input_path;
		#say "Main bus track input path: @path";
		$::g->add_path(@path) if @path;

		# connect tracks to Master
		
		$::g->add_edge($_->name, 'Master'); 

	} 	
		grep{ 1 unless $preview eq 'doodle'
			 and $_->rec_status eq 'MON' } # exclude MON tracks in doodle mode	
		grep{ $_->rec_status ne 'OFF' }    # exclude OFF tracks
		map{$tn{$_}} 	                   # convert to Track objects
		$main->tracks;                     # list of Track names

}

sub add_paths_for_recording {
	$debug2 and say "&add_paths_for_recording";
	return if $preview; # don't record during preview modes

	# get list of REC-status tracks to record
	
	my @tracks = grep{ 
			(ref $_) !~ /Slave/  						# don't record slave tracks
			and not $_->group =~ /null|Mixdown|Temp/ 	# nor these groups
			and not $_->rec_defeat        				# nor rec-defeat tracks
			and $_->rec_status eq 'REC' 
	} ::Track::all();
	map{ 

		# Track input from a WAV, JACK client, or soundcard
		#
		# We record 'raw' signal, as per docs and design

		if( $_->source_type !~ /track|bus|loop/ ){
		
			# create temporary track for rec_file chain

			# we do this because the path doesn't
			# include the original track.
			#
			# but why not supply the track as 
			# an edge attribute, then the source
			# and output info can be provided 
			# that way.

			# Later, we will rewrite it that way

			$debug and say "rec file link for $_->name";	
			my $name = $_->name . '_rec_file';
			my $anon = ::SlaveTrack->new( 
				target => $_->name,
				rw => 'OFF',
				group => 'Temp',
				name => $name);

			# connect IO
			
			$g->add_path(input_node($_->source_type), $name, 'wav_out');

			# set chain_id to R3 (if original track is 3) 
			$g->set_vertex_attributes($name, { 
				chain_id => 'R'.$_->n,
				mono_to_stereo => '', # override 
			});

		} elsif ($_->source_type =~ /bus|track/) {

			# for tracks with identified (track|bus) input

			# cache_tracks/merge_edits has its own logic
			# therefore these connections (triggered from
			# generate_setup()) will not affect AFAIK
			# any other recording scenario

			# special case, record 'cooked' signal

			# generally a sub bus 
			# - has 'rec_defeat' set (therefore doesn't reach here)
			# - receives a stereo input
			# - mix track width is set to stereo (default)

			my @edge = ($_->name, 'wav_out'); # cooked signal

			$g->add_path(@edge); 

			# set chain_id to R3 (if original track is 3) 

			$g->set_edge_attributes(@edge, { 
				chain_id => 'R'.$_->n,
			});
			
			# if this path is left unconnected, 
			# i.e. track gets no input		
			# it will be removed by prune_graph()
			
			# to record raw:
			
			# source_type: loop
			# source_id:   loop,track_name_in

			# but for WAV to contain content, 
			# we need to guarantee that track_name as
			# an input
		}


	} @tracks;
}

sub input_node { $_[0].'_in' }
sub output_node {$_[0].'_out'}
	

sub add_paths_for_aux_sends {
	$debug2 and say "&add_paths_for_aux_sends";

	map {  add_path_for_one_aux_send( $_ ) } 
	grep { (ref $_) !~ /Slave/ 
			and $_->group !~ /Mixdown|Master/
			and $_->send_type 
			and $_->rec_status ne 'OFF' } ::Track::all();
}
sub add_path_for_one_aux_send {
	my $track = shift;
		my @e = ($track->name, output_node($track->send_type));
		$g->add_edge(@e);
		 $g->set_edge_attributes(@e,
			  {	track => $track->name,
				# force stereo output width
				width => 2,
				chain_id => 'S'.$track->n,});
}

sub add_paths_from_Master {
	$debug2 and say "&add_paths_from_Master";

	if ($mastering_mode){
		$g->add_path(qw[Master Eq Low Boost]);
		$g->add_path(qw[Eq Mid Boost]);
		$g->add_path(qw[Eq High Boost]);
	}
	$g->add_path($mastering_mode ?  'Boost' : 'Master',
			output_node($tn{Master}->send_type)) if $main_out;
 

}
sub add_paths_for_mixdown_handling {
	$debug2 and say "&add_paths_for_mixdown_handling";

	if ($tn{Mixdown}->rec_status eq 'REC'){
		my @p = (($mastering_mode ? 'Boost' : 'Master'), ,'Mixdown', 'wav_out');
		$g->add_path(@p);
		$g->set_vertex_attributes('Mixdown', {
		  	format		=> signal_format($mix_to_disk_format,$tn{Mixdown}->width),
		  	chain_id	=> "Mixdown" },
		); 
		# no effects will be applied because effects are on chain 2
												 
	# Mixdown handling - playback
	
	} elsif ($tn{Mixdown}->rec_status eq 'MON'){
			my @e = qw(wav_in Mixdown soundcard_out);
			$g->add_path(@e);
			$g->set_vertex_attributes('Mixdown', {
				send_type	=> $tn{Master}->send_type,
				send_id		=> $tn{Master}->send_id,
				chain			=> "Mixdown" }); 
		# no effects will be applied because effects are on chain 2
	}
}
sub prune_graph {
	$debug2 and say "&prune_graph";
	# prune graph: remove tracks lacking inputs or outputs
	::Graph::remove_out_of_bounds_tracks($g) if edit_mode();
	::Graph::recursively_remove_inputless_tracks($g);
	::Graph::recursively_remove_outputless_tracks($g); 
}
# new object based dispatch from routing graph
	
sub process_routing_graph {
	$debug2 and say "&process_routing_graph";
	@io = map{ dispatch($_) } $g->edges;
	$debug and map $_->dumpp, @io;
	map{ $inputs{$_->ecs_string} //= [];
		push @{$inputs{$_->ecs_string}}, $_->chain_id;
		$post_input{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} grep { $_->direction eq 'input' } @io;
	map{ $outputs{$_->ecs_string} //= [];
		push @{$outputs{$_->ecs_string}}, $_->chain_id;
		$pre_output{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} grep { $_->direction eq 'output' } @io;
	no warnings 'numeric';
	my @in_keys = values %inputs;
	my @out_keys = values %outputs;
	use warnings 'numeric';
	%is_ecasound_chain = map{ $_, 1} map{ @$_ } values %inputs;

	# sort entries into an aesthetic order

	%inputs = reverse %inputs;	
	%outputs = reverse %outputs;	
	@input_chains = sort map {'-a:'.join(',',sort by_chain @$_)." $inputs{$_}"} @in_keys;
	@output_chains = sort map {'-a:'.join(',',sort by_chain @$_)." $outputs{$_}"} @out_keys;
	@post_input = sort by_index map{ "-a:$_ $post_input{$_}"} keys %post_input;
	@pre_output = sort by_index map{ "-a:$_ $pre_output{$_}"} keys %pre_output;
	@input_chains + @output_chains # to sense empty chain setup
}
{ my ($m,$n,$o,$p,$q,$r);
sub by_chain {
	($m,$n,$o) = $a =~ /(\D*)(\d+)(\D*)/ ;
	($p,$q,$r) = $b =~ /(\D*)(\d+)(\D*)/ ;
	if ($n != $q){ $n <=> $q }
	elsif ( $m ne $p){ $m cmp $p }
	else { $o cmp $r }
}
}
sub by_index {
	my ($i) = $a =~ /(\d+)/;
	my ($j) = $b =~ /(\d+)/;
	$i <=> $j
}

sub non_track_dispatch {

	# loop -> loop
	#	
	# assign chain_id to edge based on chain_id of left-side loop's
	# corresponding track:
	#	
	# hihat_out -- J7a -> Master_in
	#
	# soundcard_in -> wav_out (rec_file)
	#
	# currently handled using an anonymous track
	#
	# we expect edge attributes 
	# to have been provided for handling this. 

	# loop -> soundcard_out
	#
	# track7-soundcard_out as aux_send will have chain id S7
	# that will be transferred by expand_graph() to 
	# the new edge, loop-soundcard-out

	# we will issue two IO objects, one for the chain input
	# fragment, one for the chain output
	
	
	my $edge = shift;
	$debug and say "non-track dispatch: ",join ' -> ',@$edge;
	my $eattr = $g->get_edge_attributes(@$edge) // {};
	$debug and say "found edge attributes: ",yaml_out($eattr) if $eattr;

	my $vattr = $g->get_vertex_attributes($edge->[0]) // {};
	$debug and say "found vertex attributes: ",yaml_out($vattr) if $vattr;

	if ( ! $eattr->{chain_id} and ! $vattr->{chain_id} ){
		my $n = $eattr->{n} || $vattr->{n};
		$eattr->{chain_id} = jumper_count($n);
	}
	my @direction = qw(input output);
	map{ 
		my $direction = shift @direction;
		my $class = ::IO::get_class($_, $direction);
		my $attrib = {%$vattr, %$eattr};
		$attrib->{endpoint} //= $_ if ::Graph::is_a_loop($_); 
		$debug and say "non-track: $_, class: $class, chain_id: $attrib->{chain_id},",
 			"device_id: $attrib->{device_id}";
		$class->new($attrib ? %$attrib : () ) } @$edge;
		# we'd like to $class->new(override($edge->[0], $edge)) } @$edge;
}

{ 
### counter for jumper chains 
#
#   sequence: J1 J1a J1b J1c, J2, J3, J4, J4d, J4e

my %used;
my $counter;
my $prefix = 'J';
reset_aux_chain_counter();
  
sub reset_aux_chain_counter {
	%used = ();
	$counter = 'a';
}
sub jumper_count {
	my $track_index = shift;
	my $try1 = $prefix . $track_index;
	$used{$try1}++, return $try1 unless $used{$try1};
	$try1 . $counter++;
}
}
	

sub dispatch { # creates an IO object from a graph edge
my $edge = shift;
	return non_track_dispatch($edge) if not grep{ $tn{$_} } @$edge ;
	$debug and say 'dispatch: ',join ' -> ',  @$edge;
	my($name, $endpoint, $direction) = decode_edge($edge);
	$debug and say "name: $name, endpoint: $endpoint, direction: $direction";
	my $track = $tn{$name};
	my $class = ::IO::get_class( $endpoint, $direction );
		# we need the $direction because there can be 
		# edges to and from loop,Master_in
	my @args = (track => $name,
			endpoint => $endpoint, # for loops
				chain_id => $tn{$name}->n, # default
				override($name, $edge));   # priority: edge > node
	#say "dispatch class: $class";
	$class->new(@args);
}
sub decode_edge {
	# assume track-endpoint or endpoint-track
	# return track, endpoint
	my ($a, $b) = @{$_[0]};
	#say "a: $a, b: $b";
	my ($name, $endpoint) = $tn{$a} ? @{$_[0]} : reverse @{$_[0]} ;
	my $direction = $tn{$a} ? 'output' : 'input';
	($name, $endpoint, $direction)
}
sub override {
	# data from edges has priority over data from vertexes
	# we specify $name, because it could be left or right 
	# vertex
	$debug2 and say "&override";
	my ($name, $edge) = @_;
	(override_from_vertex($name), override_from_edge($edge))
}
	
sub override_from_vertex {
	my $name = shift;
		warn("undefined graph\n"), return () unless (ref $g) =~ /Graph/;
		my $attr = $g->get_vertex_attributes($name);
		$attr ? %$attr : ();
}
sub override_from_edge {
	my $edge = shift;
		warn("undefined graph\n"), return () unless (ref $g) =~ /Graph/;
		my $attr = $g->get_edge_attributes(@$edge);
		$attr ? %$attr : ();
}
							
sub write_chains {

	$debug2 and print "&write_chains\n";

	## write general options
	
	my $globals = $ecasound_globals_default;

	# use realtime globals if they exist and we are
	# recording to a non-mixdown file
	
	$globals = $ecasound_globals_realtime
		if $ecasound_globals_realtime 
			and grep{ ! /Mixdown/} really_recording();
			# we assume there exists latency-sensitive monitor output 
			# when recording
			
	my $ecs_file = join "\n\n", 
					"# ecasound chainsetup file",
					"# general",
					$globals, 
					"# audio inputs",
					join("\n", @input_chains), "";
	$ecs_file .= join "\n\n", 
					"# post-input processing",
					join("\n", @post_input), "" if @post_input;				
	$ecs_file .= join "\n\n", 
					"# pre-output processing",
					join("\n", @pre_output), "" if @pre_output;
	$ecs_file .= join "\n\n", 
					"# audio outputs",
					join("\n", @output_chains), "";
	$debug and print "ECS:\n",$ecs_file;
	open my $setup, ">", setup_file();
	print $setup $ecs_file;
	close $setup;
	$chain_setup = $ecs_file;

}

sub signal_format {
	my ($template, $channel_count) = @_;
	$template =~ s/N/$channel_count/;
	my $format = $template;
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
{ my $old_edit_mode;
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
		 or $edit_mode != $old_edit_mode
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
	$old_edit_mode = $edit_mode;

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
	disconnect_jack_ports_list();
	connect_jack_ports_list();
	transport_status() unless $quiet;
	$ui->flash_ready();
	#print eval_iam("fs");
	1;
	
}

{ 
  my $plumbing_tag = q(BEGIN NAMA CONNECTIONS LIST);
  my $plumbing_header = qq(;### $plumbing_tag
;## The following lines are automatically generated.
;## DO NOT place any connection data below this line!!
;
); 

sub connect_jack_ports_list {

	# skip if we can? 
	#
	# no, because stale connections remain, we
	# have to rewrite every time... if jack.plumbing
	#
	local $debug = 1;
	
	my $configure_jack_plumbing =  # boolean
		(		
			$use_jack_plumbing 
		and $jack_running
		and $jack_plumbing
		);

	#my $dis = shift;
	my $dis;
	my $fh;

	# read user data from ~/.jack.plumbing if we need it
	
	if( $configure_jack_plumbing){


		$debug and say "jack plumbing is running: we will configure";
		
		my $cmd = "cat ".jack_plumbing_conf();
		my $user_plumbing = io(jack_plumbing_conf())->all
			if -f -r jack_plumbing_conf();

		# keep user data, deleting below tag

		$user_plumbing =~ s/;[# ]*$plumbing_tag.*//gs;
	
		open $fh, ">", jack_plumbing_conf();
		
		print $fh $user_plumbing, $plumbing_header;
	}
	map{  
		my $track = $_; 
 		my $name = $track->name;
 		my $dest = "ecasound:$name\_in_";
		my $file = join_path(project_root(), $track->source_id);
		if (! -e -r $file){ say $track->name, 
				": JACK ports file $file not found. No sources connected.";
	  	} else {
			my $line_number = 0;
			my @lines = io($file)->slurp;
			for my $port (@lines){   
				# $port is the source port name
				chomp $port;
				$debug and say "port file $file, line $line_number, port $port";
				
				# setup shell command
				
				if(! $jack{$port}){
					say $track->name, qq(: port "$port" not found. Skipping.);
					next
				}
			
				# ecasound port suffix	
				
				my $ecasound_port_number = $track->width == 1
					?  1 
					: $line_number % $track->width + 1;

				if( $configure_jack_plumbing ){

					my $ecasound_port = $dest .  $ecasound_port_number;
					my $config_line = join " ", 'connect', quote($port), quote($ecasound_port);
					$debug and print $fh "($config_line)\n";

				} else { # fall back to jack_connect
					# quote port in case it contains spaces
					my $p = $port =~ / / ? qq("$port") : $port	;

					# command: jack_connect Horgand_1:1 ecasound:synth_in_
					my $cmd = q(jack_).$dis.qq(connect $p $dest);

					$cmd .= $ecasound_port_number;
					$debug and say $cmd;
					system $cmd;
				}
				$line_number++;
			};
		}
 	 } grep{ $_->source_type eq 'jack_ports_list' 
				and $_->rec_status eq 'REC' } ::Track::all();

	 close $fh if $configure_jack_plumbing;
}
}
sub quote { qq("$_[0]")}

sub disconnect_jack_ports_list { 
	#connect_jack_ports_list('dis')  # probably we can go without this
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
	limit_processing_time() if mixing_only() or edit_mode();
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
	eval_iam('stop');	
	disable_length_timer();
	if ( ! $quiet ){
		sleeper(0.5);
		engine_status(current_position(),2,0);
	}
	unmute();
	stop_heartbeat();
	$ui->project_label_configure(-background => $old_bg);
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
	engine_status(current_position(),2,1),revise_prompt(),stop_heartbeat()
		#if $status =~ /finished|error|stopped/;
		if $status =~ /finished|error/;
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
 	$event_id{processing_time} = AE::timer($length, 0, \&stop_transport);
}
sub disable_length_timer {
	$event_id{processing_time} = undef; 
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
		reconfigure_engine();
	}
}
sub post_rec_configure {

		$ui->global_version_buttons(); # recreate
		map{ $_->set(rw => 'MON')} ::Bus::all();
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

## effect functions

sub add_effect {
	
	$debug2 and print "&add_effect\n";
	
	my %p 			= %{shift()};
	my ($n,$code,$parent_id,$id,$parameter,$values) =
		@p{qw( chain type parent_id cop_id parameter values)};
	my $i = $effect_i{$code};

	# don't create an existing vol or pan effect
	
	return if $id and ($id eq $ti{$n}->vol 
				or $id eq $ti{$n}->pan);   

	$id = cop_add(\%p); 
	%p = ( %p, cop_id => $id); # replace chainop id
	$ui->add_effect_gui(\%p) unless $ti{$n}->hide;
	if( valid_engine_setup() ){
		my $er = engine_running();
		$ti{$n}->mute if $er;
		apply_op($id);
		$ti{$n}->unmute if $er;
	}
	$id;

}
sub modify_effect {
	my ($op_id, $parameter, $sign, $value) = @_;
		# $parameter: zero based
	my $cop = $cops{$op_id} 
		or print("$op_id: non-existing effect id. Skipping\n"), return; 
	my $code = $cop->{type};
	my $i = effect_index($code);
	defined $i or croak "undefined effect code for $op_id: ",yaml_out($cop);
	my $parameter_count = scalar @{ $effects[$i]->{params} };
	#print "op_id: $op_id, code: ",$cops{$op_id}->{type}," parameter count: $parameter_count\n";

	print("$op_id: effect does not exist, skipping\n"), return 
		unless $cops{$op_id};
	print("$op_id: parameter (", $parameter + 1, ") out of range, skipping.\n"), return 
		unless ($parameter >= 0 and $parameter < $parameter_count);
		my $new_value = $value; 
		if ($sign) {
			$new_value = 
 			eval (join " ",
 				$copp{$op_id}->[$parameter], 
 				$sign,
 				$value);
		}
	$debug and print "id $op_id p: $parameter, sign: $sign value: $value\n";
	effect_update_copp_set( 
		$op_id, 
		$parameter, 
		$new_value);
}
sub modify_multiple_effects {
	my ($op_ids, $parameters, $sign, $value) = @_;
	map{ my $op_id = $_;
		map{ 	my $parameter = $_;
				$parameter--; # convert to zero-base
				modify_effect($op_id, $parameter, $sign, $value);
		} @$parameters
	} @$op_ids;
}

sub remove_effect { 
	@_ = discard_object(@_);
	$debug2 and print "&remove_effect\n";
	my $id = shift;
	carp("$id: does not exist, skipping...\n"), return unless $cops{$id};
	my $n = $cops{$id}->{chain};
		
	my $parent = $cops{$id}->{belongs_to} ;
	$debug and print "id: $id, parent: $parent\n";

	my $object = $parent ? q(controller) : q(chain operator); 
	$debug and print qq(ready to remove $object "$id" from track "$n"\n);

	$ui->remove_effect_gui($id);

		# recursively remove children
		$debug and print "children found: ", join "|",@{$cops{$id}->{owns}},"\n";
		map{remove_effect($_)}@{ $cops{$id}->{owns} } 
			if defined $cops{$id}->{owns};
;

	if ( ! $parent ) { # i am a chain operator, have no parent
		remove_op($id);

	} else {  # i am a controller

	# remove the controller
 			
 		remove_op($id);

	# i remove ownership of deleted controller

		$debug and print "parent $parent owns list: ", join " ",
			@{ $cops{$parent}->{owns} }, "\n";

		@{ $cops{$parent}->{owns} }  =  grep{ $_ ne $id}
			@{ $cops{$parent}->{owns} } ; 
		$cops{$id}->{belongs_to} = undef;
		$debug and print "parent $parent new owns list: ", join " ",
			@{ $cops{$parent}->{owns} } ,$/;

	}
	# remove id from track object

	$ti{$n}->remove_effect( $id ); 
	delete $cops{$id}; # remove entry from chain operator list
	delete $copp{$id}; # remove entry from chain operator parameters list
}


sub nama_effect_index { # returns nama chain operator index
						# does not distinguish op/ctrl
	my $id = shift;
	my $n = $cops{$id}->{chain};
	$debug and print "id: $id n: $n \n";
	$debug and print join $/,@{ $ti{$n}->ops }, $/;
		for my $pos ( 0.. scalar @{ $ti{$n}->ops } - 1  ) {
			return $pos if $ti{$n}->ops->[$pos] eq $id; 
		};
}
sub ecasound_effect_index { 
	my $id = shift;
	my $n = $cops{$id}->{chain};
	my $opcount;  # one-based
	$debug and print "id: $id n: $n \n",join $/,@{ $ti{$n}->ops }, $/;
	for my $op (@{ $ti{$n}->ops }) { 
			# increment only for ops, not controllers
			next if $cops{$op}->{belongs_to};
			++$opcount;
			last if $op eq $id
	} 
	$offset{$n} + $opcount;
}



sub remove_op {
	# remove chain operator from Ecasound engine

	$debug2 and print "&remove_op\n";

	# only if engine is configured
	return unless eval_iam('cs-connected') and eval_iam('cs-is-valid');

	my $id = shift;
	my $n = $cops{$id}->{chain};
	my $index;
	my $parent = $cops{$id}->{belongs_to}; 

	# select chain
	
	return unless ecasound_select_chain($n);

	# deal separately with controllers and chain operators

	if ( !  $parent ){ # chain operator
		$debug and print "no parent, assuming chain operator\n";
	
		$index = ecasound_effect_index( $id );
		$debug and print "ops list for chain $n: @{$ti{$n}->ops}\n";
		$debug and print "operator id to remove: $id\n";
		$debug and print "ready to remove from chain $n, operator id $id, index $index\n";
		$debug and eval_iam("cs");
		eval_iam("cop-select ". ecasound_effect_index($id) );
		$debug and print "selected operator: ", eval_iam("cop-selected"), $/;
		eval_iam("cop-remove");
		$debug and eval_iam("cs");

	} else { # controller

		$debug and print "has parent, assuming controller\n";

		my $ctrl_index = ctrl_index($id);
		$debug and print eval_iam("cs");
		eval_iam("cop-select ".  ecasound_effect_index(root_parent($id)));
		$debug and print "selected operator: ", eval_iam("cop-selected"), $/;
		eval_iam("ctrl-select $ctrl_index");
		eval_iam("ctrl-remove");
		$debug and print eval_iam("cs");
	}
}


# Track sax effects: A B C GG HH II D E F
# GG HH and II are controllers applied to chain operator C
# 
# to remove controller HH:
#
# for Ecasound, chain op index = 3, 
#               ctrl index     = 2
#                              = nama_effect_index HH - nama_effect_index C 
#               
#
# for Nama, chain op array index 2, 
#           ctrl arrray index = chain op array index + ctrl_index
#                             = effect index - 1 + ctrl_index 
#
#

sub root_parent { 
	my $id = shift;
	my $parent = $cops{$id}->{belongs_to};
	carp("$id: has no parent, skipping...\n"),return unless $parent;
	my $root_parent = $cops{$parent}->{belongs_to};
	$parent = $root_parent || $parent;
	$debug and print "$id: is a controller-controller, root parent: $parent\n";
	$parent;
}

sub ctrl_index { 
	my $id = shift;
	nama_effect_index($id) - nama_effect_index(root_parent($id));

}
sub cop_add {
	$debug2 and print "&cop_add\n";
	my $p = shift;
	my %p = %$p;
	$debug and say yaml_out($p);

	# return an existing id 
	return $p{cop_id} if $p{cop_id};
	

	# use an externally provided (magical) id or the
	# incrementing counter
	
	my $id = $magical_cop_id || $cop_id;

	# make entry in %cops with chain, code, display-type, children

	my ($n, $type, $parent_id, $parameter)  = 
		@p{qw(chain type parent_id parameter)};
	my $i = $effect_i{$type};


	$debug and print "Issuing a cop_id for track $n: $id\n";

	$cops{$id} = {chain => $n, 
					  type => $type,
					  display => $effects[$i]->{display},
					  owns => [] }; 

	$p->{cop_id} = $id;

	# set defaults
	
	if (! $p{values}){
		my @vals;
		$debug and print "no settings found, loading defaults if present\n";
		my $i = $effect_i{ $cops{$id}->{type} };
		
		# don't initialize first parameter if operator has a parent
		# i.e. if operator is a controller
		
		for my $p ($parent_id ? 1 : 0..$effects[$i]->{count} - 1) {
		
			my $default = $effects[$i]->{params}->[$p]->{default};
			push @vals, $default;
		}
		$debug and print "copid: $id defaults: @vals \n";
		$copp{$id} = \@vals;
	}

	if ($parent_id) {
		$debug and print "parent found: $parent_id\n";

		# store relationship
		$debug and print "parent owns" , join " ",@{ $cops{$parent_id}->{owns}}, "\n";

		push @{ $cops{$parent_id}->{owns}}, $id;
		$debug and print join " ", "my attributes:", (keys %{ $cops{$id} }), "\n";
		$cops{$id}->{belongs_to} = $parent_id;
		$debug and print join " ", "my attributes again:", (keys %{ $cops{$id} }), "\n";
		$debug and print "parameter: $parameter\n";

		# set fx-param to the parameter number, which one
		# above the zero-based array offset that $parameter represents
		
		$copp{$id}->[0] = $parameter + 1; 
		
 		# find position of parent and insert child immediately afterwards

 		my $end = scalar @{ $ti{$n}->ops } - 1 ; 
 		for my $i (0..$end){
 			splice ( @{$ti{$n}->ops}, $i+1, 0, $id ), last
 				if $ti{$n}->ops->[$i] eq $parent_id
 		}
	}
	else { push @{$ti{$n}->ops }, $id; } 

	# set values if present
	
	# ugly! The passed values ref may be used for multiple
	# instances, so we copy it here [ @$values ]
	
	$copp{$id} = [ @{$p{values}} ] if $p{values};

	# make sure the counter $cop_id will not occupy an
	# already used value
	
	while( $cops{$cop_id}){$cop_id++};

	$id;
}

sub effect_update_copp_set {
	my ($id, $param, $val) = @_;
	effect_update( @_ );
	$copp{$id}->[$param] = $val;
}
	

sub effect_update {

	# update the parameters of the Ecasound chain operator
	# referred to by a Nama operator_id
	
	#$debug2 and print "&effect_update\n";

	return unless valid_engine_setup();
	#my $es = eval_iam("engine-status");
	#$debug and print "engine is $es\n";
	#return if $es !~ /not started|stopped|running/;

	my ($id, $param, $val) = @_;
	$param++; # so the value at $p[0] is applied to parameter 1
	carp("$id: effect not found. skipping...\n"), return unless $cops{$id};
	my $chain = $cops{$id}{chain};
	return unless $is_ecasound_chain{$chain};

	$debug and print "chain $chain id $id param $param value $val\n";

	# $param is zero-based. 
	# %copp is  zero-based.

 	$debug and print join " ", @_, "\n";	

	my $old_chain = eval_iam('c-selected') if valid_engine_setup();
	ecasound_select_chain($chain);

	# update Ecasound's copy of the parameter
	if( is_controller($id)){
		my $i = ecasound_controller_index($id);
		$debug and print 
		"controller $id: track: $chain, index: $i param: $param, value: $val\n";
		eval_iam("ctrl-select $i");
		eval_iam("ctrlp-select $param");
		eval_iam("ctrlp-set $val");
	}
	else { # is operator
		my $i = ecasound_operator_index($id);
		$debug and print 
		"operator $id: track $chain, index: $i, offset: ",
		$offset{$chain}, " param $param, value $val\n";
		eval_iam("cop-select ". ($offset{$chain} + $i));
		eval_iam("copp-select $param");
		eval_iam("copp-set $val");
	}
	ecasound_select_chain($old_chain);
}

sub sync_effect_parameters {
	# when a controller changes an effect parameter
	# the effect state can differ from the state in
	# %copp, Nama's effect parameter store
	#
	# this routine syncs them in prep for save_state()
	
 	return unless valid_engine_setup();
	my $old_chain = eval_iam('c-selected');
	map{ sync_one_effect($_) } ops_with_controller();
	eval_iam("c-select $old_chain");
}

sub sync_one_effect {
		my $id = shift;
		my $chain = $cops{$id}{chain};
		eval_iam("c-select $chain");
		eval_iam("cop-select " . ( $offset{$chain} + ecasound_operator_index($id)));
		$copp{$id} = get_cop_params( scalar @{$copp{$id}} );
}

sub get_cop_params {
	my $count = shift;
	my @params;
	for (1..$count){
		eval_iam("copp-select $_");
		push @params, eval_iam("copp-get");
	}
	\@params
}
		
sub ops_with_controller {
	grep{ ! is_controller($_) }
	grep{ scalar @{$cops{$_}{owns}} }
	map{ @{ $_->ops } } 
	map{ $tn{$_} } 
	grep{ $tn{$_} } 
	$g->vertices;
}

sub is_controller { my $id = shift; $cops{$id}{belongs_to} }

sub ecasound_operator_index { # does not include offset
	my $id = shift;
	my $chain = $cops{$id}{chain};
	my $track = $ti{$chain};
	my @ops = @{$track->ops};
	my $controller_count = 0;
	my $position;
	for my $i (0..scalar @ops - 1) {
		$position = $i, last if $ops[$i] eq $id;
		$controller_count++ if $cops{$ops[$i]}{belongs_to};
	}
	$position -= $controller_count; # skip controllers 
	++$position; # translates 0th to chain-position 1
}
	
	
sub ecasound_controller_index {
	my $id = shift;
	my $chain = $cops{$id}{chain};
	my $track = $ti{$chain};
	my @ops = @{$track->ops};
	my $operator_count = 0;
	my $position;
	for my $i (0..scalar @ops - 1) {
		$position = $i, last if $ops[$i] eq $id;
		$operator_count++ if ! $cops{$ops[$i]}{belongs_to};
	}
	$position -= $operator_count; # skip operators
	++$position; # translates 0th to chain-position 1
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
	ecasound_select_chain($this_track->n);
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
		{no autodie 'opendir';
			opendir DIR, $dir 
				or carp("failed to open directory $dir: $!\n"), next;
		}
		push @plugins,  
			map{"$dir/$_"} 						# full path
			grep{ ! $seen{$_} and ++$seen{$_}}  # skip seen plugins
			grep{ /\.so$/} readdir DIR;			# get .so files
		closedir DIR;
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


## persistent state support

sub save_state {
	my $file = shift || $state_store_file; 
	$debug2 and print "&save_state\n";
	$saved_version = $VERSION;


	# some stuff get saved independently of our state file
	
	$debug and print "saving palette\n";
	$ui->save_palette;

	# do nothing more if only Master and Mixdown
	
	if (scalar @::Track::all == 2 ){
		print "No user tracks, skipping...\n";
		return;
	}

	print "\nSaving state as ",
	save_system_state($file), "\n";
	save_effect_chains();
	save_effect_profiles();

	# store alsa settings

	if ( $opts{a} ) {
		my $file = $file;
		$file =~ s/\.yml$//;
		print "storing ALSA settings\n";
		print qx(alsactl -f $file.alsa store);
	}
}

sub save_system_state {

	my $file = shift;

	# save stuff to state file

	$file = join_path(&project_dir, $file) unless $file =~ m(/); 
	$file =~ /\.yml$/ or $file .= '.yml';	

	sync_effect_parameters(); # in case a controller has made a change

	# remove null keys in %cops and %copp
	
	delete $cops{''};
	delete $copp{''};

	# prepare tracks for storage
	
	$this_track_name = $this_track->name;

	@tracks_data = (); # zero based, iterate over these to restore

	$debug and print "copying tracks data\n";

	map { push @tracks_data, $_->hashref } ::Track::all();
	# print "found ", scalar @tracks_data, "tracks\n";

	# delete unused fields
	map { my $t = $_;
				map{ delete $t->{$_} } 
					qw(ch_r ch_m source_select send_select jack_source jack_send);
	} @tracks_data;

	$debug and print "copying bus data\n";
	@bus_data = (); # 
	map{ push @bus_data, $_->hashref } ::Bus::all();

	# prepare inserts data for storage
	
	$debug and print "copying inserts data\n";
	@inserts_data = ();
	while (my $k = each %::Insert::by_index ){ 
		push @inserts_data, $::Insert::by_index{$k}->hashref;
	}

	# prepare marks data for storage (new Mark objects)

	@marks_data = ();
	$debug and print "copying marks data\n";
	map { push @marks_data, $_->hashref } ::Mark::all();

	# prepare fade data for storage
	
	@fade_data = ();
	while (my $k = each %::Fade::by_index ){ 
		push @fade_data, $::Fade::by_index{$k}->hashref;
	}

	@edit_data = ();
	while (my $k = each %::Edit::by_name ){
		push @edit_data, $::Edit::by_name{$k}->hashref;
	}

	# save history -- 50 entries, maximum

	my @history = $::term->GetHistory;
	my %seen;
	@command_history = ();
	map { push @command_history, $_ 
			unless $seen{$_}; $seen{$_}++ } @history;
	my $max = scalar @command_history;
	$max = 50 if $max > 50;
	@command_history = @command_history[-$max..-1];
	$debug and print "serializing\n";

	serialize(
		file => $file, 
		format => 'yaml',
		vars => \@persistent_vars,
		class => '::',
		);


	$file
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

sub save_effect_chains { # if they exist
	my $file = shift || $effect_chain_file;
	if (keys %effect_chain){
		serialize (
			file => join_path(project_root(), $file),
			format => 'yaml',
			vars => [ qw( %effect_chain ) ],
			class => '::');
	}
}
sub save_effect_profiles { # if they exist
	my $file = shift || $effect_profile_file;
	if (keys %effect_profile){
		serialize (
			file => join_path(project_root(), $file),
			format => 'yaml',
			vars => [ qw( %effect_profile ) ],
			class => '::');
	}
}
sub restore_effect_chains {

	my $file = join_path(project_root(), $effect_chain_file);
	return unless -e $file;

	# don't overwrite them if already present
	assign_var($file, qw(%effect_chain)) unless keys %effect_chain
}
sub restore_effect_profiles {

	my $file = join_path(project_root(), $effect_profile_file);
	return unless -e $file;

	# don't overwrite them if already present
	assign_var($file, qw(%effect_profile)) unless keys %effect_profile; 
}
sub assign_var {
	my ($source, @vars) = @_;
	assign_vars(
				source => $source,
				vars   => \@vars,
		#		format => 'yaml', # breaks
				class => '::');
}
sub restore_state {
	$debug2 and print "&restore_state\n";
	my $file = shift;
	$file = $file || $state_store_file;
	$file = join_path(project_dir(), $file)
		unless $file =~ m(/);
	$file .= ".yml" unless $file =~ /yml$/;
	! -f $file and (print "file not found: $file\n"), return;
	$debug and print "using file: $file\n";
	
	my $yaml = io($file)->all;

	# remove empty key hash lines # fixes YAML::Tiny bug
	$yaml = join $/, grep{ ! /^\s*:/ } split $/, $yaml;

	# rewrite obsolete null hash/array substitution
	$yaml =~ s/~NULL_HASH/{}/g;
	$yaml =~ s/~NULL_ARRAY/[]/g;

	# rewrite %cops 'owns' field to []
	
	$yaml =~ s/owns: ~/owns: []/g;

	# restore persistent variables

	assign_var($yaml, @persistent_vars );

	restore_effect_chains();
	restore_effect_profiles();

	##  print yaml_out \@groups_data; 
	# %cops: correct 'owns' null (from YAML) to empty array []
	
	# backward compatibility fixes for older projects

	if (! $saved_version ){

		# Tracker group is now called 'Main'
	
		map{ $_->{name} = 'Main'} grep{ $_->{name} eq 'Tracker' } @groups_data;
		
		for my $t (@tracks_data){
			$t->{group} =~ s/Tracker/Main/;
			if( $t->{source_select} eq 'soundcard'){
				$t->{source_type} = 'soundcard' ;
				$t->{source_id} = $t->{ch_r}
			}
			elsif( $t->{source_select} eq 'jack'){
				$t->{source_type} = 'jack_client' ;
				$t->{source_id} = $t->{jack_source}
			}
			if( $t->{send_select} eq 'soundcard'){
				$t->{send_type} = 'soundcard' ;
				$t->{send_id} = $t->{ch_m}
			}
			elsif( $t->{send_select} eq 'jack'){
				$t->{send_type} = 'jack_client' ;
				$t->{send_id} = $t->{jack_send}
			}
		}
	}
	if( $saved_version < 0.9986){
	
		map { 	# store insert without intermediate array

				my $t = $_;

				# use new storage format for inserts
				my $i = $t->{inserts};
				if($i =~ /ARRAY/){ 
					$t->{inserts} = scalar @$i ? $i->[0] : {}  }
				
				# initialize inserts effect_chain_stack and cache_map

				$t->{inserts} //= {};
				$t->{effect_chain_stack} //= [];
				$t->{cache_map} //= {};

				# set class for Mastering tracks

				$t->{class} = '::MasteringTrack' if $t->{group} eq 'Mastering';
				$t->{class} = '::SimpleTrack' if $t->{name} eq 'Master';

				# rename 'ch_count' field to 'width'
				
				$t->{width} = $t->{ch_count};
				delete $t->{ch_count};

				# set Mixdown track width to 2
				
				$t->{width} = 2 if $t->{name} eq 'Mixdown';
				
				# remove obsolete fields
				
				map{ delete $t->{$_} } qw( 
											delay 
											length 
											start_position 
											ch_m 
											ch_r
											source_select 
											jack_source   
											send_select
											jack_send);
		}  @tracks_data;
	}

	# jack_manual is now called jack_port
	if ( $saved_version <= 1){
		map { $_->{source_type} =~ s/jack_manual/jack_port/ } @tracks_data;
	}
	if ( $saved_version <= 1.053){ # convert insert data to object
		my $n = 0;
		@inserts_data = ();
		for my $t (@tracks_data){
			my $i = $t->{inserts};
			next unless keys %$i;
			$t->{postfader_insert} = ++$n;
			$i->{class} = '::PostFaderInsert';
			$i->{n} = $n;
			$i->{wet_name} = $t->{name} . "_wet";
			$i->{dry_name} = $t->{name} . "_dry";
			delete $t->{inserts};
			delete $i->{tracks};
			push @inserts_data, $i;
		} 
	}
	if ( $saved_version <= 1.054){ 

		for my $t (@tracks_data){

			# source_type 'track' is now  'bus'
			$t->{source_type} =~ s/track/bus/;

			# convert 'null' bus to 'Null' (which is eliminated below)
			$t->{group} =~ s/null/Null/;
		}

	}

	if ( $saved_version <= 1.055){ 

	# get rid of Null bus routing
	
		map{$_->{group}       = 'Main'; 
			$_->{source_type} = 'null';
			$_->{source_id}   = 'null';
		} grep{$_->{group} eq 'Null'} @tracks_data;

	}

	if ( $saved_version <= 1.064){ 
		map{$_->{version} = $_->{active};
			delete $_->{active}}
			grep{$_->{active}}
			@tracks_data;
	}

	$debug and print "inserts data", yaml_out \@inserts_data;


	# make sure Master has reasonable output settings
	
	map{ if ( ! $_->{send_type}){
				$_->{send_type} = 'soundcard',
				$_->{send_id} = 1
			}
		} grep{$_->{name} eq 'Master'} @tracks_data;

	if ( $saved_version <= 1.064){ 

		map{ 
			my $default_list = ::IO::default_jack_ports_list($_->{name});

			if( -e join_path(project_root(),$default_list)){
				$_->{source_type} = 'jack_ports_list';
				$_->{source_id} = $default_list;
			} else { 
				$_->{source_type} = 'jack_manual';
				$_->{source_id} = ($_->{target}||$_->{name}).'_in';
			}
		} grep{ $_->{source_type} eq 'jack_port' } @tracks_data;
	}
	if ( $saved_version <= 1.067){ 

		map{ $_->{current_edit} or $_->{current_edit} = {} } @tracks_data;
		map{ 
			delete $_->{active};
			delete $_->{inserts};
			delete $_->{prefader_insert};
			delete $_->{postfader_insert};
			
			# eliminate field is_mix_track
			if ($_->{is_mix_track} ){
				 $_->{source_type} = 'bus';
				 $_->{source_id}   = undef;
			}
			delete $_->{is_mix_track};

 		} @tracks_data;
	}

	#  destroy and recreate all buses

	::Bus::initialize();	

	create_system_buses(); 

	# restore user buses
		
	map{ my $class = $_->{class}; $class->new( %$_ ) } @bus_data;

	my $main = $bn{Main};

	# bus should know its mix track
	
	$main->set( send_type => 'track', send_id => 'Master')
		unless $main->send_type;

	# restore user tracks
	
	my $did_apply = 0;

	# temporary turn on mastering mode to enable
	# recreating mastering tracksk

	my $current_master_mode = $mastering_mode;
	$mastering_mode = 1;

	map{ 
		my %h = %$_; 
		my $class = $h{class} || "::Track";
		my $track = $class->new( %h );
	} @tracks_data;

	$mastering_mode = $current_master_mode;

	# restore inserts
	
	::Insert::initialize();
	
	map{ 
		bless $_, $_->{class};
		$::Insert::by_index{$_->{n}} = $_;
	} @inserts_data;

	$ui->create_master_and_mix_tracks();

	$this_track = $tn{$this_track_name} if $this_track_name;
	set_current_bus();

	map{ 
		my $n = $_->{n};

		# create gui
		$ui->track_gui($n) unless $n <= 2;

		# restore effects
		
		for my $id (@{$ti{$n}->ops}){
			$did_apply++ 
				unless $id eq $ti{$n}->vol
					or $id eq $ti{$n}->pan;
			
			add_effect({
						chain => $cops{$id}->{chain},
						type => $cops{$id}->{type},
						cop_id => $id,
						parent_id => $cops{$id}->{belongs_to},
						});

		}
	} @tracks_data;


	#print "\n---\n", $main->dump;  
	#print "\n---\n", map{$_->dump} ::Track::all();# exit; 
	$did_apply and $ui->manifest;
	$debug and print join " ", 
		(map{ ref $_, $/ } ::Track::all()), $/;


	# restore Alsa mixer settings
	if ( $opts{a} ) {
		my $file = $file; 
		$file =~ s/\.yml$//;
		print "restoring ALSA settings\n";
		print qx(alsactl -f $file.alsa restore);
	}

	# text mode marks 
		
	map{ 
		my %h = %$_; 
		my $mark = ::Mark->new( %h ) ;
	} @marks_data;


	$ui->restore_time_marks();
	$ui->paint_mute_buttons;

	# track fades
	
	map{ 
		my %h = %$_; 
		my $fade = ::Fade->new( %h ) ;
	} @fade_data;

	# edits 
	
	map{ 
		my %h = %$_; 
		my $edit = ::Edit->new( %h ) ;
	} @edit_data;

	# restore command history
	
	$term->SetHistory(@command_history);
} 

sub set_track_class {
	my ($track, $class) = @_;
	bless $track, $class;
	$track->set(class => $class);
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
	my $current_track = $this_track;
	if ($soloing) { all() }

	# get list of already muted tracks if I haven't done so already
	
	if ( ! @already_muted ){
		@already_muted = grep{ $_->old_vol_level} 
                         map{ $tn{$_} } 
						 ::Track::user();
	}
	$debug and say join " ", "already muted:", map{$_->name} @already_muted;

	# mute all tracks
	my @bus_tree = ($this_track->name, $this_track->bus_tree());
	map { $tn{$_}->mute(1) } 
	grep { my $tn = $_; ! grep { $tn eq $_ } @bus_tree } 
	::Track::user();

	$soloing = 1;
}

sub all {
	
	# unmute all tracks
	map { $tn{$_}->unmute(1) } ::Track::user();

	# re-mute previously muted tracks
	if (@already_muted){
		map { $_->mute(1) } @already_muted;
	}

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
	$jack_running =  process_is_running('jackd');
	$jack_plumbing = process_is_running('jack.plumbing');
	my $jack_lsp = qx(jack_lsp -Ap 2> /dev/null); 
	%jack = %{jack_ports($jack_lsp)} if $jack_running;
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
	my ($name, $type, $id, @args) = @_; 
		# command add_sub_bus does not supply @args at present
	
	::SubBus->new( 
		name => $name, 
		send_type => $type // 'track',
		send_id	 => $id // $name,
		);
	# create mix track
	my @vals = (source_type => 'bus', 
				source_id 	=> 'bus',
				width		=> 2, # default to stereo 
				rec_defeat 	=> 1,
				@args);

	if ($tn{$name}){
		say qq($name: setting as mix track for bus "$name");
		$tn{$name}->set( @vals );

	} else { ::add_track($name, @vals); }
}
	
sub add_send_bus {

	my ($name, $dest_id, $bus_type) = @_;
	my $dest_type = dest_type( $dest_id );

	# dest_type: soundcard | jack_client | loop | jack_port | jack_multi
	
	print "name: $name: dest_type: $dest_type dest_id: $dest_id\n";

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
	$term->rl_deprep_terminal() unless $opts{T};
	exit; 
}

# some common variables for cache_track and merge_track
# related routines

{ # begin shared lexicals for cache_track and merge_edits

	my ($track, 
		$additional_time, 
		$processing_time, 
		$orig_version, 
		$cooked,
		$complete_caching_ref);

sub cache_track { # launch subparts if conditions are met
	($track, $additional_time) = @_;
	say $track->name, ": preparing to cache.";
	
	# check conditions for sub-bus mix track
	if( $bn{$track->name} ){ 
		$track->rec_status ne 'OFF' or say(
			"mix track ",$track->name, ": status is OFF. Aborting."), return;

	# check conditions for normal track
	} else { 
		$track->rec_status eq 'MON' or say(
			$track->name, ": track caching requires MON status. Aborting."), return;
	}
	say($track->name, ": no effects to cache!  Skipping."), return 
		unless 	$track->fancy_ops 
				or $track->has_insert
				or $bn{$track->name};

	$complete_caching_ref = \&update_cache_map;
	prepare_to_cache();
	cache_engine_run();

}

sub prepare_to_cache {
	# uses shared lexicals
	
 	initialize_chain_setup_vars();
	$orig_version = $track->monitor_version;

	# create a temporary track to represent the output file
	
	my $cooked_name = $track->name . '_cooked';
	my $cooked = ::CacheRecTrack->new(
		name => $cooked_name,
		group => 'Temp',
		target => $track->name,
	);

	# connect the temporary track's output path
	
	$g->add_path($track->name, $cooked->name, 'wav_out');

	# set the correct output parameters in the graph
	
	$g->set_vertex_attributes(
		$cooked->name, 
		{ format => signal_format($cache_to_disk_format,$cooked->width),
		}
	); 

	# Case 1: Caching a standard track
	
	# set the original track to read the WAV file
	
	$g->add_path('wav_in',$track->name) if $track->rec_status eq 'MON';
	$debug and say "The graph0 is:\n$g";
	

	# Case 2: Caching a sub-bus mix track

	# apply all sub-buses (unneeded ones will be pruned from the graph)
	
	map{ $_->apply() } 
	grep{ (ref $_) =~ /Sub/ } 
	::Bus::all()
		if $track->rec_status eq 'REC';

	$debug and say "The graph1 is:\n$g";
	prune_graph();
	$debug and say "The graph2 is:\n$g";
	::Graph::expand_graph($g); 
	$debug and say "The graph3 is:\n$g";
	::Graph::add_inserts($g);
	$debug and say "The graph4 is:\n$g";
	process_routing_graph(); 
	write_chains();
	remove_temporary_tracks();
}
sub cache_engine_run { # uses shared lexicals

	connect_transport('quiet')
		or say ("Couldn't connect engine! Aborting."), return;
	$processing_time = $length + $additional_time;

	say $/,$track->name,": processing time: ". d2($processing_time). " seconds";
	print "Starting cache operation. Please wait.";
	revise_prompt(" "); 

	# we try to set processing time this way
	eval_iam("cs-set-length $processing_time"); 

	eval_iam("start");

	# ensure that engine stops at completion time
 	$event_id{poll_engine} = AE::timer(1, 0.5, \&poll_cache_progress);

	# complete_caching() contains the remainder of the caching code.
	# It is triggered by stop_polling_cache_progress()
}
sub complete_caching {
	# uses shared lexicals
	
	my $name = $track->name;
	my @files = grep{/$name/} new_files_were_recorded();
	if (@files ){ 
		
		&$complete_caching_ref; # update cache map 
		post_cache_processing();

	} else { say "track cache operation failed!"; }
}
sub update_cache_map {

		$debug and say "updating track cache_map";
		#say "cache map",yaml_out($track->cache_map);
		my $cache_map = $track->cache_map;
		$cache_map->{$track->last} = { 
			original 			=> $orig_version,
			effect_chain	=> push_effect_chain($track), # bypass
		};
		pop @{$track->effect_chain_stack}; # we keep it elsewhere
		if (my @inserts = grep{$_}(
				$track->prefader_insert, 
				$track->postfader_insert)
		){
			say "removing insert... ";
			say "if you want it again you will need to replace it yourself";
			say "this is what it was";
			map{ say $_->dump; $_->remove } 
				map{ $::Insert::by_index{$_} } 
				@inserts;
		}
		#say "cache map",yaml_out($track->cache_map);
		say qq(Saving effects for cached track "), $track->name, '".';
		say qq('uncache' will restore effects and set version $orig_version\n);
}

sub post_cache_processing {

		# only set to MON tracks that would otherwise remain
		# in a REC status
		#
		# track:REC bus:MON -> keep current state
		# track:REC bus:REC -> set track to MON

		$track->set(rw => 'MON') if $track->rec_status eq 'REC';

		$ui->global_version_buttons(); # recreate
		$ui->refresh();
		reconfigure_engine();
		revise_prompt("default"); 

}
sub merge_edits {
	# set shared lexicals

	$additional_time = 0; # needed only for effect caching

	$complete_caching_ref = sub 
	{ 
		# restore previous effects
		pop_effect_chain($track);	

		# possibly store comments
		
		disable_edits();
	};

	$track = $this_track; 

	# maybe we are on an edit track or host alias track
	
	# so we will try to merge edits for a track that is the same
	# name as the current bus, unless the current bus is
	# a system bus

	$track = $tn{$this_bus} 
		unless grep{ $this_bus eq $_ } qw(Main Master Mixdown);
	
	# make sure the system is in a suitable state
	
	# - track has edits
	# - track doesn't have inserts
	# - bus and track settings are correct
	
	say($track->name, ": version ", $track->monitor_version,
	"has no edits to merge. Aborting."), return
		unless $track->version_has_edits;

	say($track->name, ": has inserts. Remove them and try again. Aborting."),
		return if $track->has_insert;

	say($track->name, ": edits are not enabled. Select an edit for this track 
and version and try again. Aborting"), return 
		unless $track->edits_enabled;

	my $bus = $::Bus::by_name{$track->name};

	$bus->set(rw => 'MON'); # no edits of edits
	
	# we are good to go
	
	say $track->name, ": preparing to merge edits.";

	end_edit_mode(); # possibly set by select_edit

	# push effects off track	
	
	push_effects_chain($this_track, ops  => $this_track->ops);  # all of them

	prepare_to_cache();
	cache_engine_run();
}
sub poll_cache_progress {

	print ".";
	my $status = eval_iam('engine-status'); 
	my $here   = eval_iam("getpos");
	update_clock_display();
	#say "engine time:   ", d2($here);
	#say "engine status: ", $status;

	return unless 
		   $status =~ /finished|error|stopped/ 
		or $here > $processing_time;

	say "Done.";
	#engine_status(current_position(),2,1);
	#revise_prompt();
	stop_polling_cache_progress();
}
sub stop_polling_cache_progress {
	$event_id{poll_engine} = undef; 
	$ui->reset_engine_mode_color_display();
	complete_caching();

}
} # end shared lexicals for cache_track and merge_edits

sub uncache_track { 
	my $track = shift;
	# skip unless MON;
	my $cache_map = $track->cache_map;
	my $version = $track->monitor_version;
	if(is_cached($track)){
		# blast away any existing effects, TODO: warn or abort	
		say $track->name, ": removing effects (except vol/pan)" if $track->fancy_ops;
		map{ remove_effect($_)} $track->fancy_ops;

		# original WAV -> WAV case: reset version 
		if ( $cache_map->{$version}{original} ){ 
			$track->set(version => $cache_map->{$version}{original});
			print $track->name, ": setting uncached version ", $track->version, $/;

		# assume a sub-bus mix track, i.e. REC -> WAV: set to REC
		} else { 
			$track->set(rw => 'REC') ;
			say $track->name, ": setting sub-bus mix track to REC";
		} 

		add_effect_chain($track, $cache_map->{$version}{effect_chain})
			if $cache_map->{$version}{effect_chain};
	} 
	else { print $track->name, ": version $version is not cached\n"}
}
sub is_cached {
	my $track = shift;
	my $cache_map = $track->cache_map;
	$cache_map->{$track->monitor_version}
}
	
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


### WAV file length/format/modify_time are cached in %wav_info 

sub ecasound_get_info {
	# get information about an audio object
	
	my ($path, $command) = @_;
	teardown_engine();
	eval_iam('cs-add gl');
	eval_iam('c-add g');
	eval_iam('ai-add ' . $path);
	eval_iam('ao-add null');
	eval_iam('cs-connect');
	eval_iam('ai-select '. $path);
	my $result = eval_iam($command);
	teardown_engine();
	$result;
}
sub cache_wav_info {
	my @files = File::Find::Rule
		->file()
		->name( '*.wav' )
		->in( this_wav_dir() );	
	map{  get_wav_info($_) } @files;
}
sub get_wav_info {
	my $path = shift;
	#say "path: $path";
	$wav_info{$path}{length} = get_length($path);
	$wav_info{$path}{format} = get_format($path);
	$wav_info{$path}{modify_time} = get_modify_time($path);
}
sub get_length { 
	my $path = shift;
	my $length = ecasound_get_info($path, 'ai-get-length');
	sprintf("%.4f", $length);
}
sub get_format {
	my $path = shift;
	ecasound_get_info($path, 'ai-get-format');
}
sub get_modify_time {
	my $path = shift;
	my @stat = stat $path;
	$stat[9]
}
sub wav_length {
	my $path = shift;
	update_wav_cache($path);
	$wav_info{$path}{length}
}
sub wav_format {
	my $path = shift;
	update_wav_cache($path);
	$wav_info{$path}{format}
}
sub update_wav_cache {
	my $path = shift;
	return unless get_modify_time($path) != $wav_info{$path}{modify_time};
	say qq(WAV file $path has changed! Updating cache.);
	get_wav_info($path) 
}
	
sub freq { [split ',', $_[0] ]->[2] }  # e.g. s16_le,2,44100

sub channels { [split ',', $_[0] ]->[1] }
	
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
sub detect_keystroke_p {
	$event_id{stdin} = AE::io(*STDIN, 0, sub {
		&{$attribs->{'callback_read_char'}}();
		
		abort_set_edit_points(), return
			if $attribs->{line_buffer} eq "q"
			or $attribs->{line_buffer} eq "Q";

		if (   $attribs->{line_buffer} eq "p"
			or $attribs->{line_buffer} eq "P"){ get_edit_mark()}
		else{ reset_input_line() }
	});
}

sub reset_input_line {
	$attribs->{line_buffer} = q();
	$attribs->{point} 		= 0;
	$attribs->{end}   		= 0;
}


{ my $p;
  my @edit_points; 
  my @names = qw(dummy play-start rec-start rec-end);

sub initialize_edit_points {
	$p = 0;
    @edit_points = ();
}
sub abort_set_edit_points {
	say "...Aborting!";
	reset_input_line();
	eval_iam('stop');
	initialize_edit_points();
	detect_spacebar();
}

sub get_edit_mark {
	$p++;
	if($p <= 3){  # record mark
		my $pos = eval_iam('getpos');
		push @edit_points, $pos;
		say " got $names[$p] position ".d1($pos);
		reset_input_line();
		if( $p == 3){ complete_edit_points() }
		else{
			$term->stuff_char(10);
			&{$attribs->{'callback_read_char'}}();
		}
	}
}
sub complete_edit_points {
	@::edit_points = @edit_points; # save to global
	eval_iam('stop');
	say "\nEngine is stopped\n";
	detect_spacebar();
	transfer_edit_marks($this_edit) if $this_edit;
	print prompt(), " ";
}
}
sub set_edit_points {
	$tn{$this_edit->edit_name}->set(rw => 'OFF') if defined $this_edit;
	say("You must use a playback-only mode to setup edit marks. Aborting"), 
		return 1 if really_recording();
	say("You need stop the engine first. Aborting"), 
		return 1 if engine_running();
	say "Ready to set edit points!";
	sleeper(0.2);
	say q(Press the "P" key three times to mark positions for:
    + play-start
    + record-start
    + record-end

	say q(Press "Q" to quit.)

Engine will start in 2 seconds.);
	initialize_edit_points();
 	$event_id{set_edit_points} = AE::timer(2, 0, 
	sub {
		reset_input_line();
		detect_keystroke_p();
		eval_iam('start');
		say "\n\nEngine is running\n";
		print prompt();
	});
}
sub transfer_edit_points {
	say("Use 'set_edit_points' command to specify edit region"), return
		 unless scalar @edit_points;
	my $edit = shift;
	::Mark->new( name => $edit->play_start_name, time => $edit_points[0]);
	::Mark->new( name => $edit->rec_start_name,  time => $edit_points[1]);
	::Mark->new( name => $edit->rec_end_name,    time => $edit_points[2]);
	@edit_points = ();
}

sub generate_edit_record_setup { # for current edit
	# set edit track to REC
	# set global region start offset
	# set global region length cutoff
	# set regenerate_setup flag
	# insert host track fades
	# mute edit track
	# schedule unmuting at rec-start point - fade-in
	# schedule muting at rec-end point     - fade-out
}

sub new_edit {
	#my @edit_points = @_;
	say("You must use 'set_edit_points' before creating a new edit. Aborting."),
		return unless @edit_points;
	my $overlap = grep { 
		my $fail;
		my $rst = $_->rec_start_time;
		my $ret = $_->rec_end_time;
		my $nst = $edit_points[1];
		my $net = $edit_points[2];
		my $rst1 = d1($rst);
		my $ret1 = d1($ret);
		my $nst1 = d1($nst);
		my $net1 = d1($net);
		say("New rec-start time $nst1 conflicts with Edit ",
			$_->n, ": $rst1 < $nst1 < $ret1"), $fail++
		if $rst < $nst and $nst < $ret;
		say("New rec-end time $net1 conflicts with Edit ",
			$_->n, ": $rst1 < $net1 < $ret1"), $fail++
		if $rst < $net and $net < $ret;
		say("New rec interval $nst1 - $net1 conflicts with Edit ",
			$_->n, ": $rst1 - $ret1"), $fail++
		if $nst < $rst and $ret < $net;
		$fail
	} grep{ $_->host_track eq $this_track->name} 
		values %Audio::Nama::Edit::by_name;
	say("Aborting."), return if $overlap;
	my $name = $this_track->name;
	my $editre = qr($name-v\d+-edit\d+);
	say("$name: editing of edits is not currently allowed."),
		return if $name =~ /-v\d+-edit\d+/;
	say("$name: must be in MON mode.
Edits will be applied against current version"), 
		return unless $this_track->rec_status eq 'MON' 
			or $this_track->rec_status eq 'REC' and
			grep{ /$editre/ } keys %::Track::by_name;
	my $v = $this_track->monitor_version;
	say "$name: creating new edit against version $v";
	my $edit = ::Edit->new(
		host_track 		=> $this_track->name,
		host_version	=> $v,
	);
	$this_track->current_edit->{$v} = $edit->n;
	$this_edit = $edit;
	transfer_edit_points($edit);
	record_edit();
}
sub record_edit {
	set_edit_play_mode();
	$this_edit->edit_track->set(rw => 'REC');
	$this_edit->store_fades(std_host_fades(), edit_fades());
}
sub play_edit {
	set_edit_play_mode();
	$this_edit->edit_track->set(rw => 'MON');
	$this_edit->store_fades(std_host_fades(), edit_fades());
}
sub preview_edit_in {
	set_edit_play_mode();
	$this_edit->edit_track->set(rw => 'OFF');
	$this_edit->store_fades(std_host_fades());
}
sub preview_edit_out {
	set_edit_play_mode();
	$this_edit->edit_track->set(rw => 'OFF');
	$this_edit->store_fades(reverse_host_fades());
}
sub set_edit_play_mode {
	set_edit_mode();
	$this_edit->bus->set(rw => 'REC');
	$this_edit->edit_track->set(rw => 'MON');
	$regenerate_setup++;
}
sub end_track_edit_magic {
	# convert host track to mix track
	
	my $name = $this_edit->host_track;
	my @vals = (rec_defeat 	=> 0,
				rw => 'MON',
				);
	$::tn{$name}->set( @vals );
	$this_edit->bus->set(rw => 'OFF');
}
sub end_edit_mode  	{ 

	# regenerate fades
	
	$edit_mode = 0; 
	$regenerate_setup++ 
}
sub set_edit_mode 	{ $edit_mode = edit_mode_conditions() ?  1 : 0 }
sub edit_mode		{ $edit_mode }
sub edit_mode_conditions {        
	defined $this_edit or say('No edit is defined'), return;
	defined $this_edit->play_start_time or say('No edit points defined'), return;
	$this_edit->host_alias_track->rec_status eq 'MON'
		or say('host track alias: ',$this_edit->host_alias,
				" must be set to MON"), return;
	$this_edit->host_alias_track->monitor_version == $this_edit->host_version
		or say('host track alias: ',$this_edit->host_alias,
				" must be set to version ",$this_edit->host_version), return
	1;
}
sub reverse_host_fades { host_fades('in','out') }

sub std_host_fades { host_fades('out','in') }

sub host_fades {
	my ($first,$second) = @_;
	::Fade->new(  type => $first,
					mark1 => $this_edit->rec_start_name,
					duration => $edit_crossfade_time,
					relation => 'fade_from_mark',
					track => $this_edit->host_alias,
	), 
	::Fade->new(  type => $second,
					mark1 => $this_edit->rec_end_name,
					duration => $edit_crossfade_time,
					relation => 'fade_from_mark',
					track => $this_edit->host_alias,
	), 
}
sub edit_fades {
	::Fade->new(  type => 'in',
					mark1 => $this_edit->rec_start_name,
					duration => $edit_crossfade_time,
					relation => 'fade_from_mark',
					track => $this_edit->edit_name,
	), 
	::Fade->new(  type => 'out',
					mark1 => $this_edit->rec_end_name,
					duration => $edit_crossfade_time,
					relation => 'fade_from_mark',
					track => $this_edit->edit_name,
	); 
}

### edit region computations

{
# use internal lexical values for the computations

# track values
my( $trackname, $playat, $region_start, $region_end, $length);

# edit values
my( $edit_play_start, $edit_play_end);

# dispatch table
my( %playat, %region_start, %region_end);

# test variables
# my ($index, $new_playat, $new_region_start, $new_region_end);



%region_start = (
    out_of_bounds_near				=> sub{ "*" },
    out_of_bounds_far				=> sub{ "*" },	

	play_start_during_playat_delay	=> sub {$region_start },
	no_region_play_start_during_playat_delay => sub { 0 },

	play_start_within_region 
				=> sub {$region_start + $edit_play_start - $playat },
	no_region_play_start_after_playat_delay
				=> sub {$region_start + $edit_play_start - $playat },
);
%playat = (
    out_of_bounds_near				=> sub{ "*" },
    out_of_bounds_far				=> sub{ "*" },	

	play_start_during_playat_delay	=> sub{ $playat - $edit_play_start },
	no_region_play_start_during_playat_delay
									=> sub{ $playat - $edit_play_start },

	play_start_within_region   				=> sub{ 0 },
	no_region_play_start_after_playat_delay => sub{ 0 },

);
%region_end = (
    out_of_bounds_near				=> sub{ "*" },
    out_of_bounds_far				=> sub{ "*" },	

	play_start_during_playat_delay	
		=> sub { $region_start + $edit_play_end - $playat },
	no_region_play_start_during_playat_delay 
		=> sub {                 $edit_play_end - $playat },

	play_start_within_region 
		=> sub { $region_start + $edit_play_end - $playat },
	no_region_play_start_after_playat_delay
		=> sub {                 $edit_play_end - $playat },
);

sub new_playat       {       $playat{edit_case()}->() };
sub new_region_start { $region_start{edit_case()}->() };
sub new_region_end   
	{   
		my $end = $region_end{edit_case()}->();
		return $end if $end eq '*';
		$end < $length ? $end : $length
	};
# the following value will always allow enough time
# to record the edit. it may be longer than the 
# actual WAV file in some cases. (I doubt that
# will be a problem.)

sub edit_case {

	# logic for no-region case
	
    if ( ! $region_start and ! $region_end  )
	{
		if( $edit_play_end < $playat)
			{ "out_of_bounds_near" }
		elsif( $edit_play_start > $playat + $length)
			{ "out_of_bounds_far" }
		elsif( $edit_play_start >= $playat)
			{"no_region_play_start_after_playat_delay"}
		elsif( $edit_play_start < $playat and $edit_play_end > $playat )
			{ "no_region_play_start_during_playat_delay"}
	} 
	# logic for region present case
	
	elsif ( defined $region_start and defined $region_end )
	{ 
		if ( $edit_play_end < $playat)
			{ "out_of_bounds_near" }
		elsif ( $edit_play_start > $playat + $region_end - $region_start)
			{ "out_of_bounds_far" }
		elsif ( $edit_play_start >= $playat)
			{ "play_start_within_region"}
		elsif ( $edit_play_start < $playat and $playat < $edit_play_end)
			{ "play_start_during_playat_delay"}
		else {carp "$trackname: fell through if-then"}
	}
	else { carp "$trackname: improperly defined region" }
}

sub set_edit_vars {
	my $track = shift;
	$trackname      = $track->name;
	$playat 		= $track->playat_time;
	$region_start   = $track->region_start_time;
	$region_end 	= $track->region_end_time;
	$edit_play_start= $::this_edit->play_start_time;
	$edit_play_end	= $::this_edit->play_end_time;
	$length 		= wav_length($track->full_path);
}
sub set_edit_vars_testing {
	($playat, $region_start, $region_end, $edit_play_start, $edit_play_end, $length) = @_;
}
}

sub jack_plumbing_conf {
	join_path( $ENV{HOME} , '.jack.plumbing' )
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

sub list_edits {
	my @edit_data =
		map{ s/^---//; s/...\s$//; $_ } 
		map{ $_->dump }
		sort{$a->n <=> $b->n} 
		values %::Edit::by_name;
	pager(@edit_data);
}
sub explode_track {
	my $track = shift;
	
	# quit if I am already a mix track

	say($track->name,": I am already a mix track. I cannot explode!"),return
		if $track->source_type eq 'bus' or $bn{$track->name};

	my @versions = @{ $track->versions };

	# quit if I have only one version

	say($track->name,": Only one version. Skipping."), return
		if scalar @versions == 1;

	$track->busify;

	my $host = $track->name;
	my @names = map{ "$host-v$_"} @versions;
	my @exists = grep{ $::tn{$_} } @names;
	say("@exists: tracks already exist. Aborting."), return if @exists;
	my $current = cwd;
	chdir this_wav_dir();
	for my $i (@versions){

		# make a track

		my $name = "$host-v$i";
		::Track->new(
			name 	=> $name, 
			rw		=> 'MON',
			group	=> $host,
		);

		# symlink the WAV file we want

		symlink $track->targets->{$i}, "$name.wav";


	}
	chdir $current;
}	

sub select_edit {
	my $n = shift;
	my ($edit) = grep{ $_->n == $n } values %::Edit::by_name;
	say("Edit $n not found. Skipping."),return if ! $edit;
	say( qq(Edit $n applies to track "), $edit->host_track, 
		 qq(" version ), $edit->host_version, ".
This does does not match the track's current monitor version,
which is: ", $edit->host->monitor_version, ". Aborting."), return
		if $edit->host->monitor_version != $edit->host_version;
	$this_edit = $edit;
	$edit->bus->set(rw => 'REC');
	my @vals = (
		rw => 'REC',
		rec_defeat => 1,
		source_type => 'bus',
		source_id	=> undef,
	);
	$edit->host->set( @vals );
	set_edit_mode() and play_edit(); # should select_edit do this?
}
sub apply_fades { 
	# use info from Fade objects in %::Fade::by_name
	# applying to tracks that are part of current
	# chain setup
	my @tracks = map{$ti{$_}} keys %is_ecasound_chain;
	map{ ::Fade::refresh_fade_controller($_) }
	grep{$_->{fader} }  # only if already exists
	@tracks
}
sub disable_edits {

	# if we are on a host track, host alias or edit track
	# the current bus will be the name of the host track
	
	my $host = $tn{$this_bus};
	defined $host or print($this_track->name,": edits not enabled.\n"), return 1;

	# turn off bus (and all edit tracks)
	
	my $bus = $::Bus::by_name{$this_bus};
	$bus->set(rw => 'OFF');

	# we will use information from current edit
	# if defined
	
	my $edit = $this_edit;

	# reset host track, copying back source settings if possible
	
	$host->set(
		rw 			=> 'MON',
		rec_defeat	=> 0,
		source_type => (defined $edit 
			? $edit->edit_track->source_type
			: 'soundcard'),
		source_id 	=> (defined $edit 
			? $edit->edit_track->source_id
			: 1),
	);
	end_edit_mode();
}
{
my $comment_re = qr/([^*]*)(\*.*)?/;
sub show_version_comments {
	my ($t, @v) = @_;
	return unless @v;
	$t->set(version_comment => {}) unless $t->version_comment; # initialize
	my $c = $t->version_comment;
	::pager(map{ $c->{$_} ? "$_: $c->{$_}\n" : "" }@v);
}
sub add_version_comment {
	my ($t,$v,$text) = @_;
	$text =~ s/\s+$//; # remove trailing spaces
	$t->set(version_comment => {}) unless $t->version_comment; # initialize
	my $c = $t->version_comment;
	my ($u,$n) = $c->{$v} =~ /$comment_re/; 
	$c->{$v} = "$text $n";
	"$v: $c->{$v}\n";
}
sub remove_version_comment {
	my ($t,$v) = @_;
	$t->set(version_comment => {}) unless $t->version_comment; # initialize
	my $c = $t->version_comment;
	my ($u,$n) = $c->{$v} =~ /$comment_re/; 
	if($n){ 
		$c->{$v} = $n;
		"$v: $n\n";
	} else { 
		delete $c->{$v}; # remove key if no text remains
		"$v: [comment deleted]\n";
	}
}

sub set_system_version_comment { 
	my ($t,$v,$text) = @_;
	$t->set(version_comment => {}) unless $t->version_comment; # initialize
	my $c = $t->version_comment;
	my ($u,$n) = $c->{$v} =~ /$comment_re/; 
	$u =~ s/\s+$//; # remove trailing spaces
	my $comment;
	$comment = "$u " if $u;
	$comment .= "* $text";
	$c->{$v} = $comment;
	"$v: $comment\n";
}
}
### end
