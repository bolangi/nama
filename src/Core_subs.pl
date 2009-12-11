sub nama { 
	process_options();
	prepare(); 
	command_process($execute_on_project_load);
	reconfigure_engine();
	$ui->loop;
}
sub prepare {
	
	$debug2 and print "&prepare\n";
	choose_sleep_routine();

	$project_name = shift @ARGV;
	$debug and print "project name: $project_name\n";

	$debug and print ("\%opts\n======\n", yaml_out(\%opts)); ; 


	read_config(global_config());  # from .namarc if we have one

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
	poll_jack();
	initialize_terminal();

	if (! $project_name ){
		$project_name = "untitled";
		$opts{c}++; 
	}
	print "\nproject_name: $project_name\n";
	
	if ($project_name){
		load_project( name => $project_name, create => $opts{c}) ;
	}
	1;	
}
sub issue_first_prompt {
	$term->stuff_char(10); # necessary to respond to Ctrl-C at first prompt 
	&{$attribs->{'callback_read_char'}}();
	print prompt();
	$attribs->{already_prompted} = 0;
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
	vet_keystrokes();
	revise_prompt();
	# handle Control-C from terminal

	$SIG{INT} = \&cleanup_exit;
	#$event_id{sigint} = AE::signal('INT', \&cleanup_exit);

}
sub revise_prompt {
    $term->callback_handler_install(prompt(), \&process_line);
}
sub prompt {
	"nama". ($this_track ? " [".$this_track->name."]" : '') . " ('h' for help)> "
}
sub vet_keystrokes {
	$event_id{stdin} = AE::io(*STDIN, 0, sub {
		&{$attribs->{'callback_read_char'}}();
		if (  $press_space_to_start_transport and
				$attribs->{line_buffer} eq " " ){

			toggle_transport();	
			$attribs->{line_buffer} = q();
			$attribs->{point} 		= 0;
			$attribs->{end}   		= 0;
			$term->stuff_char(10);
			&{$attribs->{'callback_read_char'}}();
		}
	});
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
	@a or print ( <<WARN
LADSPA helper program 'analyseplugin' not found
in $ENV{PATH}, your shell's list of executable 
directories. You will probably have more fun with the LADSPA
libraries and executables installed. http://ladspa.org
WARN
	) and  sleeper (0.6) and $missing++;
	my @b = `which ecasound`;
	@b or print ( <<WARN
Ecasound executable program 'ecasound' not found
in $ENV{PATH}, your shell's list of executable 
directories. This suite depends on the Ecasound
libraries and executables for all audio processing! 
WARN
	) and sleeper (0.6) and $missing++;

	my @c = `which file`;
	@c or print ( <<WARN
BSD utility program 'file' not found
in $ENV{PATH}, your shell's list of executable 
directories. This program is currently required
to be able to play back mixes in stereo.
WARN
	) and sleeper (0.6);
	if ( $missing ) {
	print "You lack $missing main parts of this suite.  
Do you want to continue? [N] ";
	$missing and 
	my $reply = <STDIN>;
	chomp $reply;
	print ("Goodbye.\n"), exit unless $reply =~ /y/i;
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
		debugging-output			D
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
                                 (manually use 'generate' and 'connect' commands)
--debugging-output, -D           Emit debugging information

HELP


	say $banner;

	if ($opts{D}){
		$debug = 1;
		$debug2 = 1;
	}
	if ( ! $opts{t} and can_load( modules => { Tk => undef } ) ){ 
		$ui = ::Graphical->new;
	} else {
		$ui = ::Text->new;
		can_load( modules =>{ Event => undef});
		import Event qw(loop unloop unloop_all);
	}
	can_load( modules => {AnyEvent => undef});

}
	
{
my $default_port = 2868; # Ecasound's default
sub launch_ecasound_server {
	my $port = shift // $default_port;
	my $command = "ecasound -K -C --server --server-tcp-port=$port";
	my $redirect = "2>&1>/dev/null &";
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

$debug and say "return value: $return_value
length: $length
type: $type
reply: $reply";

	$return_value == 256 or die "illegal return value, stopped" ;
	$reply =~ s/\s+$//; 

	given($type){
		when ('e'){ warn $reply }
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
	# $errmsg and carp("IAM WARN: ",$errmsg), 
	# not needed ecasound prints error on STDOUT
	$e->errmsg('');
	"@result";
	#$errmsg ? undef : "@result";
}
sub colonize { # convert seconds to hours:minutes:seconds 
	my $sec = shift;
	my $hours = int ($sec / 3600);
	$sec = $sec % 3600;
	my $min = int ($sec / 60);
	$sec = $sec % 60;
	$sec = "0$sec" if $sec < 10;
	$min = "0$min" if $min < 10 and $hours;
	($hours ? "$hours:" : "") . qq($min:$sec);
}

## configuration file

sub project_root { File::Spec::Link->resolve_all($project_root)};

sub config_file { $opts{f} ? $opts{f} : ".namarc" }
sub this_wav_dir {
	$project_name and
	File::Spec::Link->resolve_all(
		join_path( project_root(), $project_name, q(.wav) )  
	);
}
sub project_dir  {$project_name and join_path( project_root(), $project_name)
}

sub global_config{
print ("reading config file $opts{f}\n"), return io( $opts{f})->all if $opts{f} and -r $opts{f};
my @search_path = (project_dir(), $ENV{HOME}, project_root() );
my $c = 0;
	map{ 
#print $/,++$c,$/;
			if (-d $_) {
				my $config = join_path($_, config_file());
				#print "config: $config\n";
				if( -f $config ){ 
					my $yml = io($config)->all ;
					return $yml;
				}
			}
		} ( @search_path) 
}

sub read_config {
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
	print ("no project name.. doing nothing.\n"),return 
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
	initialize_buses();	
	initialize_project_data();

	remove_small_wavs(); 
	rememoize();

	restore_state( $h{settings} ? $h{settings} : $state_store_file) unless $opts{m} ;
	if (! $tn{Master}){

		::SimpleTrack->new( 
			group => 'Master', 
			name => 'Master',
			rw => 'MON',); # no dir, we won't record tracks


		 ::Track->new( 
			group => 'Mixdown', 
			name => 'Mixdown', 
			width => 2,
			rw => 'MON'); 
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
sub rememoize {
	return unless $memoize;
	package ::Wav;
	unmemoize('candidates');
	memoize(  'candidates');
}

=comment
	# rules for instrument monitor buses using raw inputs
	
	$mon_setup = ::Rule->new(
		
		name			=>  'mon_setup', 
		target			=>  'MON',
		chain_id 		=>	sub{ my $track = shift; $track->n },
		input_type		=>  'file',
		input_object	=>  sub{ my $track = shift; $track->full_path },
		post_input		=>	sub{ my $track = shift; $track->mono_to_stereo},
		condition 		=> 1,
		status			=>  1,
	);


 	$rec_setup = ::Rule->new(	 	# used by user buses 
		
		name			=>	'rec_setup', 
		chain_id		=>  sub{ $_[0]->n },   
		target			=>	'REC',
		input_type		=> sub{ $_[0]->source_input()->[0]},
		input_object	=> sub{ $_[0]->source_input()->[1]},
		post_input			=>	sub{ my $track = shift;
										$track->rec_route .
										$track->mono_to_stereo 
										},
		condition 		=> 1,
		status			=>  1,
	);

	$send_bus_out = ::Rule->new(

		name			=>  'send_bus_out',
		chain_id		=>  sub { $_[0]->n },
		target			=>  'all',
		output_type		=> sub{ $_[0]->send_output()->[0]},
		output_object	=> sub{ $_[0]->send_output()->[1]},
		pre_output		=>	sub{ $_[0]->pre_send},
		condition        => sub{ $tn{$_[0]->target()}->rec_status ne 'OFF'},
		status			=>  1,
		
	);

}
=cut

sub jack_running {
	my @pids = split " ", qx(pgrep jackd);
	my @jack  = grep{   my $pid;
						/jackd/ and ! /defunct/
						and ($pid) = /(\d+)/
						and grep{ $pid == $_ } @pids 
				} split "\n", qx(ps ax) ;
}
sub engine_running {
	eval_iam("engine-status") eq "running"
};

sub initialize_buses {
	$main_bus = ::Bus->new(name => 'Main_Bus');
	$null_bus = ::Bus->new(name => 'Null_Bus');
}
	
sub initialize_project_data {
	$debug2 and print "&initialize_project_data\n";

	return if transport_running();
	$ui->destroy_widgets();
	$ui->project_label_configure(
		-text => uc $project_name, 
		-background => 'lightyellow',
		); 

	# assign_var($project_init_file, @project_vars);

	%cops        = ();   
	$cop_id           = "A"; # autoincrement
	%copp           = ();    # chain operator parameters, dynamic
	                        # indexed by {$id}->[$param_no]
							# and others
	%old_vol = ();

	@input_chains = ();
	@output_chains = ();

	%track_widget = ();
	%effects_widget = ();

	# time related
	
	$markers_armed = 0;

	# new Marks
	# print "original marks\n";
	#print join $/, map{ $_->time} ::Mark::all();
 	map{ $_->remove} ::Mark::all();
	@marks_data = ();
	#print "remaining marks\n";
	#print join $/, map{ $_->time} ::Mark::all();
	# volume settings
	
	%old_vol = ();

	# $is_armed = 0;
	
	$old_snapshot = {};
	$preview = $initial_user_mode;
	$mastering_mode = 0;
	$saved_version = 0; 
	
	%bunch = ();	
	
	::Bus->initialize();
	::Group->initialize();
	create_groups();
	::Track->initialize();

	%inputs = %outputs = ();

}
sub create_groups {

	::Group->new(name => 'Master'); # master fader
	::Group->new(name => 'Mixdown', rw => 'REC');
	::Group->new(name => 'Mastering'); # mastering network
	::Group->new(name => 'Insert'); # auxiliary tracks for inserts
	::Group->new(name => 'Cooked'); # used by CacheRec tracks
	::Group->new(name => 'Temp'); # tracks to be removed
								#	after generating chain setup
	$main = ::Group->new(name => 'Main', rw => 'REC');
	$null    = ::Group->new(name => 'null');
}

## track and wav file handling

# create read-only track pointing at WAV files of specified
# track name in a different project

sub add_track_alias_project {
	my ($name, $track, $project) = @_;
	my $dir =  join_path(project_root(), $project, '.wav'); 
	if ( -d $dir ){
		if ( glob "$dir/$track\_*.wav"){
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
	my $track = ::Track->new(
		name => $name,
		@params
	);
	$this_track = $track;
	return if ! $track; 
	$debug and print "ref new track: ", ref $track; 
	$track->source($ch_r) if $ch_r;
#		$track->send($ch_m) if $ch_m;

	my $group = $::Group::by_name{$track->group}; 
	command_process('for mon; mon') if $preview and $group->rw eq 'MON';
	$group->set(rw => 'REC') unless $track->target; # not if is alias

	# normal tracks default to 'REC'
	# track aliases default to 'MON'
	$track->set(rw => $track->target
					?  'MON'
					:  'REC') ;
	$track_name = $ch_m = $ch_r = undef;

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
sub add_slave_track {
	my %h = @_;
	say (qq[Group "$h{group}" does not exist, skipping.]), return
		 unless $::Group::by_name{$h{group}};
	say (qq[Target track "$h{target}" does not exist, skipping.]), return
		 unless $tn{$h{target}};
		::SlaveTrack->new(	
			name => "$h{group}_$h{target}",
			target => $h{target},
			rw => 'MON',
			source_type => undef,
			source_id => undef,
			send_type => $::Bus::by_name{$h{group}}->destination_type,
			send_id   => $::Bus::by_name{$h{group}}->destination_id,
			)
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

sub remove_small_wavs {

	# 44 byte stubs left by a recording chainsetup that is 
	# connected by not started
	
	$debug2 and print "&remove_small_wavs\n";
	

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
				type => 'ea',
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
	map{ /-o:(.*?\.wav)$/} grep{ /-o:/ and /\.wav$/} split "\n", $chain_setup
}


sub generate_setup { 

	$debug2 and print "&generate_setup\n";

	my $automix = shift; # route Master to null_out if present

	# save current track
	my $old_this_track = $this_track;

	initialize_chain_setup_vars();
	add_paths_for_main_tracks();
	$debug and say "The graph is:\n$g";
	add_paths_for_recording();
	$debug and say "The graph is:\n$g";
	add_paths_for_null_input_tracks();
	$debug and say "The graph is:\n$g";
	add_paths_for_aux_sends();
	$debug and say "The graph is:\n$g";
	#add_paths_for_send_buses();
	#$debug and say "The graph is:\n$g";
	#add_paths_for_sub_buses();
	#$debug and say "The graph is:\n$g";
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

	process_routing_graph() or say("No tracks to record or play."),return;

	# now we have processed graph, we can remove temp tracks

	$this_track = $old_this_track;

	write_chains(); 

	remove_temp_tracks();

	1; # used to sense a chain setup ready to run
}
sub remove_temp_tracks {
	map { $_->remove  } grep{ $_->group eq 'Temp'} ::Track::all();
}
sub initialize_chain_setup_vars {

	@io = (); 			# IO object list
	$g = Graph->new(); 	
	%inputs = %outputs = %post_input = %pre_output = ();
	@input_chains = @output_chains = @post_input = @pre_output = ();
	undef $chain_setup;
}
sub add_paths_for_main_tracks {
	$debug2 and say "&add_paths_for_main_tracks";
	map{ 

		# connect signal sources to tracks
		
		my @path = $_->input_path;
		#say "Main bus track input path: @path";
		$g->add_path(@path) if @path;

		# connect tracks to Master
		
		$g->add_edge($_->name, 'Master'); #  if $g->predecessors($_->name);

	} 	# exclude MON tracks in doodle mode	
		grep{ 1 unless $preview eq 'doodle' and $_->rec_status eq 'MON' } 
		grep{ $_->rec_status ne 'OFF' }  # exclude OFF tracks
		map{$tn{$_}} 	# convert to Track objects
		$main->tracks;  # list of Track names

}

sub add_paths_for_recording {
	return if $preview; # don't record during preview modes
	$debug2 and say "&add_paths_for_recording";

	# we record tracks set to REC, unless rec_defeat is set 
	# or the track belongs to the 'null' group
	my @tracks = ::Track::all();

	map{ 
		# create temporary track for rec_file chain
		
		my $name = $_->name . '_rec_file';
		my $anon = ::SlaveTrack->new( 
			target => $_->name,
			rw => 'OFF',
			group => 'Temp',
			name => $name);

		# connect IO
		
		my ($type, $device_id) = @{ $_->source_input };
		$g->add_path($_->source_type ."_in", $name, 'wav_out');

		# set chain_id to R3 (if original track is 3) 
		$g->set_vertex_attributes($name, { chain_id => 'R'.$_->n });

	} grep{ $_->rec_status eq 'REC' 
			and not $_->group eq 'null'  
			and not $_->rec_defeat 
	} @tracks;
}


sub add_paths_for_null_input_tracks {
	$debug2 and say "&add_paths_for_null_tracks";

	map{ $g->add_path('null_in', $_->name, 'Master') }
 	grep{ $_->rec_status eq 'REC' } 
	map{$tn{$_}} 	# convert to Track objects
	$::Group::by_name{null}->tracks; # list of Track names
}

sub add_paths_for_aux_sends {
	$debug2 and say "&add_paths_for_aux_sends";

	# auxiliary sends go to soundcard or jack_client
	# track output usually goes to Master or to another track
	# so we can connect without concern for duplicate connections
	# which our graph doesn't allow
=comment
		my ($type, $device_id) = @{ $_->send_output };
		say "aux send name: ", $_->name," type: $type, device_id: $device_id";
		$g->add_path($_->name, $type);
		 $g->set_edge_attributes($_->name, $type, 
			{ track => $_, chain_id => 'S'.$_->n });
=cut
	
	map {  
		my $name = $_->name . '_aux';
		my $anon = ::SlaveTrack->new( 
			target => $_->name,
			group => 'Temp',
			name => $name);

		# connect IO

		#say "aux send track: ",$anon->name, " n: ", $anon->n;
		my ($type, $device_id) = @{ $_->send_output };
		#say "aux send name: $name, type: $type, device_id: $device_id";
		$g->add_path($_->name, $name, $type);

		$g->set_vertex_attributes($name, { chain_id => 'S'.$_->n });

  	} grep { $_->name !~ /_rec_file/ 
				and $_->send_type 
				and $_->rec_status ne 'OFF' } ::Track::all();
}
=comment
sub add_paths_for_send_buses {
	$debug2 and say "&add_paths_for_send_buses";

	my @user_buses = grep{ $_->name  !~ /Null_Bus|Main_Bus/ } values %::Bus::by_name;
	map{

		my $bus = $_;
		# we get tracks from a group of the same name as $bus->name
		my @tracks = grep{ $_->rec_status ne 'OFF' } 
					 map{$tn{$_}} $::Group::by_name{$bus->name}->tracks;

		# we only support post-fader send buses
		
		if( $bus->bus_type eq 'cooked'){  # post-fader send bus

			$debug and say 'process post-fader bus';

			# The signal path is:
			# [target track] -> [slave track] -> [slave track send_output]
			
			#map{   $g->add_path( $_->target, $_->name, $_->send_type.'_out');
			map{   $g->add_path( $_->target, $_->name, $_->send_type);
			} @tracks; 
		}
	} @user_buses;
}
sub add_paths_for_sub_buses {
	$debug2 and say "&add_paths_for_sub_buses";

	my @user_buses = grep{ $_->name  !~ /Null_Bus|Main_Bus/ } values %::Bus::by_name;
	map{

		my $bus = $_;
		# we get tracks from a group of the same name as $bus->name
		my @tracks = grep{ $_->rec_status ne 'OFF' } 
					 map{$tn{$_}} $::Group::by_name{$bus->name}->tracks;

		if( $_->bus_type eq 'sub'){   # sub bus
			$debug and say 'process sub bus';
			my $output = $bus->destination_type eq 'track' 
				? $bus->destination_id
				: $bus->destination_type . '_out';

			$debug and say "bus output: $output";

			# The signal path is:
			# [track input] -> [track] -> [bus destination]
			
			map{ 	my @path = ($_->input_path, $output);
					say "path: @path";
					$g->add_path(@path); 

			} @tracks;
		}
	} @user_buses;
}
=cut
sub add_paths_from_Master {
	$debug2 and say "&add_paths_from_Master";

	if ($mastering_mode){
		$g->add_path(qw[Master Eq Low Boost]);
		$g->add_path(qw[Eq Mid Boost]);
		$g->add_path(qw[Eq High Boost]);
		$g->add_path(qw[Boost soundcard_out]) if $main_out;

	} else { $g->add_edge('Master','soundcard_out') if $main_out }

}
sub add_paths_for_mixdown_handling {
	$debug2 and say "&add_paths_for_mixdown_handling";

	if ($tn{Mixdown}->rec_status eq 'REC'){
		my @p = (($mastering_mode ? 'Boost' : 'Master'), ,'Mixdown', 'wav_out');
		$g->add_path(@p);
		$g->set_vertex_attributes('Mixdown', {
		  format	=> 
			signal_format($mix_to_disk_format,$tn{Mixdown}->width),
		  chain_id			=> "Mixdown" }); 
		# no effects will be applied because effects are on chain 2
												 
	# Mixdown handling - playback
	
	} elsif ($tn{Mixdown}->rec_status eq 'MON'){
			my @e = qw(wav_in Mixdown soundcard_out);
			$g->add_path(@e);
			$g->set_vertex_attributes('Mixdown', {
 				  chain			=> "Mixdown" }); 
		# no effects will be applied because effects are on chain 2
	}
}
sub prune_graph {
	$debug2 and say "&prune_graph";
	# prune graph: remove tracks lacking inputs or outputs
	::Graph::remove_inputless_tracks($g);
	::Graph::remove_outputless_tracks($g); 
}
{
my @fields = qw(
		n
		name
		width
		playat_output
		select_output
		modifiers
		mono_to_stereo
		rec_route
		full_path
		source_input
		send_output
		pre_send
);

# an optimization
# sets a cache of current track method values for io dispatch
sub track_snapshots {
	my %tracks = map{ $_->name => $_->snapshot(\@fields) } 
					grep{ $_->rec_status ne 'OFF' } ::Track::all() ;
	\%tracks;
}
}
# new object based dispatch from routing graph
	
{my $jumper_id;
sub process_routing_graph {
	$debug2 and say "&process_routing_graph";
	$track_snapshots = track_snapshots(); # sets global used by dispatch
	$jumper_id = 0;  # for loop-to-loop chain ids
	#say yaml_out($track_snapshots); die "here";
	@io = map{ dispatch($_) } $g->edges;
	map{ $inputs{$_->ecs_string} //= [];
		push @{$inputs{$_->ecs_string}}, $_->chain_id;
		$post_input{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} grep { $_->direction eq 'input' } @io;
	map{ $outputs{$_->ecs_string} //= [];
		push @{$outputs{$_->ecs_string}}, $_->chain_id;
		$pre_output{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} grep { $_->direction eq 'output' } @io;
	no warnings 'numeric';
	my @in_keys = sort{$a->[0] <=> $b->[0]} values %inputs;
	my @out_keys = sort{$a->[0] <=> $b->[0]} values %outputs;
	my @temp;
	while( $out_keys[0] =~ /^\D/){
		push @temp, shift @out_keys;
	}
	push @out_keys, sort @temp;
	use warnings 'numeric';
	%inputs = reverse %inputs;	
	%outputs = reverse %outputs;	
	@input_chains = map {'-a:'.join(',',@$_)." $inputs{$_}"} @in_keys;
	@output_chains = map {'-a:'.join(',',@$_)." $outputs{$_}"} @out_keys;
	@post_input = sort map{ "-a:$_ $post_input{$_}"} keys %post_input;
	@pre_output = sort map{ "-a:$_ $pre_output{$_}"} keys %pre_output;
	@input_chains + @output_chains # to sense empty chain setup
}
sub non_track_dispatch {

	# loop-to-loop: assign chain_id to edge (if not present)
	#
	# we will use lower case j1, j2 for these "jumper chains"
	
	# soundcard_in - wav_out: we expect edge attributes 
	# to have been provided for handling this. 

	# loop-soundcard_out: 
	#
	# track7-soundcard_out as aux_send will have chain id S7
	# that will be transferred by expand_graph() to 
	# the new edge, loop-soundcard-out

	# we will issue two IO objects, one for the chain input
	# fragment, one for the chain output
	
	my $edge = shift;
	$debug and say "non-track dispatch: $edge->[0]-$edge->[1]";
	my $attr = $g->get_edge_attributes(@$edge);
	my $vattr = $g->get_vertex_attributes($edge->[0]);
	
	$attr->{chain_id} //= 'J'.$vattr->{n}. $vattr->{j}++;
	my @direction = qw(input output);
	map{ 
		my $direction = shift @direction;
		my $class = ::IO::get_class($_, $direction);
		my $attrib = {%$attr};
		$attrib->{device_id} //= $_ if ::Graph::is_a_loop($_);
		$attrib->{direction} //= $direction;
		$debug and say "non-track: $_, class: $class, chain_id: $attrib->{chain_id},",
 			"device_id: $attrib->{device_id}, direction $direction";
		$class->new($attrib ? %$attrib : () ) } @$edge;
}
} # end $jumper_id scope 
	

sub dispatch { # creates an IO object from a graph edge
	my $edge = shift;
	return non_track_dispatch($edge) if not grep{ $tn{$_} } @$edge ;
	$debug and say "dispatch: $edge->[0]-$edge->[1]";
	my($name, $endpoint, $direction) = decode_edge($edge);
	$debug and say "name: $name, endpoint: $endpoint, direction: $direction";
	my $track = $tn{$name};
	my $class = ::IO::get_class( $endpoint, $direction );
	my @args = (track => $track_snapshots->{$name},
			#	endpoint => $endpoint,
				device_id => $endpoint,
				direction => $direction,
				chain_id => $tn{$name}->n,
				override($name, $edge));
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
	$debug2 and say "&override";
	my ($name, $edge) = @_;
	override_from_vertex($name), override_from_edge($edge)
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
							
sub soundcard_output {
 	$::jack_running 
		? [qw(jack_client_out system)]
		: ['soundcard_device_out', $::alsa_playback_device]
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
	my $sf = join_path(&project_dir, $chain_setup_file);
	open my $setup, ">$sf";
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
		my $project_file = join_path(&project_dir , $chain_setup_file);
		eval_iam("cs-disconnect") if eval_iam("cs-connected");
		eval_iam("cs-remove") if eval_iam("cs-selected");
		eval_iam("cs-load ". $project_file);
		eval_iam("cs-select ". $project_file); # needed by Audio::Ecasound, but not Net-ECI !!
		$debug and map{eval_iam($_)} qw(cs es fs st ctrl-status);
}

sub arm {

	# now that we have reconfigure_engine(), use is limited to 
	# - exiting preview
	# - automix	
	
	$debug2 and print "&arm\n";
	exit_preview_mode();
	#adjust_latency();
	if( generate_setup() ){ connect_transport() };
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
sub reconfigure_engine {
	$debug2 and print "&reconfigure_engine\n";
	# skip if command line option is set
	return if $opts{R};

	return 0 if $disable_auto_reconfigure;

	# we don't want to disturb recording/mixing
	return 1 if really_recording() and engine_running();

	find_duplicate_inputs();

	# only act if change in configuration

	my $current = yaml_out(status_snapshot());
	my $old = yaml_out($old_snapshot);

	if ( $current eq $old){
			$debug and print ("no change in setup\n");
			return;
	}
	$debug and print ("setup change\n");

# 	# restore playback position unless 
# 	
# 	#  - doodle mode
# 	#  - change in global version
#     #  - change in project
#     #  - user or Mixdown track is REC enabled
# 	
# 	my $old_pos;
# 
# 	my $will_record = ! $preview 
# 						&&  grep { $_->{rec_status} eq 'REC' } 
# 							@{ $status_snapshot->{tracks} };
# 
# 	# restore playback position if possible
# 
# 	if (	$preview eq 'doodle'
# 		 	or  $old_snapshot->{project} ne $status_snapshot->{project} 
# 			or  $old_snapshot->{global_version} 
# 					ne $status_snapshot->{global_version} 
# 			or  $will_record  ){
# 
# 		$old_pos = undef;
# 
# 	} else { $old_pos = eval_iam('getpos') }
# 
# 	my $was_running = engine_running();
# 	stop_transport() if $was_running;

	$old_snapshot = status_snapshot();

	print STDOUT ::Text::show_tracks(::Track::all()) ;
	if ( generate_setup() ){
		print STDOUT ::Text::show_tracks_extra_info();
		connect_transport();
# 		eval_iam("setpos $old_pos") if $old_pos; # temp disable
# 		start_transport() if $was_running and ! $will_record;
		$ui->flash_ready;
		1; }
	else {	my $setup = join_path( project_dir(), $chain_setup_file);
			unlink $setup if -f $setup; }

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
	my $no_transport_status = shift;
	load_ecs(); 
	eval_iam("cs-selected") and	eval_iam("cs-is-valid")
		or print("Invalid chain setup, engine not ready.\n"),return;
	find_op_offsets(); 
	apply_ops();
	eval_iam('cs-connect');
	# or say("Failed to connect setup, engine not ready"),return;
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
	disconnect_jack_ports();
	connect_jack_ports();
	transport_status() unless $no_transport_status;
	$ui->flash_ready();
	#print eval_iam("fs");
	1;
	
}


sub connect_jack_ports {

	# use a heuristic to map port names to track channels
		
	# If track is mono, all to one input
	# If track is stereo, map as follows:
	# 
	# L or l: 1
	# R or r: 2
	# 
	# # if first entry ends with zero we use this mapping
	# 0: 1 
	# 1: 2
	# 
	# # otherwise we use this mapping
	# 1: 1
	# 2: 2
	# 
	# If track is more than stereo, use linenumber % channel_count
	# 
	# 1st: 1
	# 2nd: 2
	# 3rd: 3
	# ...

	my $dis = shift;
	my $offset;
	my %map_RL = (L => 1, R => 2);
	map{  my $track = $_; 
 		  my $name = $track->name;
 		  my $dest = "ecasound:$name\_in_";
 		  my $file = join_path(project_root(), $track->name.'.ports');
		  my $line_number = 0;
		  if( $track->rec_status eq 'REC' and -e $file){ 
			for (io($file)->slurp){   
					# $_ is the source port name
					chomp;
					# skip silently if port doesn't exist
					return unless $jack{$_};	
		  			my $cmd = q(jack_).$dis.qq(connect "$_" $dest);
					# define offset once based on first port line
					# ends in zero: 1 
					# ends in one:  0
					/(\d)$/ and $offset //= ! $1;
					#$debug and say "offset: $offset";
					if( $track->width == 1){ $cmd .= "1" }
					elsif( $track->width == 2){
						my($suffix) = /([LlRr]|\d+)$/;
						#say "suffix: $suffix";
						$cmd .= ($suffix =~ /\d/) 
							? ($suffix + $offset)
							: $map_RL{uc $suffix};
					} else { $cmd .= ($line_number % $track->width + 1) }
					$line_number++;
					$debug and say $cmd;
					system $cmd;
			} ;
		  }
 	 } grep{ $_->source_type eq 'jack_manual' and $_->rec_status eq 'REC' 
	 } ::Track::all();
}

sub disconnect_jack_ports { connect_jack_ports('dis') }

sub transport_status {
	
	map{ 
		say("Warning: $_: input ",$tn{$_}->source,
		" is already used by track ",$already_used{$tn{$_}->source},".")
		if $duplicate_inputs{$_};
	} $main->tracks;


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
		print "looping from ", d1($start), 
			($start > 120 
				? " (" . colonize( $start ) . ") "  
				: " " ),
						"to ", d1($end),
			($end > 120 
				? " (".colonize( $end ). ") " 
				: " " ),
				$/;
	}
	say "Engine is ready.";
	print "setup length is ", d1($length), 
		($length > 120	?  " (" . colonize($length). ")" : "" )
		,$/;
	print "now at ", colonize( eval_iam( "getpos" )), $/;
	print "\nPress SPACE to start or stop engine.\n\n"
		if $press_space_to_start_transport;
	#$term->stuff_char(10); 
}
sub start_transport { 

	# set up looping event if needed
	# mute unless recording
	# start
	# wait 0.5s
	# unmute
	# start heartbeat
	# report engine status
	# sleep 1s

	$debug2 and print "&start_transport\n";
	carp("Invalid chain setup, aborting start.\n"),return unless eval_iam("cs-is-valid");

	print "\nstarting at ", colonize(int eval_iam("getpos")), $/;
	schedule_wraparound();
	mute();
	eval_iam('start');
	sleeper(0.5) unless really_recording();
	unmute();
	$ui->set_engine_mode_color_display();
	start_heartbeat();
	print "engine is ", eval_iam("engine-status"), "\n\n"; 

	sleep 1; # time for engine to stabilize
}
sub stop_transport { 

	$debug2 and print "&stop_transport\n"; 
	mute();
	eval_iam('stop');	
	sleeper(0.5);
	print "\nengine is ", eval_iam("engine-status"), "\n\n"; 
	unmute();
	stop_heartbeat();
	$ui->project_label_configure(-background => $old_bg);
}
sub transport_running { eval_iam('engine-status') eq 'running'  }

sub disconnect_transport {
	return if transport_running();
		eval_iam("cs-disconnect") if eval_iam("cs-connected");
}

sub start_heartbeat {
 	$event_id{heartbeat} = AE::timer(0, 1, \&::heartbeat);
}

sub stop_heartbeat {
	$event_id{heartbeat} = undef; 
	$ui->reset_engine_mode_color_display();
	rec_cleanup() }

sub heartbeat {

	#	print "heartbeat fired\n";

	my $here   = eval_iam("getpos");
	my $status = eval_iam('engine-status');
	say("\nengine is stopped"),revise_prompt(),stop_heartbeat()
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
	$ui->clock_config(-text => colonize(eval_iam('cs-get-position')));
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
sub wraparound {
	package ::;
	@_ = discard_object(@_);
	my ($diff, $start) = @_;
	#print "diff: $diff, start: $start\n";
	$event_id{wraparound} = undef;
	$event_id{wraparound} = AE::timer($diff,0, sub{set_position($start)});
}

sub poll_jack { $event_id{poll_jack} = AE::timer(0,5,\&jack_update) }

sub mute {
	return if $tn{Master}->rw eq 'OFF' or really_recording();
	$tn{Master}->mute;
}
sub unmute {
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
	my $here = eval_iam("cs-get-position");

	print("mark exists already\n"), return 
		if grep { $_->time == $here } ::Mark::all();

	my $mark = ::Mark->new( time => $here, 
							name => $name);

		$ui->marker($mark); # for GUI
}
sub mark {
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
	my @marks = sort { $a->time <=> $b->time } @::Mark::all;
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
	my $here = eval_iam("cs-get-position");
	my @marks = sort { $a->time <=> $b->time } @::Mark::all;
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
	sleeper( 0.6);
}
## post-recording functions
sub rec_cleanup {  
	$debug2 and print "&rec_cleanup\n";
	print("transport still running, can't cleanup"),return if transport_running();
	if( my (@files) = new_files_were_recorded() ){
		say join $/, "Now reviewing your recorded files...", (@files);
		(grep /Mixdown/, @files) ? command_process('mixplay') : post_rec_configure();
	reconfigure_engine();
	}
}
sub post_rec_configure {

		$ui->global_version_buttons(); # recreate
		$main->set( rw => 'MON');
		$ui->refresh();
		reconfigure_engine();
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
						$tn{$name}->set(active => undef) if $tn{$name};
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
	@recorded 
} 

## effect functions

sub add_effect {
	
	$debug2 and print "&add_effect\n";
	
	my %p 			= %{shift()};
	my ($n,$code,$parent_id,$id,$parameter,$values) =
		@p{qw( chain type parent_id cop_id parameter values)};
	my $i = $effect_i{$code};

	return if $id and ($id eq $ti{$n}->vol 
				or $id eq $ti{$n}->pan);   # skip these effects 
			   								# already created in add_track

	$id = cop_add(\%p); 
	%p = ( %p, cop_id => $id); # replace chainop id
	$ui->add_effect_gui(\%p);
	if( eval_iam("cs-is-valid") ){
		my $er = engine_running();
		$ti{$n}->mute if $er;
		apply_op($id);
		$ti{$n}->unmute if $er;
	}
	$id;

}
sub modify_effect {
	my ($op_id, $parameter, $sign, $value) = @_;
	print("$op_id: effect does not exist\n"), return 
		unless $cops{$op_id};

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

	$debug2 and print "&remove_op\n";
	return unless eval_iam('cs-connected') and eval_iam('cs-is-valid');
	my $id = shift;
	my $n = $cops{$id}->{chain};
	my $index;
	my $parent = $cops{$id}->{belongs_to}; 

	# select chain
	
	my $cmd = "c-select $n";
	$debug and print "cmd: $cmd$/";
	eval_iam($cmd);
	#print "selected chain: ", eval_iam("c-selected"), $/; 

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
		$index = ctrl_index( $id );
		my $cmd = "c-select $n";
		#print "cmd: $cmd$/";
		eval_iam($cmd);
		# print "selected chain: ", eval_iam("c-selected"), $/; # Ecasound bug
		eval_iam("cop-select ". ($offset{$n} + $index));
		#print "selected operator: ", eval_iam("cop-selected"), $/;
		eval_iam("cop-remove");
		$debug and eval_iam("cs");

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

	# do nothing if cop_id has been issued
	return $p{cop_id} if $p{cop_id};

	local $cop_id = $magical_cop_id if $magical_cop_id;

	# make entry in %cops with chain, code, display-type, children

	my ($n, $type, $parent_id, $parameter)  = 
		@p{qw(chain type parent_id parameter)};
	my $i = $effect_i{$type};


	$debug and print "Issuing a cop_id for track $n: $cop_id\n";

	$cops{$cop_id} = {chain => $n, 
					  type => $type,
					  display => $effects[$i]->{display},
					  owns => [] }; 

	$p->{cop_id} = $cop_id;

	# set defaults
	
	if (! $p{values}){
		my @vals;
		$debug and print "no settings found, loading defaults if present\n";
		my $i = $effect_i{ $cops{$cop_id}->{type} };
		
		# don't initialize first parameter if operator has a parent
		# i.e. if operator is a controller
		
		for my $p ($parent_id ? 1 : 0..$effects[$i]->{count} - 1) {
		
			my $default = $effects[$i]->{params}->[$p]->{default};
			push @vals, $default;
		}
		$debug and print "copid: $cop_id defaults: @vals \n";
		$copp{$cop_id} = \@vals;
	}

	if ($parent_id) {
		$debug and print "parent found: $parent_id\n";

		# store relationship
		$debug and print "parent owns" , join " ",@{ $cops{$parent_id}->{owns}}, "\n";

		push @{ $cops{$parent_id}->{owns}}, $cop_id;
		$debug and print join " ", "my attributes:", (keys %{ $cops{$cop_id} }), "\n";
		$cops{$cop_id}->{belongs_to} = $parent_id;
		$debug and print join " ", "my attributes again:", (keys %{ $cops{$cop_id} }), "\n";
		$debug and print "parameter: $parameter\n";

		# set fx-param to the parameter number, which one
		# above the zero-based array offset that $parameter represents
		
		$copp{$cop_id}->[0] = $parameter + 1; 
		
 		# find position of parent and insert child immediately afterwards

 		my $end = scalar @{ $ti{$n}->ops } - 1 ; 
 		for my $i (0..$end){
 			splice ( @{$ti{$n}->ops}, $i+1, 0, $cop_id ), last
 				if $ti{$n}->ops->[$i] eq $parent_id
 		}
	}
	else { push @{$ti{$n}->ops }, $cop_id; } 

	# set values if present
	
	$copp{$cop_id} = $p{values} if $p{values};

	$cop_id++; # return value then increment
}

sub effect_update_copp_set {

	my ($id, $param, $val) = @_;
	effect_update( @_ );
	$copp{$id}->[$param] = $val;
}
	

sub effect_update {

	# update the parameters of the Ecasound chain operator
	# referred to by a Nama operator_id
	
	# (why not use this routine to update %copp values as
	# well?)
	
	#$debug2 and print "&effect_update\n";
	my $es = eval_iam("engine-status");
	$debug and print "engine is $es\n";
	return if $es !~ /not started|stopped|running/;

	my ($id, $param, $val) = @_;
	$param++; # so the value at $p[0] is applied to parameter 1
	my $chain = $cops{$id}{chain};

	carp("effect $id: non-existent chain\n"), return
		unless $chain;

	$debug and print "chain $chain id $id param $param value $val\n";

	# $param is zero-based. 
	# %copp is  zero-based.

	return if $ti{$chain}->rec_status eq "OFF"; 

	# above will produce a wrong result if the user changes track status
	# while the engine is running BUG

	return if $ti{$chain}->name eq 'Mixdown' and 
			  $ti{$chain}->rec_status eq 'REC';

	# above is irrelevant the way that mixdown is now
	# implemented DEPRECATED
	
 	$debug and print join " ", @_, "\n";	

	my $old_chain = eval_iam('c-selected');
	eval_iam("c-select $chain");

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
	eval_iam("c-select $old_chain");
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

	my $resolution = 40; # number of steps per second
	my $steps = $seconds * $resolution;
	my $wink  = 1/$resolution;
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
	my $from  = 0;
	fade( $id, 0, $from, $to, $fade_time + 0.2);
}
sub fadeout {
	my $id    = shift;
	my $from  =	$copp{$id}[0];
	my $to	  = 0;
	fade( $id, 0, $from, $to, $fade_time );
}

sub find_op_offsets {

	$debug2 and print "&find_op_offsets\n";
	eval_iam('c-select-all');
		#my @op_offsets = split "\n",eval_iam("cs");
		my @op_offsets = grep{ /"\d+"/} split "\n",eval_iam("cs");
		shift @op_offsets; # remove comment line
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
 		next if $ti{$n}->rec_status eq "OFF" ;
		#next if $n == 2; # no volume control for mix track
		#next if ! defined $offset{$n}; # for MIX
 		#next if ! $offset{$n} ;

	# controllers will follow ops, so safe to apply all in order
		for my $id ( @{ $ti{$n}->ops } ) {
		apply_op($id);
		}
	}
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
sub new_plugins {
	my $effects_cache = join_path(&project_root, $effects_cache_file);
	my $path = ladspa_path();
	
	my @filenames;
	for my $dir ( split ':', $path){
		opendir DIR, $dir or carp "failed to open directory $dir: $!\n";
		push @filenames,  map{"$dir/$_"} grep{ /.so$/ } readdir DIR;
		closedir DIR;
	}
	push @filenames, '/usr/local/share/ecasound/effect_presets',
                 '/usr/share/ecasound/effect_presets',
                 "$ENV{HOME}/.ecasound/effect_presets";
	my $effmod = modified($effects_cache);
	my $latest;
	map{ my $mod = modified($_);
		 $latest = $mod if $mod > $latest } @filenames;

	$latest > $effmod
}

sub modified {
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
	my @plugins;
	for my $dir (@dirs) {
		opendir DIR, $dir or carp qq(can't open LADSPA dir "$dir" for read: $!\n);
	
		push @plugins,  
			grep{ /\.so$/ and ! $seen{$_} and ++$seen{$_}} readdir DIR;
		closedir DIR;
	};
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
		# print ("$_ not found\n"), 
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
	

## persistent state support

sub save_state {
	$debug2 and print "&save_state\n";
	$saved_version = $VERSION;

	# first save palette to project_dir/palette.yml
	
	$debug and print "saving palette\n";
	$ui->save_palette;

	# save %effect_chain, common to all projects
	
 	serialize (
 		file => join_path(project_root(), $effect_chain_file),
		format => 'yaml',
 		vars => [ qw( %effect_chain ) ],
 		class => '::');
	

	# do nothing more if only Master and Mixdown
	
	if (scalar @::Track::all == 2 ){
		print "No user tracks, skipping...\n";
		return;
	}

	my $file = shift; # mysettings

	# remove nulls in %cops 
	
	delete $cops{''};

	$file = $file || $state_store_file;
	$file = join_path(&project_dir, $file) unless $file =~ m(/); 
	$file =~ /\.yml$/ or $file .= '.yml';	
	# print "filename base: $file\n";
	print "\nSaving state as $file\n";

# prepare tracks for storage

@tracks_data = (); # zero based, iterate over these to restore

$debug and print "copying tracks data\n";

map { push @tracks_data, $_->hashref } ::Track::all();
# print "found ", scalar @tracks_data, "tracks\n";

# delete unused fields
map { my $t = $_;
			map{ delete $t->{$_} } 
				qw(ch_r ch_m source_select send_select jack_source jack_send);
} @tracks_data;

@bus_data = (); # 
map{ push @bus_data, $_->hashref } 
	grep{ $_->name !~ /Main_Bus|Null_Bus/} ::Bus::all();

# prepare marks data for storage (new Mark objects)

@marks_data = ();
$debug and print "copying marks data\n";
map { push @marks_data, $_->hashref } ::Mark::all();

$debug and print "copying groups data\n";
@groups_data = ();
map { push @groups_data, $_->hashref } ::Group::all();

$debug and print "copying bus data\n";


# save history

	my @history = $::term->GetHistory;
	my %seen;
	@command_history = ();
	map { push @command_history, $_ 
			unless $seen{$_}; $seen{$_}++ } @history;

$debug and print "serializing\n";
	serialize(
		file => $file, 
		format => 'yaml',
		vars => \@persistent_vars,
		class => '::',
		);


# store alsa settings

	if ( $opts{a} ) {
		my $file = $file;
		$file =~ s/\.yml$//;
		print "storing ALSA settings\n";
		print qx(alsactl -f $file.alsa store);
	}


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
	$file = join_path(project_dir(), $file);
	$file .= ".yml" unless $file =~ /yml$/;
	! -f $file and (print "file not found: $file\n"), return;
	$debug and print "using file: $file\n";
	
	my $yaml = io($file)->all;

	# rewrite obsolete null hash/array substitution
	$yaml =~ s/~NULL_HASH/{}/g;
	$yaml =~ s/~NULL_ARRAY/[]/g;

	# rewrite %cops 'owns' field to []
	
	$yaml =~ s/owns: ~/owns: []/g;

	# restore persistent variables

	assign_var($yaml, @persistent_vars );

	# restore effect chains

	assign_var(join_path(project_root(), $effect_chain_file), qw(%effect_chain));

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

	#  destroy and recreate all groups

	::Group::initialize();	
	map { ::Group->new( %{ $_ } ) } @groups_data;  
	create_groups(); # make sure we have them all

	# restore user buses
	
	map{ my $class = $_->{class}; ::Bus->new( %$_ ) } @bus_data;
	
	# restore user tracks
	
	my $did_apply = 0;

	map{ 
		my %h = %$_; 
		my $track = ::Track->new( %h ) ; # initially Audio::Nama::Track 
		if ( $track->class ){ bless $track, $track->class } # current scheme
	} @tracks_data;

	$ui->create_master_and_mix_tracks();

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
	my $seconds = shift;
	my $am_running = ( eval_iam('engine-status') eq 'running');
	return if really_recording();
	my $jack = $jack_running;
	#print "jack: $jack\n";
	$am_running and $jack and eval_iam('stop');
	eval_iam("setpos $seconds");
	$am_running and $jack and sleeper($seek_delay), eval_iam('start');
	$ui->clock_config(-text => colonize($seconds));
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
	print "none muted\n";
		@already_muted = grep{ $_->old_vol_level} 
                         map{ $tn{$_} } 
						 ::Track::user();
	print join " ", "muted", map{$_->name} @already_muted;
	}

	# mute all tracks
	map { $this_track = $tn{$_}; $this_track->mute(1) } ::Track::user();

    $this_track = $current_track;
    $this_track->unmute(1);
	$soloing = 1;
}

sub all {
	
	my $current_track = $this_track;
	# unmute all tracks
	map { $this_track = $tn{$_}; $this_track->unmute(1) } ::Track::user();

	# re-mute previously muted tracks
	if (@already_muted){
		map { $_->mute(1) } @already_muted;
	}

	# remove listing of muted tracks
	
	@already_muted = ();
	$this_track = $current_track;
	$soloing = 0;
	
}

sub show_chain_setup {
	$debug2 and print "&show_chain_setup\n";
	my $setup = join_path( project_dir(), $chain_setup_file);
	say("No tracks to record or play."), return unless -f $setup;
	my $chain_setup;
	io( $setup ) > $chain_setup; 
	pager( $chain_setup );
}
sub pager {
	$debug2 and print "&pager\n";
	my @output = @_;
#	my ($screen_lines, $columns) = split " ", qx(stty size);
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
	my $user_input = join " ", @_;
	return if $user_input =~ /^\s*$/;
	$debug and print "user input: $user_input\n";
	my ($cmd, $predicate) = ($user_input =~ /([\S]+?)\b(.*)/);
	if ($cmd eq 'for' 
			and my ($bunchy, $do) = $predicate =~ /\s*(.+?)\s*;(.+)/){
		$debug and print "bunch: $bunchy do: $do\n";
		my ($do_part, $after) = $do =~ /(.+?);;(.+)/;
		$do = $do_part if $do_part;
		my @tracks;
		if ( lc $bunchy eq 'all' ){
			$debug and print "special bunch: all\n";
			@tracks = ::Track::user();
		} elsif ( lc $bunchy eq 'rec' ){
			$debug and print "special bunch: rec\n";
			@tracks = grep{$tn{$_}->rec_status eq 'REC'} ::Track::user();
		} elsif ( my $group = $::Group::by_name{$bunchy}){
			@tracks = $group->tracks;
		} elsif ( lc $bunchy eq 'mon' ){
			$debug and print "special bunch: mon\n";
			@tracks = grep{$tn{$_}->rec_status eq 'MON'} ::Track::user();
		} elsif ( lc $bunchy eq 'off' ){
			$debug and print "special bunch: off\n";
			@tracks = grep{$tn{$_}->rec_status eq 'OFF'} ::Track::user();
		} elsif ($bunchy =~ /\s/  # multiple identifiers
			or $tn{$bunchy} 
			or $bunchy !~ /\D/ and $ti{$bunchy}){ 
			$debug and print "multiple tracks found\n";
			@tracks = grep{ $tn{$_} or ! /\D/ and $ti{$_} }
				split " ", $bunchy;
			$debug and print "multitracks: @tracks\n";
		} elsif ( @tracks = @{$bunch{$bunchy}}) {
			$debug and print "bunch tracks: @tracks\n";
 		}
		for my $t(@tracks) {
			command_process("$t; $do");
		}
		command_process($after) if $after;
	} elsif ($cmd eq 'eval') {
			$debug and print "Evaluating perl code\n";
			pager( eval $predicate );
			print "\n";
			$@ and print "Perl command failed: $@\n";
	}
	elsif ( $cmd eq '!' ) {
			$debug and print "Evaluating shell commands!\n";
			#system $predicate;
			my $output = qx( $predicate );
			#print "length: ", length $output, $/;
			pager($output); 
			print "\n";
	} else {


		my @user_input = split /\s*;\s*/, $user_input;
		map {
			my $user_input = $_;
			my ($cmd, $predicate) = ($user_input =~ /([\S]+)(.*)/);
			$debug and print "cmd: $cmd \npredicate: $predicate\n";
			if ($cmd eq 'eval') {
				$debug and print "Evaluating perl code\n";
				pager( eval $predicate);
				print "\n";
				$@ and print "Perl command failed: $@\n";
			} elsif ($cmd eq '!') {
				$debug and print "Evaluating shell commands!\n";
				my $output = qx( $predicate );
				#print "length: ", length $output, $/;
				pager($output); 
				print "\n";
			} elsif ($tn{$cmd}) { 
				$debug and print qq(Selecting track "$cmd"\n);
				$this_track = $tn{$cmd};
				my $c = q(c-select ) . $this_track->n; 
				eval_iam( $c ) if eval_iam( 'cs-connected' );
				$predicate !~ /^\s*$/ and $parser->command($predicate);
			} elsif ($cmd =~ /^\d+$/ and $ti{$cmd}) { 
				$debug and print qq(Selecting track ), $ti{$cmd}->name, $/;
				$this_track = $ti{$cmd};
				my $c = q(c-select ) . $this_track->n; 
				eval_iam( $c );
				$predicate !~ /^\s*$/ and $parser->command($predicate);
			} elsif ($iam_cmd{$cmd}){
				$debug and print "Found Iam command\n";
				my $result = eval_iam($user_input);
				pager( $result );  
			} else {
				$debug and print "Passing to parser\n", $_, $/;
				#print 1, ref $parser, $/;
				#print 2, ref $::parser, $/;
				# both print
				defined $parser->command($_) 
					or print "Bad command: $_\n";
			}    
		} @user_input;
	}
	
	$ui->refresh; # in case we have a graphic environment
}
sub load_keywords {
	@keywords = keys %commands;
	push @keywords, grep{$_} map{split " ", $commands{$_}->{short}} @keywords;
	push @keywords, keys %iam_cmd;
	push @keywords, keys %effect_j;
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


sub jack_update {
	# cache current JACK status
	$jack_running = jack_running();
	$jack_lsp = qx(jack_lsp -Ap 2> /dev/null); 
	%jack = %{jack_ports()} if $jack_running;
}
sub jack_client {

	# returns true if client and direction exist
	# returns number of client ports
	
	my ($name, $direction)  = @_;

	# synth:in_1 input
	# synth input
	# aeolus:out.R
	
	my $port;
	($name, $port) = $name =~ /^([^:]+):?(.*)/;

	# currently we ignore port

	$jack{$name}{$direction};
}

sub jack_ports {
	$jack_running or return;
	my $j = $jack_lsp; 
	#return if $j =~ /JACK server not running/;

	# convert to single lines

	$j =~ s/\n\s+/ /sg;

	# system:capture_1 alsa_pcm:capture_1 properties: output,physical,terminal,
	my %jack = ();

	map{ 
		my ($direction) = /properties: (input|output)/;
		s/properties:.+//;
		my @ports = /
			\s* 			# zero or more spaces
			([^:]+:[^:]+?) # non-colon string, colon, non-greey non-colon string
			(?=[-+.\w]+:|\s+$) # zero-width port name or spaces to end-of-string
		/gx;
		map { 
				s/ $//; # remove trailing space
				$jack{ $_ }{ $direction }++;
				my ($client, $port) = /(.+?):(.+)/;
				$jack{ $client }{ $direction }++;

		 } @ports;

	} split "\n",$j;
	#print yaml_out \%jack;
	\%jack
}
	

sub automix {

	#use Smart::Comments '###';
	# add -ev to summed signal
	my $ev = add_effect( { chain => $tn{Master}->n, type => 'ev' } );
	### ev id: $ev

	# turn off audio output
	
	$main_out = 0;

	### Status before mixdown:

	command_process('show');

	### reduce track volume levels  to 10%
	
	command_process( 'for mon; vol/10');

	#command_process('show');

	generate_setup('automix'); # pass a bit of magic
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
		command_process( 'for mon; vol*10');
		$main_out = 1;
		return;
	}

	### apply multiplier to individual tracks

	command_process( "for mon; vol*$multiplier" );

	# $main_out = 1; # mixdown will turn off and turn on main out
	
	### mixdown
	command_process('mixdown; arm; start');

	### turn on audio output

	# command_process('mixplay'); # rec_cleanup does this
	# automatically

	#no Smart::Comments;
	
}

sub master_on {

	return if $mastering_mode;
	
	# set $mastering_mode	
	
	$mastering_mode++;

	# create mastering tracks if needed
	
	# (no group membership needed)

	if ( ! $tn{Eq} ){  
	
		my $old_track = $this_track;
		add_mastering_tracks();
		add_mastering_effects();
		$this_track = $old_track;
	} else { unhide_mastering_tracks() }
	
}
sub master_off {

	$mastering_mode = 0;
	hide_mastering_tracks();
}


sub add_mastering_tracks {

	map{ 
		my $track = ::MasteringTrack->new(
			name => $_,
			rw => 'MON',
			group => 'Mastering', 
		);
		$ui->track_gui( $track->n );

 } @mastering_track_names;

}

sub add_mastering_effects {
	
	$this_track = $tn{Eq};

	command_process("append_effect $eq");

	$this_track = $tn{Low};

	command_process("append_effect $low_pass");
	command_process("append_effect $compressor");
	command_process("append_effect $spatialiser");

	$this_track = $tn{Mid};

	command_process("append_effect $mid_pass");
	command_process("append_effect $compressor");
	command_process("append_effect $spatialiser");

	$this_track = $tn{High};

	command_process("append_effect $high_pass");
	command_process("append_effect $compressor");
	command_process("append_effect $spatialiser");

	$this_track = $tn{Boost};
	
	command_process("append_effect $limiter"); # insert after vol
}

sub unhide_mastering_tracks {
	map{ $tn{$_}->set(hide => 0)} @mastering_track_names;
}

sub hide_mastering_tracks {
	map{ $tn{$_}->set(hide => 1)} @mastering_track_names;
 }
		
# vol/pan requirements of mastering tracks

{ my %volpan = (
	Eq => {},
	Low => {},
	Mid => {},
	High => {},
	Boost => {vol => 1},
);

sub need_vol_pan {
	my ($track_name, $type) = @_;
	return 1 unless $volpan{$track_name};
	return 1 if $volpan{$track_name}{$type};
	return 0;
} }
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
	else { warn "effect code not found: $input\n";}
	$code;
}
	# status_snapshot() 
	#
	# hashref output for detecting if we need to reconfigure engine
	# compared as YAML strings
	#
	# why is this different from $track_snapshots used for
	# dispatch()?
	#
	# for one, because dispatch() doesn't need to consider inserts,
	# which exist as temporary tracks at the time of dispatch()
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
		inserts
		rec_status
		current_version
 );
sub status_snapshot {

	
	my %snapshot = ( project 		=> 	$project_name,
					 mastering_mode => $mastering_mode,
					 preview        => $preview,
					 main_out 		=> $main_out,
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
	my $orig = $this_track;
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
	my ($name, $type, $id) = @_;
	if ($::Group::by_name{$name} or $tn{$name}){
		say qq(group, bus, or track "$name" already exists. Skipping."), return;
	}
	::SubBus->new( 
		name => $name, 
		bus_type => 'sub',
		groups => [$name],
		rules => [qw(rec_file)],
		destination_type => $type // 'track',
		destination_id	 => $id // $name,
		)
	or carp("can't create bus!\n"), return;
	::Group->new( name => $name, rw => 'REC');
	# create mix track
	
	::add_track($name, 	source_type => 'track', 
						source_id 	=> $name,
						rec_defeat 	=> 1,
						);
	
	
}
	
sub add_send_bus {

	my ($name, $dest_id, $bus_type) = @_;
	my $dest_type = dest_type( $dest_id );

	# dest_type: soundcard | jack_client | loop
	
	print "name: $name: dest_type: $dest_type dest_id: $dest_id\n";

	if ($::Bus::by_name{$name}){
		say qq(monitor bus "$name" already exists. Updating with new tracks.");

	} else {
	my @args = (
		name => $name, 
		bus_type => $bus_type,
		groups => [$name],
		rules => $bus_type eq 'cooked' 
			?  [qw(send_bus_out )]
			:  [qw(rec_setup mon_setup send_bus_out)],
		destination_type => $dest_type,
		destination_id	 => $dest_id,
	);

	my $bus = $bus_type eq 'cooked'
		?  ::SendBusCooked->new( @args ) 
		:  ::SendBusRaw->new( @args );

	$bus or carp("can't create bus!\n"), return;
	::Group->new( name => $name, rw => 'REC');
	}

	map{ ::SlaveTrack->new(	name => "$name\_$_", # BusName_TrackName
							rw => 'MON',
							target => $_,
							group  => $name,
							source_type => undef,
							source_id => undef,
							send_type => $dest_type, 
							send_id => $dest_id,
						)
   } $main->tracks;
		
}

sub dest_type { 
	my $dest = shift;
	if (defined $dest and ($dest !~ /\D/))        { 'soundcard' } # digits only
	elsif ($dest =~ /^loop,/) { 'loop' }
	elsif ($dest){  # any string 
		#carp( "$dest: jack_client doesn't exist.\n") unless jack_client($dest);
		'jack_client' ; }
	else { undef }
}
	
sub update_send_bus {
	my $name = shift;
		add_send_bus( $name, 
						 $::Bus::by_name{$name}->destination_id),
						 "dummy",
}

sub new_effect_chain_name {
	my $name = '_'.$this_track->name . '_';
	my $i;
	map{ my ($j) = /_(\d+)$/; $i = $j if $j > $i; }
	@{ $this_track->effect_chain_stack }, 
		grep{/$name/} keys %effect_chain;
	$name . ++$i
}

# too many functions in push and pop!!

sub push_effect_chain {
	say("no effects to store"), return unless $this_track->fancy_ops;
	my %vals = @_; 
	###my $add_name = $vals{add}; # undef in case of bypass # disabled!
	my $save_name   = $vals{save} || new_effect_chain_name();
	#$debug and say "add: $add_name save: $save_name"; 
	new_effect_chain( $save_name ); # current track effects
	push @{ $this_track->effect_chain_stack }, $save_name;
	map{ remove_effect($_)} $this_track->fancy_ops;
	###add_effect_chain($add_name) if $add_name; # disabled!
	#say "save name $save_name";
	$save_name;
}

sub pop_effect_chain { # restore previous, save current as name if supplied
	my $save_name = shift;
	my $previous = pop @{$this_track->effect_chain_stack};
	say ("no previous effect chain"), return unless $previous;
	if($save_name){ 
		push_effect_chain( save => $save_name, add => $previous);
	} 
	else { 
		map{ remove_effect($_)} $this_track->fancy_ops;
		add_effect_chain($previous);
	}
	delete $effect_chain{$previous};
}
sub uncache { 
	my $t = $this_track;
	# skip unless MON;
	my $cm = $t->cache_map;
	my $v = $t->monitor_version;
	if(is_cached()){
		# blast away any existing effects, TODO: warn or abort	
		say $t->name, ": removing effects (except vol/pan)" if $t->fancy_ops;
		map{ remove_effect($_)} $t->fancy_ops;
		$t->set(active => $cm->{$v}{original});
		print $t->name, ": setting uncached version ", $t->active, $/;
		add_effect_chain($cm->{$v}{effect_chain});
	} 
	else { print $t->name, ": version $v is not cached\n"}
}
sub is_cached {
	my $cm = $this_track->cache_map;
	$cm->{$this_track->monitor_version}
}
	

sub replace_effects { is_cached() ? uncache() : pop_effect_chain()}

sub new_effect_chain {
	my ($name, @ops) = @_;
#	say "name: $name, ops: @ops";
	@ops or @ops = $this_track->fancy_ops;
	$effect_chain{$name} = { 
					ops 	=> \@ops,
					type 	=> { map{$_ => $cops{$_}{type} 	} @ops},
					params	=> { map{$_ => $copp{$_} 		} @ops},
	}
}

sub add_effect_chain {
	my $name = shift;
	say ("$name: effect chain does not exist"), return 
		if ! $effect_chain{$name};
	map {  $magical_cop_id = $_ unless $cops{$_}; # try to reuse cop_id
			command_process( join " ", 
				'add_effect',
				$effect_chain{$name}{type}{$_}, 
				@{$effect_chain{$name}{params}{$_}});
			$magical_cop_id = undef;
	} @{$effect_chain{$name}{ops}};
			
}	
sub cleanup_exit {
 	remove_small_wavs();
 	kill 15, ecasound_pid() if $sock;  	
	$term->rl_deprep_terminal();
	CORE::exit; 
}
sub cache_track {
	print($this_track->name, ": track caching requires MON status.\n\n"), 
		return unless $this_track->rec_status eq 'MON';
	print($this_track->name, ": no effects to cache!  Skipping.\n\n"), 
		return unless $this_track->fancy_ops;
 	initialize_chain_setup_vars();
	my $orig = $this_track; 
	my $orig_version = $this_track->monitor_version;
	my $cooked = $this_track->name . '_cooked';
	::CacheRecTrack->new(
		width => 2,
		name => $cooked,
		group => 'Temp',
		target => $this_track->name,
	);
	$g->add_path( 'wav_in',$orig->name, $cooked, 'wav_out');
	add_paths_for_sub_buses();  # we will prune unneeded ones
	::Graph::expand_graph($g); # array ref
	::Graph::add_inserts($g);
	process_routing_graph(); 
	write_chains();
	maybe_write_chains() or say("nothing to do"), return;
	remove_temp_tracks();
	connect_transport('no_transport_status')
		or say ("Couldn't connect engine! Skipping."), return;
	say $/,$orig->name,": length ". d2($length). " seconds";
	say "Starting cache operation. Please wait.";
	eval_iam("cs-set-length $length");
	eval_iam("start");
	sleep 2; # time for transport to stabilize
	while( eval_iam('engine-status') ne 'finished'){ 
	print q(.); sleep 2; update_clock_display() } ; print " Done\n";
	$this_track = $orig;
	my $name = $this_track->name;
	my @files = grep{/$name/} new_files_were_recorded();
	if (@files ){ 
		$debug and say "updating track cache_map";
		#say "cache map",yaml_out($this_track->cache_map);
		my $cache_map = $this_track->cache_map;
		$cache_map->{$this_track->last} = { 
			original 			=> $orig_version,
			effect_chain	=> push_effect_chain(), # bypass
		};
		pop @{$this_track->effect_chain_stack};
		#say "cache map",yaml_out($this_track->cache_map);
		say qq(Saving effects for cached track "$name".
'replace' will restore effects and set version $orig_version\n);
		post_rec_configure();
	} else { say "track cache operation failed!"; }
}
sub do_script {
	say "hello script";
	my $name = shift;
	my $file;
	if( $name =~ m!/!){ $file = $name }
	else {
		$file = join_path(project_dir(),$name);
		if(-e $file){}
		else{ $file = join_path(project_root(),$name) }
	}
	-e $file or say("$file: file not found. Skipping"), return;
	my @lines = split "\n",io($file)->all;
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
	$main->set(rw => $old_group_status);
	1;
}
### end
