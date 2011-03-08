# ----------- Modes: mastering, preview, doodle ---------

package ::;
use Modern::Perl;
our (
	$debug,
	$debug2,
	$preview,
	$main,
	$old_group_rw,
	%tn,
	$mastering_mode,
	@mastering_track_names,
	$ui,
	$this_track,
	$compressor,
	$spatialiser,
	$low_pass,
	$mid_pass,
	$high_pass,
	$limiter,
	$eq,
);

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
	return if engine_running() and ::ChainSetup::really_recording();
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
sub exit_preview_mode { # exit preview and doodle modes

		$debug2 and print "&exit_preview_mode\n";
		return unless $preview;
		stop_transport() if engine_running();
		$debug and print "Exiting preview/doodle mode\n";
		$preview = 0;
		$main->set(rw => $old_group_rw) if $old_group_rw;

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
		
1;
__END__
