# ----------- Engine Setup and Teardown -----------

package ::;
use Modern::Perl;
use ::Log qw(logpkg);
no warnings 'uninitialized';

sub generate_setup { 

	# return 1 if successful
	# catch errors from generate_setup_try() and cleanup
	logsub("&generate_setup");

	# extra argument (setup code) will be passed to generate_setup_try()
	# my ($extra_setup_code) = @_;

	# save current track
	local $this_track;

	# prevent engine from starting an old setup
	
	eval_iam('cs-disconnect') if eval_iam('cs-connected');

	::ChainSetup::initialize();

	
	# this is our chance to save state without the noise
	# of temporary tracks, avoiding the issue of getting diffs 
	# in the project data from each new chain setup.
	autosave() if $config->{autosave} eq 'setup'
					and $project->{name}
					and $config->{use_git} 
					and $project->{repo};
	
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

	logsub("&reconfigure_engine");
	my $force = shift;

	# skip if command line option is set
	# don't skip if $force argument given
	
	return if ($config->{opts}->{R} or $config->{disable_auto_reconfigure})
		and not $force;

	# don't disturb recording/mixing
	
	return if ::ChainSetup::really_recording() and engine_running();
	
	# store a lists of wav-recording tracks for the rerecord
	# function
	
	restart_wav_memoize(); # check if someone has snuck in some files
	
	find_duplicate_inputs(); # we will warn the user later

	if( $force or $setup->{changed} ){ 
		logpkg('debug',"reconfigure requested");
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

	$old_offset_run_status = $mode->{offset_run};

	process_command('show_tracks');

	{ local $quiet = 1; stop_transport() }

	trigger_rec_cleanup_hooks();
	trigger_rec_setup_hooks();
	$setup->{_old_rec_status} = { 
		map{$_->name => $_->rec_status } ::Track::rec_hookable()
	};
	if ( generate_setup() ){
	
		reset_latency_compensation() if $config->{opts}->{Q};
		
		logpkg('debug',"I generated a new setup");
		
		{ local $quiet = 1; connect_transport() }
		propagate_latency() if $config->{opts}->{Q} and $jack->{jackd_running};
		show_status();

		eval_iam("setpos $project->{playback_position}")
 				if $project->{playback_position}
					and not ::ChainSetup::really_recording();
		start_transport('quiet') if $mode->eager 
								and ($mode->doodle or $mode->preview);
		transport_status();
		$ui->flash_ready;
		1
	}
}
}
sub request_setup { 
	my ($package, $filename, $line) = caller();
    logpkg('debug',"reconfigure requested in file $filename:$line");
	$setup->{changed}++
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
		n
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
					 mastering_mode => $mode->mastering,
					 preview        => $mode->{preview},
					 jack_running	=> $jack->{jackd_running},
					 tracks			=> [], );
	map { push @{$snapshot{tracks}}, $_->snapshot(\@relevant_track_fields) }
	grep{ $_->rec_status ne 'OFF' } grep { $_->group ne 'Temp' } ::Track::all();
	\%snapshot;
}
sub status_snapshot_string { json_out(status_snapshot()) }
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
	logsub("&arm");
	exit_preview_mode();
	reconfigure_engine('force');
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
	remove_riff_header_stubs();

	register_other_ports(); # that don't belong to my upcoming instance
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
	$setup->{audio_length} = eval_iam('cs-get-length'); # returns zero if unknown
	sync_effect_parameters();
	register_own_ports(); # as distinct from other Nama instances
	$ui->length_display(-text => colonize($setup->{audio_length}));
	eval_iam("cs-set-length $setup->{audio_length}") if $tn{Mixdown}->rec_status eq 'REC' and $setup->{audio_length};
	$ui->clock_config(-text => colonize(0));
	sleeper(0.2); # time for ecasound engine to launch

	# set delay for seeking under JACK
	# we use a heuristic based on the number of tracks
	# but it should be based on the number of MON tracks
	
	my $track_count; map{ $track_count++ } ::ChainSetup::engine_tracks();
	$this_engine->{jack_seek_delay} = $jack->{jackd_running}
		?  $config->{engine_base_jack_seek_delay} * ( 1 + $track_count / 20 )
		:  0;
	connect_jack_ports_list();
	transport_status() unless $quiet;
	$ui->flash_ready();
	#print eval_iam("fs");
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

sub trigger_rec_setup_hooks {
	map { system($_->rec_setup_script) } 
	grep
	{ 
		logpkg('trace',
			join "\n",
			"track ".$_->name,
			"rec status is: ".$_->rec_status,
			"old rec status: ".$setup->{_old_rec_status}->{$_->name},
			"script was ". (-e $_->rec_setup_script ) ? "found" : "not found"
		);
		$_->rec_status eq 'REC' 
		and $setup->{_old_rec_status}->{$_->name} ne 'REC'
		and -e $_->rec_setup_script
	} 
	::Track::rec_hookable();
}	
 sub trigger_rec_cleanup_hooks {
 	map { system($_->rec_cleanup_script) } 
	grep
	{ 	$_->rec_status ne 'REC' 
		and $setup->{_old_rec_status}->{$_->name} eq 'REC'
		and -e $_->rec_cleanup_script
	}
	::Track::rec_hookable();
}
1;
__END__
