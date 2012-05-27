# ----------- Engine Setup and Teardown -----------

package ::;
use Modern::Perl;
no warnings 'uninitialized';

sub generate_setup { 

	# return 1 if successful
	# catch errors from generate_setup_try() and cleanup
	logsub("&generate_setup");

	# save current track
	local $this_track;

	# prevent engine from starting an old setup
	
	eval_iam('cs-disconnect') if eval_iam('cs-connected');

	::ChainSetup::initialize();

	$setup->{audio_length} = 0;  # TODO replace global with sub
	# TODO: use try/catch
	# catch errors unless testing (no-terminal option)
	local $@ unless $config->{opts}->{T}; 
	track_memoize(); 			# freeze track state 
	my $success = $config->{opts}->{T}      # don't catch errors during testing 
		?  ::ChainSetup::generate_setup_try(@_)
		:  eval { ::ChainSetup::generate_setup_try(@_) }; 
	track_unmemoize(); 			# unfreeze track state
	if ($@){
		say("error caught while generating setup: $@");
		::ChainSetup::initialize();
		return
	}
	$success;
}

{ my $old_offset_run_status;
sub reconfigure_engine {

	my $force = shift;

	logsub("&reconfigure_engine");

	# skip if command line option is set
	# don't skip if $force argument given
	
	return if ($config->{opts}->{R} or $config->{disable_auto_reconfigure})
		and not $force;

	# don't disturb recording/mixing
	
	return if ::ChainSetup::really_recording() and engine_running();
	
	# store recorded trackrefs if any for re-record function
	
	# an empty set (e.g. in post-record monitoring)
	# will not overwrite a previous set
	
	if( my @rec_tracks = ::ChainSetup::engine_wav_out_tracks() )
	{
		$setup->{_last_rec_tracks} = \@rec_tracks;
	}

	rememoize(); # check if someone has snuck in some files
	
	find_duplicate_inputs(); # we will warn the user later

	# only act if change in configuration
	# skip check if regenerate_setup flag is already set
	
	if( $setup->{changed} ){ 
		$setup->{changed} = 0; # reset for next time
	} 
	else {
		my $current = yaml_out(status_snapshot());
		my $old = yaml_out($setup->{_old_snapshot});
		if ( $current eq $old){
				logpkg('debug',"no change in setup");
				return;
		}
	}
	logpkg('debug',"setup change");


	##### Restore previous position and running status

 	my $old_pos;
 	my $was_running;
	my $restore_position;
	my $previous_snapshot = $setup->{_old_snapshot};

	# restore previous playback position unless 

	#  - doodle mode
	#  - change in global version (TODO)
	#  - change in project
	#  - new setup involves recording
	#  - change in edit mode
	
	if ( 	$mode->{preview} eq 'doodle' 
		 or $setup->{_old_snapshot}->{project} ne $project->{name}
		 or $mode->{offset_run} != $old_offset_run_status
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

	$setup->{_old_snapshot} = status_snapshot();
	$old_offset_run_status = $mode->{offset_run};

	command_process('show_tracks');

	stop_transport('quiet') if $was_running;


	if ( generate_setup() ){
		
		logpkg('debug',"I generated a new setup");
		
		# we save:
		# + monitoring setups 
		# + preview setups
		# + doodle setups
		
		git_snapshot() unless ::ChainSetup::really_recording(); 

		connect_transport('quiet');

		show_status();

		if( $restore_position and not ::ChainSetup::really_recording()){
			eval_iam("setpos $old_pos") if $old_pos and $old_pos < $setup->{audio_length};
		}
		start_transport('quiet') if $mode->{preview} =~ /doodle/;
			# $was_running or
		transport_status();
		$ui->flash_ready;
	}
}
}


#### status_snapshot() 
	#
	# hashref output for detecting if we need to reconfigure engine
	# compared as YAML strings


	# %status_snaphot indicates Nama's internal
	# state. It consists of 
	# - the values of selected global variables
	# - selected field values of each track
	

	
{

	# these track fields will be inspected
	
	my @relevant_track_fields = qw(
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

	
	my %snapshot = ( project 		=> 	$project->{name},
					 mastering_mode => $mode->{mastering},
					 preview        => $mode->{preview},
					 jack_running	=> $jack->{jackd_running},
					 tracks			=> [], );
	map { push @{$snapshot{tracks}}, $_->snapshot(\@relevant_track_fields) }
	::Track::all();
	\%snapshot;
}
}
sub find_duplicate_inputs { # in Main bus only

	%{$setup->{tracks_with_duplicate_inputs}} = ();
	%{$setup->{inputs_used}} = ();
	logsub("&find_duplicate_inputs");
	map{	my $source = $_->source;
			$setup->{tracks_with_duplicate_inputs}->{$_->name}++ if $setup->{inputs_used}->{$source} ;
		 	$setup->{inputs_used}->{$source} //= $_->name;
	} 
	grep { $_->rw eq 'REC' }
	map{ $tn{$_} }
	$bn{Main}->tracks(); # track names;
}
sub load_ecs {
	my $setup = $file->chain_setup;
	#say "setup file: $setup " . ( -e $setup ? "exists" : "");
	return unless -e $setup;
	#say "passed conditional";
	teardown_engine();
	eval_iam("cs-load $setup");
	eval_iam("cs-select $setup"); # needed by Audio::Ecasound, but not Net-ECI !!
	logpkg('debug',sub{map{eval_iam($_)} qw(cs es fs st ctrl-status)});
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
	
	logsub("&arm");
	exit_preview_mode();
	$setup->{changed}++;
	generate_setup() and connect_transport();
}

# substitute all live inputs by clock-sync'ed 
# Ecasound null device 'rtnull'

sub arm_rtnull {

local %::IO::io_class = qw(
	null_in					::IO::from_null
	null_out				::IO::to_null
	soundcard_in 			::IO::from_rtnull
	soundcard_out 			::IO::to_rtnull
	wav_in 					::IO::from_wav
	wav_out 				::IO::to_wav
	loop_source				::IO::from_loop
	loop_sink				::IO::to_loop
	jack_manual_in			::IO::from_rtnull
	jack_manual_out			::IO::to_rtnull
	jack_ports_list_in		::IO::from_rtnull
	jack_ports_list_out		::IO::to_rtnull
	jack_multi_in			::IO::from_rtnull
	jack_multi_out			::IO::to_rtnull
	jack_client_in			::IO::from_rtnull
	jack_client_out			::IO::to_rtnull
	);

arm();

}

sub connect_transport {
	logsub("&connect_transport");
	my $quiet = shift;
	remove_riff_header_stubs();

	# paired with calculate_and_adjust_latency() below
	remove_latency_ops() unless $config->{opts}->{O}; 

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
	$setup->{audio_length} = eval_iam('cs-get-length'); 
	sync_effect_parameters();
	$ui->length_display(-text => colonize($setup->{audio_length}));
	# eval_iam("cs-set-length $setup->{audio_length}") unless @record;
	$ui->clock_config(-text => colonize(0));
	sleeper(0.2); # time for ecasound engine to launch

	# set delay for seeking under JACK
	
	my $track_count; map{ $track_count++ } ::ChainSetup::engine_tracks();
	$engine->{jack_seek_delay} = $jack->{jackd_running}
		?  $config->{engine_base_jack_seek_delay} * ( 1 + $track_count / 20 )
		:  0;
	connect_jack_ports_list();
	transport_status() unless $quiet;
	$ui->flash_ready();
	#print eval_iam("fs");
	calculate_and_adjust_latency() unless $config->{opts}->{O};
	1;
	
}
sub transport_status {
	
	map{ 
		say("Warning: $_: input ",$tn{$_}->source,
		" is already used by track ",$setup->{inputs_used}->{$tn{$_}->source},".")
		if $setup->{tracks_with_duplicate_inputs}->{$_};
	} grep { $tn{$_}->rec_status eq 'REC' } $bn{Main}->tracks;


	# assume transport is stopped
	# print looping status, setup length, current position
	my $start  = ::Mark::loop_start();
	my $end    = ::Mark::loop_end();
	#print "start: $start, end: $end, loop_enable: $mode->{loop_enable}\n";
	if (ref $setup->{cooked_record_pending} and %{$setup->{cooked_record_pending}}){
		say join(" ", keys %{$setup->{cooked_record_pending}}), ": ready for caching";
	}
	if ($mode->{loop_enable} and $start and $end){
		#if (! $end){  $end = $start; $start = 0}
		say "looping from ", heuristic_time($start),
				 	"to ",   heuristic_time($end);
	}
	say "\nNow at: ", current_position();
	say "Engine is ". ( engine_running() ? "running." : "ready.");
	say "\nPress SPACE to start or stop engine.\n"
		if $config->{press_space_to_start};
}
1;
__END__
