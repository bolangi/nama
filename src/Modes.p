# ----------- Modes: mastering, preview, doodle ---------

package ::;
use Modern::Perl;
{
my $old_group_rw; # for restore on exiting doodle/preview mode

sub set_preview_mode {

	# set preview mode, releasing doodle mode if necessary
	
	logsub("&preview");

	# do nothing if already in 'preview' mode
	
	if ( $mode->{preview} eq 'preview' ){ return }

	$mode->{preview} = "preview";

	print "Setting preview mode.\n";
	print "Using both REC and MON inputs.\n";
	print "WAV recording is DISABLED.\n\n";
	print "Type 'arm' to enable recording.\n\n";
	# reconfigure_engine() will generate setup and start transport
}
sub set_doodle_mode {

	logsub("&doodle");
	return if engine_running() and ::ChainSetup::really_recording();
	$mode->{preview} = "doodle";

	$tn{Mixdown}->set(rw => 'OFF');
	
	# reconfigure_engine will generate setup and start transport
	
	print "Setting doodle mode.\n";
	print "Using live inputs only, no duplicate inputs\n";
	print "Exit using 'preview' or 'arm' commands.\n";
}
sub exit_preview_mode { # exit preview and doodle modes

		logsub("&exit_preview_mode");
		return unless $mode->{preview};
		stop_transport() if engine_running();
		logit('::Mode','debug', "Exiting preview/doodle mode");
		$mode->{preview} = 0;

}

sub restore_preview_mode { 
	$mode->{preview} = $mode->{eager};
}

}

sub master_on {

	return if $mode->{mastering};
	
	# set $mode->{mastering}	
	
	$mode->{mastering}++;

	# create mastering tracks if needed
	
	if ( ! $tn{Eq} ){  
	
		local $this_track;
		add_mastering_tracks();
		add_mastering_effects();
	} else { 
		unhide_mastering_tracks();
		map{ $ui->track_gui($tn{$_}->n) } @{$mastering->{track_names}};
	}

}
	
sub master_off {

	$mode->{mastering} = 0;
	hide_mastering_tracks();
	map{ $ui->remove_track_gui($tn{$_}->n) } @{$mastering->{track_names}};
	$this_track = $tn{Master} if grep{ $this_track->name eq $_} @{$mastering->{track_names}};
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

 	} grep{ $_ ne 'Boost' } @{$mastering->{track_names}};
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

	command_process("add_effect $mastering->{fx_eq}");

	$this_track = $tn{Low};

	command_process("add_effect $mastering->{fx_low_pass}");
	command_process("add_effect $mastering->{fx_compressor}");
	command_process("add_effect $mastering->{fx_spatialiser}");

	$this_track = $tn{Mid};

	command_process("add_effect $mastering->{fx_mid_pass}");
	command_process("add_effect $mastering->{fx_compressor}");
	command_process("add_effect $mastering->{fx_spatialiser}");

	$this_track = $tn{High};

	command_process("add_effect $mastering->{fx_high_pass}");
	command_process("add_effect $mastering->{fx_compressor}");
	command_process("add_effect $mastering->{fx_spatialiser}");

	$this_track = $tn{Boost};
	
	command_process("add_effect $mastering->{fx_limiter}"); # insert after vol
}

sub unhide_mastering_tracks {
	command_process("for Mastering; set_track hide 0");
}

sub hide_mastering_tracks {
	command_process("for Mastering; set_track hide 1");
 }
		
1;
__END__
