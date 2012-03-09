# ----------- Engine Setup and Teardown -----------

package ::;
use Modern::Perl;
no warnings 'uninitialized';
use ::Globals qw(:all);

sub generate_setup { 

	# return 1 if successful
	# catch errors from generate_setup_try() and cleanup
	$debug2 and print "&generate_setup\n";

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
	remove_temporary_tracks();  # cleanup
	track_unmemoize(); 			# unfreeze track state
	if ($@){
		say("error caught while generating setup: $@");
		::ChainSetup::initialize() unless $debug;
		return
	}
	$success;
}
sub remove_temporary_tracks {
	$debug2 and say "&remove_temporary_tracks";
	map { $_->remove  } grep{ $_->group eq 'Temp'} ::Track::all();
}

{ my $old_offset_run_status;
sub reconfigure_engine {
	$debug2 and print "&reconfigure_engine\n";

	# skip if command line option is set
	return if $config->{opts}->{R};

	return if $config->{disable_auto_reconfigure};

	# don't disturb recording/mixing
	return if ::ChainSetup::really_recording() and engine_running();
	
	# store recorded trackrefs if any for re-record function
	#
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
				$debug and print("no change in setup\n");
				return;
		}
	}
	$debug and print("setup change\n");

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
		
		$debug and say "I generated a new setup";
		
		# we save:
		# + monitoring setups 
		# + preview setups
		# + doodle setups
		
		git_snapshot() unless really_recording(); 

		connect_transport('quiet');
		::Text::show_status();

		if( $restore_position and not ::ChainSetup::really_recording()){
			eval_iam("setpos $old_pos") if $old_pos and $old_pos < $setup->{audio_length};
		}
		start_transport('quiet') if $was_running
			or $mode->{preview} =~ /doodle|preview/;
		transport_status();
		$ui->flash_ready;
	}
}
}
	# status_snapshot() 
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
	$debug2 and print "&find_duplicate_inputs\n";
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
	$setup->{changed}++;
	generate_setup() and connect_transport();
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
	$setup->{audio_length} = eval_iam('cs-get-length'); 
	$ui->length_display(-text => colonize($setup->{audio_length}));
	# eval_iam("cs-set-length $setup->{audio_length}") unless @record;
	$ui->clock_config(-text => colonize(0));
	sleeper(0.2); # time for ecasound engine to launch

	# set delay for seeking under JACK
	
	my $track_count; map{ $track_count++ } ::ChainSetup::engine_tracks();
	$config->{engine_jack_seek_delay} = $config->{engine_base_jack_seek_delay} * ( 1 + $track_count / 20 );

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
sub adjust_latency {

	$debug2 and print "&adjust_latency\n";
	map { $fx->{params}->{$_->latency}[0] = 0  if $_->latency() } 
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
	map { my $adjustment = ($max - $latency{$_}) / $config->{sampling_freq} * 1000;
			$debug and print "chain: $_, adjustment: $adjustment\n";
			effect_update_copp_set($ti{$_}->latency, 2, $adjustment);
			} keys %latency;
}
1;
__END__
