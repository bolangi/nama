package ::EcasoundRun;
use Role::Tiny;
use Modern::Perl;
use ::Globals qw(:all);
use ::Log qw(logpkg logsub);
sub start { 
	my $self = shift; 
	package ::;

	audio_run_ready() 
		and ecasound("cs-connected") 
		or throw("\nAudio engine is not configured. Cannot start.\n"),return;


	if (audio_run_ready())
	{
	# use gradual unmuting to avoid pop on start
	# 
	#
	# mute unless recording
	# start
	# wait 0.5s
	# unmute
	# start heartbeat
	# report engine status
	# sleep 1s
	#

	pager("\n\nStarting at ", current_position()) unless $quiet;
	schedule_wraparound();
	mute();
	ecasound('start');
	start_midi_transport() if midi_run_ready();

	# limit engine run time if we are in mixdown or edit mode, 
	# or if requested by user, set timer to specified time
	# defaulting to the result of cs-get-length
	
	limit_processing_time( $setup->{runtime_limit} || $setup->{audio_length}) 
		if mixing_only() 
		or edit_mode() 
		or defined $setup->{runtime_limit};
		# TODO and live processing
 	#$project->{events}->{post_start_unmute} = AE::timer(0.5, 0, sub{unmute()});
	sleeper(0.5);
	unmute();
	sleeper(0.5);
	$ui->set_engine_mode_color_display();
	start_heartbeat();
	engine_status() unless $quiet;
	}
}
sub stop {
	package ::;
	if (engine_running())
	{
	# Since the playback position advances slightly during
	# the fade, we restore the position to exactly where the
	# stop command was issued.
	
	my $pos;
	$pos = ecasound('getpos') if ecasound('cs-connected')
		and ! ::ChainSetup::really_recording();
	mute();
	stop_command();
	disable_length_timer();
	if ( ! $quiet ){
		sleeper(0.5);
		engine_status(current_position(),2,0);
	}
	unmute();
	stop_heartbeat();
	$ui->project_label_configure(-background => $gui->{_old_bg});

	# restore exact position transport stop command was issued
	
	set_position($pos) if $pos
	}
}
1
