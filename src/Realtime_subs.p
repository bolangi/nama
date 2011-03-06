# ------------- Realtime control routines -----------

## loading and running the Ecasound engine

package ::;
use Modern::Perl;
use ::Util qw(process_is_running really_recording);

our (
	$debug,
	$debug2,
	$this_track,
	$old_this_track,
	$preview,
	$main,
	%tn,
	%opts,
	$regenerate_setup,
	$old_snapshot,
	$project_name,
	$offset_run_flag,
	$length,
	$ui,
	$old_group_rw,
	$disable_auto_reconfigure,
);

sub valid_engine_setup {
	eval_iam("cs-selected") and eval_iam("cs-is-valid");
}
sub engine_running {
	eval_iam("engine-status") eq "running"
};


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
1;
__END__
