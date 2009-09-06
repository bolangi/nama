if ( can_load(modules => {'Time::HiRes'=> undef} ) ) 
	 { *sleeper = *finesleep;
		$hires++; }
else { *sleeper = *select_sleep }
	
sub finesleep {
	my $sec = shift;
	Time::HiRes::usleep($sec * 1e6);
}
sub select_sleep {
   my $seconds = shift;
   select( undef, undef, undef, $seconds );
# 	my $sec = shift;
# 	$sec = int($sec   + 0.5);
# 	$sec or $sec++;
# 	sleep $sec
}

sub mainloop { 
	prepare(); 
	command_process($execute_on_project_load);
	$ui->install_handlers();
	reconfigure_engine();
	$ui->loop;
}
sub status_vars {
	serialize( class => '::', vars => \@status_vars);
}
sub config_vars {
	serialize( class => '::', vars => \@config_vars);
}

sub discard_object {
	shift @_ if (ref $_[0]) =~ /Multitrack/;  # HARDCODED
	@_;
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
	
	
sub prepare {
	

	$debug2 and print "&prepare\n";
	

	$ecasound  = $ENV{ECASOUND} || q(ecasound);
	$e = Audio::Ecasound->new();
	
	
	$debug and print "started Ecasound\n";

	### Option Processing ###
	# push @ARGV, qw( -e  );
	#push @ARGV, qw(-d /media/sessions test-abc  );
	getopts('amcegstrd:f:D', \%opts); 
	#print join $/, (%opts);
	# a: save and reload ALSA state using alsactl
	# d: set project root dir
	# c: create project
	# f: specify configuration file
	# g: gui mode (default)
	# t: text mode 
	# m: don't load state info on initial startup
	# r: regenerate effects data cache
	# e: don't load static effects data (for debugging)
	# s: don't load static effects data cache (for debugging)
	# D: output debugging info
	
	# UI object for interface polymorphism
	

	if ($opts{D}){
		$debug = 1;
		$debug2 = 1;
	}
	if ( $opts{t} ){ 
		# text mode (Event.pm event loop)
		$ui = ::Text->new;
	} else {
		# default to graphic mode  (Tk event loop)
		if ( can_load( modules => { 'Tk' => undef } ) ){ 
			$ui = ::Graphical->new;
		} else { 
			print "Module Tk not found. Using Text mode.\n"; 
			$ui = ::Text->new;
		}
	}

	
	get_ecasound_iam_keywords();


	$project_name = shift @ARGV;
	$debug and print "project name: $project_name\n";

	$debug and print ("\%opts\n======\n", yaml_out(\%opts)); ; 


	read_config(global_config());  # from .namarc if we have one

	$debug and print "reading config file\n";
	if ($opts{d}){
		print "found command line project_root flag\n";
		$project_root = $opts{d};
	}

	# capture the sample frequency from .namarc
	($ladspa_sample_rate) = $devices{jack}{signal_format} =~ /(\d+)(,i)?$/;

	first_run();
	
	# init our buses
	
	$tracker_bus  = ::Bus->new(
		name => 'Tracker_Bus',
		groups => [qw(Tracker)],
		tracks => [],
		rules  => [ qw( mix_setup 
						rec_setup
						mon_setup 
						aux_send 
						rec_file) ],
	);

	# print join (" ", map{ $_->name} ::Rule::all_rules() ), $/;

	$master_bus  = ::Bus->new(
		name => 'Master_Bus',
		rules  => [ qw(mixer_out main_out) ],
		groups => ['Master'],
	);
	$mixdown_bus  = ::Bus->new(
		name => 'Mixdown_Bus',
		groups => [qw(Mixdown) ],
		rules  => [ qw(mix_setup_mon mix_file mix_ev) ],
	);

	# for metronome or other tracks using 'null' as source
	
	$null_bus = ::Bus->new(
		name => 'Null_Bus',
		groups => [qw(null) ],
		rules => [qw(null_setup)],
	);

	# Mastering chains
	
	# for bypass directly to Master
	#
	# we may prefer to use ecasound mute/bypass commands
	# on mastering chains instead of crossfading with this
	# chain
	
	$bypass_bus = ::Bus->new( 
		name => 'Bypass',
		rules => [qw(bypass)], # Similar to main_out
		tracks => ['Bypass']);

	# for EQ track

	$mastering_stage1_bus = ::Bus->new(
		name => 'Stage1',
		rules => ['stage1'], # loop_mix to loop_crossover
		tracks => ['Eq']);

	# for Low/Mid/High tracks
	
	$mastering_stage2_bus = ::Bus->new(
		name => 'Stage2',
		rules => ['stage2'], # loop_crossover to loop_boost
		tracks => [qw(Low Mid High)]);

	# for Final track with boost, limiter
	
	$mastering_stage3_bus = ::Bus->new(
		name => 'Stage3',
		rules => ['stage3'], #loop_boost to loop_output
		tracks => [qw(Boost)]);


	prepare_static_effects_data() unless $opts{e};

	load_keywords(); # for autocompletion
	chdir $project_root # for filename autocompletion
		or warn "$project_root: chdir failed: $!\n";

	# prepare_command_dispatch();  # unused

	#print "keys effect_i: ", join " ", keys %effect_i;
	#map{ print "i: $_, code: $effect_i{$_}->{code}\n" } keys %effect_i;
	#die "no keys";	
	
	initialize_rules(); # needed for transport_gui

	$ui->init_gui;
	$ui->transport_gui;
	$ui->time_gui;
	$ui->poll_jack();

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

sub eval_iam{
	#local $debug = 1;
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
	#print "config: $config";;
	my $yml = length $config > 100 ? $config : $default;
	#print "yml1: $yml";
	strip_all( $yml );
	#print "yml2: $yml";
	if ($yml !~ /^---/){
		$yml =~ s/^\n+//s;
		$yml =~ s/\n+$//s;
		$yml = join "\n", "---", $yml, "...";
	}
#	print "yml3: $yml";
	eval ('$yr->read($yml)') or croak( "Can't read YAML code: $@");
	%cfg = %{  $yr->read($yml)  };
	#print yaml_out( $cfg{abbreviations}); exit;
	*subst = \%{ $cfg{abbreviations} }; # alias
#	*devices = \%{ $cfg{devices} }; # alias
#	assigned by assign_var below
	#print yaml_out( \%subst ); exit;
	walk_tree(\%cfg);
	walk_tree(\%cfg); # second pass completes substitutions
	#print yaml_out \%cfg; 
	assign_var( \%cfg, @config_vars);  ## XXX
	#print "config file: $yml";
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
	#chdir project_dir();
	# read_config( global_config() ); 
	initialize_rules();
	initialize_project_data();
	remove_small_wavs(); 
	rememoize();

	retrieve_state( $h{settings} ? $h{settings} : $state_store_file) unless $opts{m} ;
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

sub initialize_rules {

	# first make some helper IO objects
	#
	# These objects provide code refs that alter their 
	# output based on whether JACK is running.
	#
	# Basically syntax to the Track methods that run the
	# necessary conditionals

	my $soundcard_input = ::IO->new(

		type => 	sub { my $track = shift; $track->soundcard_input()->[0]}, 
		object => 	sub { my $track = shift; $track->soundcard_input()->[1]},
	);

	my $soundcard_output = ::IO->new(

		type => 	sub { my $track = shift; $track->soundcard_output()->[0]}, 
		object => 	sub { my $track = shift; $track->soundcard_output()->[1]},
	);

	my $source_input = ::IO->new(
		type => 	sub { my $track = shift; $track->source_input()->[0]}, 
		object => 	sub { my $track = shift; $track->source_input()->[1]},
	);


	my $send_output = ::IO->new(
		type => 	sub { my $track = shift; $track->send_output()->[0]}, 
		object => 	sub { my $track = shift; $track->send_output()->[1]},
	);
 			

	package ::Rule;
		$n = 0;
		@by_index = ();	# return ref to Track by numeric key
		%by_name = ();	# return ref to Track by name
		%rule_names = (); 
	package ::;

# should we associate rule directly with track on creation?


	# combined outputs of user tracks
	
	$mixer_out = ::Rule->new( #  
		name			=> 'mixer_out', 
		chain_id		=> 1, # Master

		target			=> 'MON',

	# condition =>	sub{ defined $inputs{mixed}  
	# 	or $debug and print("no customers for mixed, skipping\n"), 0},

		input_type 		=> 'mixed', 
		input_object	=> $loop_mix, 

		output_type		=> 'mixed',
		output_object	=> \&mixer_target,
		status			=> 1,

	);

	# routes mixed signal to file

	$mix_down = ::Rule->new(

		name			=> 'mix_file', 

	# we change the track index away from the standard 2
	# for Mixdown to ensure no effects are applied.
	
		chain_id		=> 'MixDown',
		target			=> 'REC', 
		
		# sub{ defined $outputs{mixed} or $debug 
		#		and print("no customers for mixed, skipping mixdown\n"), 0}, 

		input_type 		=> 'mixed', # bus name
		input_object	=> $loop_output,

		output_type		=> 'file',
		output_object   => sub {
			my $track = shift; 
			join " ", $track->full_path, $mix_to_disk_format},

		status			=> 1,
	);

# the following rule is used by automix to normalize
# the track levels.

	$mix_down_ev = ::Rule->new(

		name			=> 'mix_ev', 
		chain_id		=> 1, # Master
		target			=> 'all', 
		
		input_type 		=> 'mixed',
		input_object	=> $loop_mix,

		output_type		=> 'device',
		output_object   => 'null',

		status			=> 0,
	);

	# routes output to JACK or sound card

	$main_out = ::Rule->new(

		name			=>  'main_out',
		chain_id		=>  'MainOut',
		target			=>  'all',
		condition 		=>	1,
		input_type		=>  'mixed',
		input_object	=>  $loop_output,
		output_type		=> $soundcard_output->type,
		output_object	=> $soundcard_output->object,
		status			=>  1,
		
	);

	# routes cooked track output to mixer 
	# generally optimized away by eliminate_loops()
	
	$mix_setup = ::Rule->new(

		name			=>  'mix_setup',
		chain_id		=>  sub { my $track = shift; "J". $track->n },
		target			=>  'all',
		input_type		=>  'cooked',
		input_object	=>  sub { my $track = shift; "loop," .  $track->n },
		output_object	=>  $loop_mix,
		output_type		=>  'cooked',
		condition 		=>  sub{ defined $inputs{mixed}->{$loop_output} },
		status			=>  1,
		
	);

	# for mix track only
	
	$mix_setup_mon = ::Rule->new(

		name			=>  'mix_setup_mon',
		chain_id		=>  sub { my $track = shift; "K". $track->n },
		target			=>  'MON',
		input_type		=>  'cooked',
		input_object	=>  sub{ my $track = shift; $track->full_path },
		output_type		=> $soundcard_output->type,
		output_object	=> $soundcard_output->object,
# 		output_type		=>  'mixed',
# 		output_object	=>  \&mixer_target,
		condition        => 1,
		status			=>  1,
		
	);


	# chains for inputs from WAV files
	# these chains receive all track effects

	$mon_setup = ::Rule->new(
		
		name			=>  'mon_setup', 
		target			=>  'MON',
		chain_id 		=>	sub{ my $track = shift; $track->n },
		input_type		=>  'file',
		input_object	=>  sub{ my $track = shift; $track->full_path },
		output_type		=>  'cooked',
		output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
		post_input		=>	sub{ my $track = shift; $track->mono_to_stereo},
		condition 		=> 1,
		status			=>  1,
	);

	# records live input to file
	# without going through track processing
		
	$rec_file = ::Rule->new(

		name			=> 'rec_file', 
		target			=> 'REC',
		chain_id		=> sub{ my $track = shift; 'R'. $track->n },   
		input_type		=> $source_input->type, # code ref
		input_object	=> $source_input->object, # code ref
		output_type		=>  'file',
		output_object   => sub {
			my $track = shift; 
			my $format = signal_format($raw_to_disk_format, $track->ch_count);
			join " ", $track->full_path, $format
		},
		post_input			=>	sub{ my $track = shift; $track->rec_route },
		status		=>  1,
	);

	# rec_setup 
	
	# convert live inputs to stereo if necessary
	# this chain takes all track effects
	
    $rec_setup = ::Rule->new(

		name			=>	'rec_setup', 
		chain_id		=>  sub{ my $track = shift; $track->n },   
		target			=>	'REC',
		input_type		=> $source_input->type,  #code ref
		input_object	=> $source_input->object,# code ref
		output_type		=>  'cooked',
		output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
		post_input			=>	sub{ my $track = shift;
										$track->rec_route .
										$track->mono_to_stereo 
										},
		condition 		=> sub { 

			my $track = shift; 
			return "satisfied" 
				unless ! defined $inputs{cooked}->{"loop," . $track->n}; 
		},
		status			=>  1,
	);


# aux_send 
# 
# send a 'cooked' signal to a soundcard output channel or JACK client

	
$aux_send = ::Rule->new(  


		name			=>  'aux_send', 
		target			=>  'all',
		chain_id 		=>	sub{ my $track = shift; "M".$track->n },
		input_type		=>  'cooked', 
		input_object	=>  sub{ my $track = shift; "loop," .  $track->n},
		output_type		=>  $send_output->type,
		output_object	=>  $send_output->object, 
		pre_output		=>	sub{ my $track = shift; $track->pre_send},
 		condition 		=> sub { my $track = shift; 
 								return "satisfied" if $track->send},
 									# and jack_client($track->send, 'input') } ,
		status			=>  1,
	);

# null_setup - for metronome tracks
#
# brings input from null device to mixer input


	$null_setup = ::Rule->new(
		
		name			=>  'null_setup', 
		target			=>  'all',
		chain_id 		=>	sub{ my $track = shift; $track->n },
		input_type		=>  'device',
		input_object	=>  'null',
		output_type		=>  'cooked',
		output_object	=>  $loop_mix,
		condition 		=>  sub{ defined $inputs{mixed}->{$loop_output} },
		status			=>  1,
# 		output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
		post_input		=>	sub{ my $track = shift; $track->mono_to_stereo},
		condition 		=> 1,
		status			=>  1,
	);

# rules for mastering mode

	$stage1 = ::Rule->new(
		name			=>  'stage1', 
		target			=>  'all',
		chain_id 		=>	sub{ my $track = shift; $track->n },
		input_type		=>  'mixed',
		input_object	=>  $loop_mastering,
		output_type		=>  'mixed',
		output_object	=>  $loop_crossover,
		status			=>  1,
	);
	$stage2 = ::Rule->new(
		name			=>  'stage2', 
		target			=>  'all',
		chain_id 		=>	sub{ my $track = shift; $track->n },
		input_type		=>  'mixed',
		input_object	=>  $loop_crossover,
		output_type		=>  'mixed',
		output_object	=>  $loop_boost,
		condition 		=>  sub{ $mastering_mode },
		status			=>  1,
	);
	$stage3 = ::Rule->new(
		name			=>  'stage3', 
		target			=>  'all',
		chain_id 		=>	sub{ my $track = shift; $track->n },
		input_type		=>  'mixed',
		input_object	=>  $loop_boost,
		output_type		=>  'mixed',
		output_object	=>  $loop_output,
		condition 		=>  sub{ $mastering_mode },
		status			=>  1,
	);
	
}

sub mixer_target { $mastering_mode ?  $loop_mastering : $loop_output}


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

	
sub eliminate_loops1 {
	#local $debug2 = 1;
	#local $debug  = 1;
	$debug2 and print "&eliminate_loops\n";
	# given track
	my $n = shift;
	my $loop_id = "loop,$n";
	return unless defined $inputs{cooked}->{$loop_id} 
		and scalar @{$inputs{cooked}->{$loop_id}} == 1;
	# get customer's id from cooked list and remove it from the list

	my $cooked_id = pop @{ $inputs{cooked}->{$loop_id} }; 

	# i.e. J3

	# add chain $n to the list of the customer's (rule's) output device 
	
	#my $rule  = grep{ $cooked_id =~ /$_->chain_id/ } ::Rule::all_rules();  
	my $rule = $mix_setup; 
	defined $outputs{cooked}->{$rule->output_object} 
	  or $outputs{cooked}->{$rule->output_object} = [];
	push @{ $outputs{cooked}->{$rule->output_object} }, $n;


	# remove chain $n as source for the loop

	delete $outputs{cooked}->{$loop_id}; 
	
	# remove customers that use loop as input

	delete $inputs{cooked}->{$loop_id}; 

	# remove cooked customer from his output device list
	# print "customers of output device ",
	#	$rule->output_object, join " ", @{
	#		$outputs{cooked}->{$rule->output_object} };
	#
	@{ $outputs{cooked}->{$rule->output_object} } = 
		grep{$_ ne $cooked_id} @{ $outputs{cooked}->{$rule->output_object} };

	#print $/,"customers of output device ",
	#	$rule->output_object, join " ", @{
	#		$outputs{cooked}->{$rule->output_object} };
	#		print $/;

	# transfer any intermediate processing to numeric chain,
	# deleting the source.
	$post_input{$n} .= $post_input{$cooked_id};
	$pre_output{$n} .= $pre_output{$cooked_id}; 
	delete $post_input{$cooked_id};
	delete $pre_output{$cooked_id};

	
}
sub eliminate_loops2 {

	# remove $loop_output when only one customer for $inputs{mixed}{$loop_output}

	my $ref = ref $inputs{mixed}{$loop_output};

	if (    $ref =~ /ARRAY/ and 
			(scalar @{$inputs{mixed}{$loop_output}} == 1) ){

		$debug and print "i have a loop to eliminate \n";
		my $customer_id = ${$inputs{mixed}{$loop_output}}[0];
		$debug and print "customer chain: $customer_id\n";

		delete $outputs{mixed}{$loop_output};
		delete $inputs{mixed}{$loop_output};

	$inputs{mixed}{$loop_mix} = [ $customer_id ];

	}
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
	
	%excluded = ();
	$old_snapshot = {};
	$preview = $initial_user_mode;
	$mastering_mode = 0;
	
	%bunch = ();	
	
	::Group::initialize();
	::Track::initialize();


	$master = ::Group->new(name => 'Master');
	$mixdown =  ::Group->new(name => 'Mixdown', rw => 'REC');
	$tracker = ::Group->new(name => 'Tracker', rw => 'REC');
	$mastering = ::Group->new(name =>'Mastering');
	$null    = ::Group->new(name => 'null');

	#print yaml_out( \%::Track::track_names );


# create magic tracks, we will create their GUI later, after retrieve

	$master_track = ::SimpleTrack->new( 
		group => 'Master', 
		name => 'Master',
		rw => 'MON',); # no dir, we won't record tracks


	$mixdown_track = ::Track->new( 
		group => 'Mixdown', 
		name => 'Mixdown', 
		rw => 'MON'); 

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

# create read-only track pointing at WAV files of specified
# name in current project

sub add_track_alias {
	my ($name, $track) = @_;
	my $target; 
	if 		( $tn{$track} ){ $target = $track }
	elsif	( $ti{$track} ){ $target = $ti{$track}->name }
	add_track(  $name, target => $target );
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

	my $group = $::Group::by_name{$track->group}; # $tracker, shurely
	#command_process('for mon; mon') if $preview;
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

sub dig_ruins { 
	

	# only if there are no tracks , 
	
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

#	}
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


sub all_chains {
	my @active_tracks = grep { $_->rec_status ne q(OFF) } ::Track::all() 
		if ::Track::all();
	map{ $_->n} @active_tracks if @active_tracks;
}

# return list of indices of user tracks with REC status

sub user_rec_tracks {
	my @user_tracks = ::Track::all();
	splice @user_tracks, 0, 2; # drop Master and Mixdown tracks
	return unless @user_tracks;
	my @user_rec_tracks = grep { $_->rec_status eq 'REC' } @user_tracks;
	return unless @user_rec_tracks;
	map{ $_->n } @user_rec_tracks;
}

# return list of indices of user tracks with REC status

sub user_mon_tracks {
	my @user_tracks = ::Track::all();
	splice @user_tracks, 0, 2; # drop Master and Mixdown tracks
	return unless @user_tracks;
	my @user_mon_tracks = grep { $_->rec_status eq 'MON' } @user_tracks;
	return unless @user_mon_tracks;
	map{ $_->n } @user_mon_tracks;

}

# return $output{file} entries
# - embedded format strings are included
# - mixdown track is included

sub really_recording {  

	keys %{$outputs{file}}; 
}

sub generate_setup { 

# Create data structures representing chain setup.
# This step precedes write_chains(), i.e. writing Setup.ecs.

	$debug2 and print "&generate_setup\n";


	%inputs = %outputs 
			= %post_input 
			= %pre_output 
			= @input_chains 
			= @output_chains 
			= ();
	
	# we don't want to go further unless there are signals
	# to process
	
	my @tracks = ::Track::all();

	shift @tracks; # drop Master

	my $have_source = join " ", map{$_->name} 
								grep{ $_ -> rec_status ne 'OFF'} 
								@tracks;

	#print "have source: $have_source\n";

	if ($have_source) {

		# process buses

		$debug and print "applying mixdown_bus\n";
		$mixdown_bus->apply; 
		$debug and print "applying master_bus\n";
		$master_bus->apply; 
		$debug and print "applying tracker_bus (user tracks)\n";
		$tracker_bus->apply;
		$debug and print "applying null_bus (user tracks)\n";
		$null_bus->apply;
		if ($mastering_mode){
			$debug and print "applying mastering buses\n";
			$mastering_stage1_bus->apply;
			$mastering_stage2_bus->apply;
			$mastering_stage3_bus->apply;
		}
		map{ eliminate_loops1($_) } all_chains();
		eliminate_loops2() unless $mastering_mode
			or useful_Master_effects();


		#print "minus loops\n \%inputs\n================\n", yaml_out(\%inputs);
		#print "\%outputs\n================\n", yaml_out(\%outputs);

		write_chains();
		return 1;
	} else { print "No inputs found!\n";
	return 0};
}

sub useful_Master_effects {

	# we have effects other than standard vol/pan
	scalar @{$tn{Master}->ops} > 2 

	or 
	# pan is not 50
	$copp{$tn{Master}->pan}->[0] != 50

	or
	# vol is not 100
	
	$copp{$tn{Master}->vol}->[0] != 100
}

sub write_chains {

	# generate Setup.ecs from %inputs and %outputs
	# by pushing lines onto @inputs and @outputs
	# and placing intermediate processing in %post_input and %pre_output

	$debug2 and print "&write_chains\n";

	# we assume that %inputs and %outputs will have the
	# same lowest-level keys, i.e. 'mixed' and 'cooked'
	#
	# @buses is not the right name...
	
	my @buses = grep { $_ !~ /file|device|jack/ } keys %inputs;
	
	### Setting devices as inputs 

		# these inputs are generated by rec_setup
	
	for my $dev (keys %{ $inputs{device} } ){

		$debug and print "dev: $dev\n";
		my @chain_ids = @{ $inputs{device}->{$dev} };
		#print "found ids: @chain_ids\n";

		# we treat $dev as a sound card
		# if $dev appears in config file %devices listing
		
		if ( $devices{$dev} ){
			push  @input_chains, 
			join " ", "-a:" . (join ",", @chain_ids),
			$devices{$dev}->{input_format} 
				? "-f:" .  $devices{$dev}->{input_format}
				: q(),
				"-i:" .  $devices{$dev}->{ecasound_id}, 
		} else { print <<WARN;
chains @chain_ids: device $dev not found in .namarc.  Skipping.

WARN
		}

	}


	#####  Setting jack_multi inputs

	for my $client (keys %{ $inputs{jack_multi} } ){

		my @chain_ids = @{ $inputs{jack_multi}->{$client} };
		#my $format;
		#$chain_ids[0] =~ /(\d+)/;
		#my $n = $1;
		push  @input_chains, 
		"-a:" . join(",",@chain_ids) . " -i:$client";
	}

	#####  Setting jack clients as inputs
 
	for my $client (keys %{ $inputs{jack} } ){

		my @chain_ids = @{ $inputs{jack}->{$client} };
		my $format;

		if ( $client eq 'system' ){ # we use the full soundcard width

			$format = signal_format(
				$devices{jack}->{signal_format},

				# client's output is our input
				jack_client($client,q(output)) 

			);

		} else { # we use track width

			$chain_ids[0] =~ /(\d+)/;
 			my $n = $1;
 			$debug and print "found chain id: $n\n";
			$format = signal_format(
						$devices{jack}->{signal_format},	
						$ti{$n}->ch_count
			);
		}
		push  @input_chains, 
			"-a:"
			. join(",",@chain_ids)
			. " -f:$format -i:jack,$client";
	}
		
	##### Setting files as inputs (used by mon_setup)

	for my $full_path (keys %{ $inputs{file} } ) {
		
		$debug and print "monitor input file: $full_path\n";
		my @chain_ids = @{ $inputs{file}->{$full_path} };

		my @chain_ids_no_modifiers = ();

		map {
			my ($chain) = /(\d+)/;
			my $track = $ti{$chain};
			if ( $track->playat_output 
					or $track->select_output
					or $track->modifiers ){

				#	single chain fragment

				my @modifiers;
				push @modifiers, $ti{$chain}->playat_output
					if $ti{$chain}->playat_output;
				push @modifiers, $ti{$chain}->select_output
					if $ti{$chain}->select_output;
				push @modifiers, split " ", $ti{$chain}->modifiers
					if $ti{$chain}->modifiers;

				push @input_chains, join ( " ",
						"-a:$_",
						"-i:".join(q[,],@modifiers,$full_path));
			} 
			else {

				# multiple chain fragment
				
				push @chain_ids_no_modifiers, $_
			}
     	} @chain_ids;
		if ( @chain_ids_no_modifiers ){ 

			push @input_chains, join ( " ",
						"-a:".join(q[,],@chain_ids_no_modifiers),
						"-i:".$full_path);
		} 

 	}

	### Setting loops as inputs 

	for my $bus( @buses ){ # i.e. 'mixed', 'cooked'
		for my $loop ( keys %{ $inputs{$bus} }){
			push  @input_chains, 
			join " ", 
				"-a:" . (join ",", @{ $inputs{$bus}->{$loop} }),
				"-i:$loop";
		}
	}
	#####  Setting devices as outputs
	#
	for my $dev ( keys %{ $outputs{device} }){
			my $format = $devices{$dev}->{output_format};
			push @output_chains, join " ",
				"-a:" . (join "," , @{ $outputs{device}->{$dev} }),
				($format ? "-f:$format" : q() ),
				"-o:". $devices{$dev}->{ecasound_id}; }

	#####  Setting jack_multi outputs 

	for my $client (keys %{ $outputs{jack_multi} } ){

		my @chain_ids = @{ $outputs{jack_multi}->{$client} };
		my $format;
		# extract track number to determine channel count
		$chain_ids[0] =~ /(\d+)/; 
		my $n = $1;
		$format = signal_format(
			$devices{jack}->{signal_format},	
			$ti{$n}->ch_count
			);
		push  @output_chains, 
		"-a:" . join(",",@chain_ids) 
				. " -f:$format" 
				. " -o:$client";
	}


	#####  Setting jack clients as outputs
 
	for my $client (keys %{ $outputs{jack} } ){

		my @chain_ids = @{ $outputs{jack}->{$client} };
		my $format;

		if ( $client eq 'system' ){ # we use the full soundcard width

			$format = signal_format(
				$devices{jack}->{signal_format},

				# client's input is our output
				jack_client($client,q(input))
			);

		} else { # we use track width

			$chain_ids[0] =~ /(\d+)/;
 			my $n = $1;
 			$debug and print "found chain id: $n\n";
			$format = signal_format(
						$devices{jack}->{signal_format},	
						$ti{$n}->ch_count
	 		);
		}
		push  @output_chains, 
			"-a:"
			. join(",",@chain_ids)
			. " -f:$format -o:jack,$client";
	}
		
	### Setting loops as outputs 

	for my $bus( @buses ){ # i.e. 'mixed', 'cooked'
		for my $loop ( keys %{ $outputs{$bus} }){
			push  @output_chains, 
			join " ", 
				"-a:" . (join ",", @{ $outputs{$bus}->{$loop} }),
				"-o:$loop";
		}
	}
	##### Setting files as outputs (used by rec_file and mix)

	for my $key ( keys %{ $outputs{file} } ){
		my ($full_path, $format) = split " ", $key;
		$debug and print "record output file: $full_path\n";
		my $chain_ids = join ",",@{ $outputs{file}->{$key} };
		
		push @output_chains, join ( " ",
			 "-a:".$chain_ids,
			 "-f:".$format,
			 "-o:".$full_path,
		 );
			 
			 
	}

	## write general options
	
	my $ecs_file = "# ecasound chainsetup file\n\n";
	$ecs_file   .= "# general\n\n";
	$ecs_file   .= $tn{Mixdown}->rec_status eq 'REC' 
					? $ecasound_globals_for_mixdown
					: $ecasound_globals;
	$ecs_file   .= "\n\n";
	$ecs_file   .= "# audio inputs\n\n";
	$ecs_file   .= join "\n", sort @input_chains;
	$ecs_file   .= "\n\n# post-input processing\n\n";
	$ecs_file   .= join "\n", sort map{ "-a:$_ $post_input{$_}"} keys %post_input;
	$ecs_file   .= "\n\n# pre-output processing\n\n";
	$ecs_file   .= join "\n", sort map{ "-a:$_ $pre_output{$_}"} keys %pre_output;
	$ecs_file   .= "\n\n# audio outputs";
	$ecs_file   .= join "\n", sort @output_chains, "\n";
	
	$debug and print "ECS:\n",$ecs_file;
	my $sf = join_path(&project_dir, $chain_setup_file);
	open my $setup, ">$sf";
	print $setup $ecs_file;
	close $setup;

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
		eval_iam"cs-remove" if eval_iam"cs-selected";
		eval_iam("cs-load ". $project_file);
		$debug and map{print "$_\n\n"}map{$e->eci($_)} qw(cs es fs st ctrl-status);
}
sub arm {

	# now that we have reconfigure_engine(), use is limited to 
	# - exiting preview
	# - automix	
	
	$debug2 and print "&arm\n";
	exit_preview();
	#adjust_latency();
	if( generate_setup() ){ connect_transport() };
}
sub preview {

	# set preview mode, releasing doodle mode if necessary
	
	$debug2 and print "&preview\n";

	# do nothing if already in 'preview' mode
	
	if ( $preview eq 'preview' ){ return }

	# make an announcement if we were in rec-enabled mode

	release_doodle_mode() if $preview eq 'doodle';

	$preview = "preview";
	$rec_file->set(status => 0);

	print "Setting preview mode.\n";
	print "Using both REC and MON inputs.\n";
	print "WAV recording is DISABLED.\n\n";
	print "Type 'arm' to enable recording.\n\n";
	# reconfigure_engine() will generate setup and start transport
}
sub doodle {

	# set doodle mode

	$debug2 and print "&doodle\n";
	return if engine_running() and really_recording();
	$preview = "doodle";
	$rec_file->set(status => 0);
	$mon_setup->set(status => 0);
	$unique_inputs_only = 1;

	# save rw setting of user tracks (not including null group)
	# and set those tracks to REC
	
	$old_group_rw = $tracker->rw;
	$tracker->set(rw => 'REC');
	$tn{Mixdown}->set(rw => 'OFF');
	
	# allow only unique inputs
	
	exclude_duplicate_inputs();

	# reconfigure_engine will generate setup and start transport
	
	print "Setting doodle mode.\n";
	print "Using live inputs only, with no duplicate inputs\n";
	print "Exit using 'preview' or 'arm' commands.\n";
}
sub reconfigure_engine {
	$debug2 and print "&reconfigure_engine\n";
	# sometimes we want to skip for debugging
	
	return 0 if $disable_auto_reconfigure;

	# we don't want to disturb recording/mixing
	return 1 if really_recording() and engine_running();

	# only act if change in configuration

	my $status_snapshot = status_snapshot();
	
	#print ("no change in setup\n"),
	 return 0 if yaml_out($old_snapshot) eq yaml_out($status_snapshot);

	# restore playback position unless 
	
	#  - doodle mode
	#  - change in global version
    #  - change in project
    #  - user or Mixdown track is REC enabled
	
	my $old_pos;

	my $will_record = ! $preview 
						&&  grep { $_->{rec_status} eq 'REC' } 
							@{ $status_snapshot->{tracks} };

	# restore playback position if possible

	if (	$preview eq 'doodle'
		 	or  $old_snapshot->{project} ne $status_snapshot->{project} 
			or  $old_snapshot->{global_version} 
					ne $status_snapshot->{global_version} 
			or  $will_record  ){

		$old_pos = undef;

	} else { $old_pos = eval_iam('getpos') }

	my $was_running = engine_running();
	stop_transport() if $was_running;

	if ( generate_setup() ){
		print STDOUT ::Text::show_tracks ( ::Track::all ) ;
		print STDOUT ::Text::show_tracks_extra_info();
		connect_transport();
		#eval_iam("setpos $old_pos") if $old_pos; # temp disable

	}
	$old_snapshot = $status_snapshot;
	start_transport() if $was_running and ! $will_record;
	$ui->flash_ready;
	1;
}

		
sub exit_preview { # exit preview and doodle modes

		$debug2 and print "&exit_preview\n";
		return unless $preview;
		stop_transport() if engine_running();
		$debug and print "Exiting preview/doodle mode\n";
		$preview = 0;
		release_doodle_mode();	

		$rec_file->set(status => 1);

}

sub release_doodle_mode {

		$debug2 and print "&release_doodle_mode\n";
		# restore preview group REC/MON/OFF setting
		$tracker->set(rw => $old_group_rw);		

		# enable playback from disk
		$mon_setup->set(status => 1);

		enable_excluded_inputs();

		# enable all rec inputs
		$unique_inputs_only = 0;
}
sub enable_excluded_inputs {

	$debug2 and print "&enable_excluded_inputs\n";
	return unless %old_rw;

	map { $tn{$_}->set(rw => $old_rw{$_}) } $tracker->tracks
		if $tracker->tracks;

	$tracker->set(rw => $old_group_rw);
	%old_rw = ();

}
sub exclude_duplicate_inputs {

	$debug2 and print "&exclude_duplicate_inputs\n";
	print ("already excluded duplicate inputs\n"), return if %old_rw;
	
 	if ( $tracker->tracks){
 		map { # print "track $_ "; 
			$old_rw{$_} = $tn{$_}->rw;
 		  	$tn{$_}->set(rw => 'REC');
 			# print "status: ", $tn{$_}->rw, $/ 
 		} $tracker->tracks;
 	}

		my @user = $tracker->tracks(); # track names
		%excluded = ();
		my %already_used;
		map{ my $source = $tn{$_}->source;
			 if( $already_used{$source}  ){
				$excluded{$_} = $tn{$_}->rw;
			 }
			 $already_used{$source}++
		 } grep { $tn{$_}->rec_status eq 'REC' } @user;
		if ( keys %excluded ){
#			print "Multiple tracks share same inputs.\n";
#			print "Excluding the following tracks: ", 
#				join(" ", keys %excluded), "\n";
			map{ $tn{$_}->set(rw => 'OFF') } keys %excluded;
		}
}

sub adjust_latency {

	$debug2 and print "&adjust_latency\n";
	map { $copp{$_->latency}[0] = 0  if $_->latency() } 
		::Track::all();
	preview();
	exit_preview();
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
	load_ecs(); 
	eval_iam("cs-selected") and	eval_iam("cs-is-valid")
		or print("Invalid chain setup, engine not ready.\n"),return;
	find_op_offsets(); 
	apply_ops();
	eval_iam('cs-connect');
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
	transport_status();
	$ui->flash_ready();
	#print eval_iam("fs");
	
}

sub transport_status {

	# assume transport is stopped
	# print looping status, setup length, current position
	
	my $start  = ::Mark::loop_start();
	my $end    = ::Mark::loop_end();
	#print "start: $start, end: $end, loop_enable: $loop_enable\n";
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
	print "setup length is ", d1($length), 
		($length > 120	?  " (" . colonize($length). ")" : "" )
		,$/;
	print "now at ", colonize( eval_iam( "getpos" )), $/;
	print "\nPress SPACE to start or stop engine.\n\n"
		unless (ref $ui) =~ /Graphical/;
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

	print "\nstarting at ", colonize(int (eval_iam"getpos")), $/;
	schedule_wraparound();
	$tn{Master}->mute unless really_recording();
	eval_iam('start');
	sleeper(0.5) unless really_recording();
	$tn{Master}->unmute;
	$ui->start_heartbeat();
	print "engine is ", eval_iam("engine-status"), "\n\n"; 

	sleep 1; # time for engine to stabilize
}
sub heartbeat {

	#	print "heartbeat fired\n";

	my $here   = eval_iam("getpos");
	my $status = eval_iam('engine-status');
	$ui->stop_heartbeat
		#if $status =~ /finished|error|stopped/;
		if $status =~ /finished|error/;
	#print join " ", $status, colonize($here), $/;
	my ($start, $end);
	$start  = ::Mark::loop_start();
	$end    = ::Mark::loop_end();
	$ui->schedule_wraparound() 
		if $loop_enable 
		and defined $start 
		and defined $end 
		and ! really_recording();

	# update time display
	#
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
		$ui->cancel_wraparound();
	} elsif ( $diff < 3 ) { #schedule the move
	$ui->wraparound($diff, $start);
		
		;
	}
}
sub stop_transport { 

	$debug2 and print "&stop_transport\n"; 
	$ui->stop_heartbeat();
	$tn{Master}->mute unless really_recording();
	$tn{Master}->mute if engine_running() and !really_recording();
	eval_iam('stop');	
	sleeper(0.5);
	print "\nengine is ", eval_iam("engine-status"), "\n\n"; 
	$tn{Master}->unmute;
	$ui->project_label_configure(-background => $old_bg);
	rec_cleanup();
}
sub transport_running {
#	$debug2 and print "&transport_running\n";
	 eval_iam('engine-status') eq 'running' ;
}
sub disconnect_transport {
	return if transport_running();
		eval_iam("cs-disconnect") if eval_iam("cs-connected");
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
	my $end = eval_iam(qq(cs-get-length)) - 10 ;  
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
 	my @k = really_recording();
	$debug and print "intended recordings: " , join $/, @k;
	return unless @k;
	print "I was recording!\n";
	my $recorded = 0;
 	for my $k (@k) {    
 		my ($n) = $outputs{file}{$k}[-1] =~ m/(\d+)/; 
		print "k: $k, n: $n\n";
		my $file = $k;
		$file =~ s/ .*$//;
 		my $test_wav = $file;
		$debug and print "track: $n, file: $test_wav\n";
 		my ($v) = ($test_wav =~ /_(\d+)\.wav$/); 
		$debug and print "n: $n\nv: $v\n";
		$debug and print "testing for $test_wav\n";
		if (-e $test_wav) {
			$debug and print "exists. ";
			if (-s $test_wav > 44100) { # 0.5s x 16 bits x 44100/s
				$debug and print "bigger than a breadbox.  \n";
				$ti{$n}->set(active => undef); 
				$ui->update_version_button($n, $v);
			$recorded++;
			}
			else { unlink $test_wav }
		}
	}
	rememoize();
	my $mixed = scalar ( grep{ /\bmix*.wav/i} @k );
	
	$debug and print "recorded: $recorded mixed: $mixed\n";
	if ( ($recorded -  $mixed) >= 1) {
			# i.e. there are first time recorded tracks
			$ui->global_version_buttons(); # recreate
			$tracker->set( rw => 'MON');
			$ui->refresh();
			print <<REC;
WAV files were recorded! 

Now reviewing your recording...

REC
			reconfigure_engine();
	}
		
} 

## effect functions

sub add_effect {
	
	$debug2 and print "&add_effect\n";
	
	my %p 			= %{shift()};
	my $n 			= $p{chain};
	my $code 			= $p{type};

	my $parent_id = $p{parent_id};  
	my $id		= $p{cop_id};   # initiates restore
	my $parameter		= $p{parameter};  # for controllers
	my $i = $effect_i{$code};
	my $values = $p{values};

	return if $id and ($id eq $ti{$n}->vol 
				or $id eq $ti{$n}->pan);   # skip these effects 
			   								# already created in add_track

	$id = cop_add(\%p); 
	my %pp = ( %p, cop_id => $id); # replace chainop id
	$ui->add_effect_gui(\%pp);
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
	#print "id $op_id p: $parameter, sign: $sign value: $value\n";

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
	return unless eval_iam('cs-is-valid');
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
	my %p 			= %{shift()};
	my $n 			= $p{chain};
	my $code		= $p{type};
	my $parent_id = $p{parent_id};  
	my $id		= $p{cop_id};   # causes restore behavior when present
	my $i       = $effect_i{$code};
	my @values = @{ $p{values} } if $p{values};
	my $parameter	= $p{parameter};  # needed for parameter controllers
	                                  # zero based
$debug and print <<PP;
n:          $n
code:       $code
parent_id:  $parent_id
cop_id:     $id
effect_i:   $i
parameter:  $parameter
PP

	return $id if $id; # do nothing if cop_id has been issued

	# make entry in %cops with chain, code, display-type, children

	$debug and print "Issuing a new cop_id for track $n: $cop_id\n";
	# from the cop_id, we may also need to know chain number and effect

	$cops{$cop_id} = {chain => $n, 
					  type => $code,
					  display => $effects[$i]->{display},
					  owns => [] }; # DEBUGGIN TEST

	$p{cop_id} = $cop_id;
 	cop_init( \%p );

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
	
	$copp{$cop_id} = \@values if @values; # needed for text mode

	$cop_id++; # return value then increment
}

sub cop_init {
	
	$debug2 and print "&cop_init\n";
	my $p = shift;
	my %p = %$p;
	my $id = $p{cop_id};
	my $parent_id = $p{parent_id};
	my $vals_ref  = $p{vals_ref};
	
	$debug and print "cop__id: $id\n";

	my @vals;
	if (ref $vals_ref) {
		@vals = @{ $vals_ref };
		$debug and print ("values supplied\n");
		@{ $copp{$id} } = @vals;
		return;
	} 
	else { 
		$debug and print "no settings found, loading defaults if present\n";
		my $i = $effect_i{ $cops{$id}->{type} };
		
		# don't initialize first parameter if operator has a parent
		# i.e. if operator is a controller
		
		for my $p ($parent_id ? 1 : 0..$effects[$i]->{count} - 1) {
		
			my $default = $effects[$i]->{params}->[$p]->{default};
			push @vals, $default;
		}
		@{ $copp{$id} } = @vals;
		$debug and print "copid: $id defaults: @vals \n";
	}
}

sub effect_update_copp_set {

	my ($id, $param, $val) = @_;
	effect_update( @_ );
	$copp{$id}->[$param] = $val;
}
	
	
sub effect_update {
	
	# why not use this routine to update %copp values as
	# well?
	
	#$debug2 and print "&effect_update\n";
	my $es = eval_iam"engine-status";
	$debug and print "engine is $es\n";
	return if $es !~ /not started|stopped|running/;

	my ($id, $param, $val) = @_;
	my $chain = $cops{$id}{chain};

	carp("effect $id: non-existent chain\n"), return
		unless $chain;

	$debug and print "chain $chain id $id param $param value $val\n";

	# $param gets incremented, therefore is zero-based. 
	# if I check i will find %copp is  zero-based

	return if $ti{$chain}->rec_status eq "OFF"; 
	return if $ti{$chain}->name eq 'Mixdown' and 
			  $ti{$chain}->rec_status eq 'REC';
 	$debug and print join " ", @_, "\n";	

	# update Ecasound's copy of the parameter

	$debug and print "valid: ", eval_iam("cs-is-valid"), "\n";
	my $controller; 
	for my $op (0..scalar @{ $ti{$chain}->ops } - 1) {
		$ti{$chain}->ops->[$op] eq $id and $controller = $op;
	}
	$param++; # so the value at $p[0] is applied to parameter 1
	$controller++; # translates 0th to chain-operator 1
	$debug and print 
	"cop_id $id:  track: $chain, controller: $controller, offset: ",
	$offset{$chain}, " param: $param, value: $val$/";
	eval_iam("c-select $chain");
	eval_iam("cop-select ". ($offset{$chain} + $controller));
	eval_iam("copp-select $param");
	eval_iam("copp-set $val");
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
# unused 
sub prepare_command_dispatch {
	map{ 
		if (my $subtext = $commands{$_}->{sub}){ # to_start
			my @short = split " ", $commands{$_}->{short};
			my @keys = $_;
			push @keys, @short if @short;
			map { $dispatch{$_} = eval qq(sub{ $subtext() }) } @keys;
		}
	} keys %commands;
# regex languge
#
my $key = qr/\w+/;
my $someval = qr/[\w.+-]+/;
my $sign = qr/[+-]/;
my $op_id = qr/[A-Z]+/;
my $parameter = qr/\d+/;
my $value = qr/[\d\.eE+-]+/; # -1.5e-6
my $dd = qr/\d+/;
my $name = qr/[\w:]+/;
my $name2 = qr/[\w-]+/;
my $name3 = qr/\S+/;
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

		if (  my ($_label) = /-(el:\w+)/  ){
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

		unlink $effects_cache;
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
	my $path = $ENV{LADSPA_PATH} || q(/usr/lib/ladspa);
	
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
		my ($short) = $code =~ /:(\w+)/;
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
		(\w.+?) # name, starting with word-char,  non-greedy
		\s+     # spaces
		-(el:\w+),? # ladspa_id maybe followed by comma
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
sub get_ladspa_hints{
	$debug2 and print "&get_ladspa_hints\n";
	$ENV{LADSPA_PATH} or local $ENV{LADSPA_PATH}='/usr/lib/ladspa';
	my @dirs =  split ':', $ENV{LADSPA_PATH};
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

	# first save palette to project_dir/palette.yml
	
	$debug and print "saving palette\n";
	$ui->save_palette;

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

# prepare marks data for storage (new Mark objects)

@marks_data = ();
$debug and print "copying marks data\n";
map { push @marks_data, $_->hashref } ::Mark::all();

$debug and print "copying groups data\n";
@groups_data = ();
map { push @groups_data, $_->hashref } ::Group::all();

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
		#		format => 'yaml', # breaks, stupid!
				class => '::');
}
sub retrieve_state {
	$debug2 and print "&retrieve_state\n";
	my $file = shift;
	$file = $file || $state_store_file;
	$file = join_path(project_dir(), $file);
	my $yamlfile = $file;
	$yamlfile .= ".yml" unless $yamlfile =~ /yml$/;
	$file = $yamlfile if -f $yamlfile;
	! -f $file and (print "file not found: $file\n"), return;
	$debug and print "using file: $file\n";

	assign_var($file, @persistent_vars );

	##  print yaml_out \@groups_data; 
	# %cops: correct 'owns' null (from YAML) to empty array []
	
	#  set group parameters

	map {my $g = $_; 
		map{
			$::Group::by_index[$g->{n}]->set($_ => $g->{$_})
			} keys %{$g};
	} @groups_data;

	#  set Master and Mixdown parmeters
	


	map {my $t = $_; 
			my %track = %{$t};
		map{

			$ti{$t->{n}}->set($_ => $t->{$_})
			} keys %track;
	} @tracks_data[0,1];

	my @master_mix_tracks_data = splice @tracks_data, 0, 2;

	$ui->create_master_and_mix_tracks(); 

	# create user tracks
	
	my $did_apply = 0;

	map{ 
		my %h = %$_; 
		#print "old n: $h{n}\n";
		#print "h: ", join " ", %h, $/;
		#delete $h{n};
		$::Track::n = $h{n} if $h{n};
		#my @hh = %h; print "size: ", scalar @hh, $/;
		my $track = ::Track->new( %h ) ;
		# set the correct class for mastering tracks
		bless $track, '::MasteringTrack' if $track->group eq 'Mastering';
		my $n = $track->n;
		#print "new n: $n\n";
		$debug and print "restoring track: $n\n";
		$ui->track_gui($n); 
		restore_track_effects( $n );
		
	} @tracks_data;
	#print "\n---\n", $tracker->dump;  
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

sub restore_track_effects {
	my $n = shift; # track number
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
	print qq(No chain setup available.
Perhaps you need to create some tracks to record/play.
), return unless -f $setup;
	my $chain_setup;
	io( $setup ) > $chain_setup; 
	pager( $chain_setup );
}
sub pager {
	$debug2 and print "&pager\n";
	my @output = @_;
	my ($screen_lines, $columns) = split " ", qx(stty size);
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
				grep{ ! $reserved{$_} } split " ", eval_iam('int-cmd-list');
}

sub process_line {
	$debug2 and print "&process_line\n";
	my ($user_input) = @_;
	$debug and print "user input: $user_input\n";
	if (defined $user_input and $user_input !~ /^\s*$/) {
		$term->addhistory($user_input) 
			unless $user_input eq $previous_text_command;
		$previous_text_command = $user_input;
		enable_excluded_inputs() if $preview eq 'doodle';
		command_process( $user_input );
		exclude_duplicate_inputs() if $preview eq 'doodle';
		reconfigure_engine();
	}
}


sub command_process {
	my $user_input = shift;
	return if $user_input =~ /^\s*$/;
	$debug and print "user input: $user_input\n";
	my ($cmd, $predicate) = ($user_input =~ /([\S]+?)\b(.*)/);
	if ($cmd eq 'for' 
			and my ($bunchy, $do) = $predicate =~ /\s*(.+?)\s*;(.+)/){
		$debug and print "bunch: $bunchy do: $do\n";
		my @tracks;
		if ( lc $bunchy eq 'all' ){
			$debug and print "special bunch: all\n";
			@tracks = ::Track::user();
		} elsif ( lc $bunchy eq 'rec' ){
			$debug and print "special bunch: rec\n";
			@tracks = grep{$tn{$_}->rec_status eq 'REC'} ::Track::user();
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
				my $c = q(c-select ) . $this_track->n; eval_iam( $c );
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
}

sub complete {
    my ($text, $line, $start, $end) = @_;
#	print join $/, $text, $line, $start, $end, $/;
    return $term->completion_matches($text,\&keyword);
};

{
    my $i;
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
    }
};

sub jack_update {
	# cache current JACK status
	$jack_running = jack_running();
	$jack_lsp = qx(jack_lsp -Ap 2> /dev/null); 
}
sub jack_client {

	# returns true if client and direction exist
	# returns number of client ports
	
	my ($name, $direction)  = @_;

	# synth:in_1 input
	# synth input
	
	my $port;
	($name, $port) = $name =~ /^([^:]+):?(.*)/;

	# currently we ignore port
	
	$jack_running or return;
	my $j = $jack_lsp; 
	#return if $j =~ /JACK server not running/;

	# convert to single lines

	$j =~ s/\n\s+/ /sg;

	# system:capture_1 alsa_pcm:capture_1 properties: output,physical,terminal,

	my %jack;

	map{ 
		my ($direction) = /properties: (input|output)/;
		s/properties:.+//;
		my @ports = /(\w+:\w+ )/g;
		map { 
				s/ $//; # remove trailing space
				$jack{ $_ }{ $direction }++;
				my ($client, $port) = /(\w+):(\w+)/;
				$jack{ $client }{ $direction }++;

		 } @ports;

	} split "\n",$j;
	#print yaml_out \%jack;
	
	$jack{$name}{$direction};
}

sub automix {

	# use Smart::Comments '###';
	# add -ev to mixtrack
	my $ev = add_effect( { chain => $master->n, type => 'ev' } );
	### ev id: $ev

	# use Ecasound globals for mixdown 
	# mixplay() below restores normal values
	
	# turn off audio output
	
	$main_out->set(status => 0);

	# turn off mix_file rule
	$mix_down->set(   status => 0);

	# turn on mix_down_ev
	$mix_down_ev->set(status => 1);

	### Status before mixdown:

	command_process('show');

	### reduce track volume levels  to 10%
	
	command_process( 'for mon; vol/10');

	#command_process('show');
	
	command_process('arm; start');

	while( eval_iam('engine-status') ne 'finished'){ 
		print q(.); sleep 5; $ui->refresh } ; print "Done\n";

	# parse cop status
	my $cs = eval_iam('cop-status');
	my $cs_re = qr/Chain "2".+?result-max-multiplier ([\.\d]+)/s;
	my ($multiplier) = $cs =~ /$cs_re/;

	### multiplier: $multiplier

	if ( $multiplier - 1 > 0.01 ){

		### apply multiplier to individual tracks

		command_process( "for mon; vol*$multiplier" );

		# keep same audible output volume: UNUSED
		
	#	my $master_multiplier = $multiplier/10;


		### master multiplier: $multiplier/10

		# command_process("Master; vol/$master_multiplier")


	}
	remove_effect($ev);
	
	### turn off 
	$mix_down_ev->set(status => 0);

	### turn on mix_file
	$mix_down->set(status => 1);

	### mixdown
	command_process('mixdown');

	command_process('show');

	command_process('arm; start');

	while( eval_iam('engine-status') ne 'finished'){ 
		print q(.); sleep 5; $ui->refresh } ; print "Done\n";

	### turn on audio output output

	$main_out->set(status => 1);

	### default to playing back Mixdown track, setting user tracks to OFF

	command_process('mixplay');
	
#	no Smart::Comments;
	
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



sub master_off {

	$mastering_mode = 0;
	hide_mastering_tracks();
}

sub unhide_mastering_tracks {
	map{ $tn{$_}->set(hide => 0)} @mastering_track_names;
}

sub hide_mastering_tracks {
	map{ $tn{$_}->set(hide => 1)} @mastering_track_names;
 }
		
# vol/pan requirements of mastering tracks

my %volpan = (
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
	else { warn "effect code not found: $input\n";}
	$code;
}

sub status_snapshot {

	# hashref output for detecting if we need to reconfigure
	# engine
	
	my %snapshot = ( project 		=> 	$project_name,
					 global_version =>  $tracker->version,
					 mastering_mode => $mastering_mode,
					 preview        => $preview,
					 main 			=> $main_out->status,
#					 global_rw      =>  $tracker->rw,
					
 );
	$snapshot{tracks} = [];
	map { 
		push @{ $snapshot{tracks} }, 
			{
				name 			=> $_->name,
				rec_status 		=> $_->rec_status,
				channel_count 	=> $_->ch_count,
				current_version => $_->current_version,
				send 			=> $_->send,
				source 			=> $_->source,
				shift			=> $_->playat,
				region_start    => $_->region_start,
				region_end    	=> $_->region_ending,

				
			} unless $_->rec_status eq 'OFF'

	} ::Track::all();
	\%snapshot
}
sub set_region {
	my ($beg, $end) = @_;
	$::this_track->set(region_start => $beg);
	$::this_track->set(region_end => $end);
	::Text::show_region();
}
	
### end
