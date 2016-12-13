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
### routines defined in the root namespace

package ::;
use Modern::Perl; use Carp;
no warnings 'uninitialized';
use ::Util qw(process_is_running);

# support both 'stop' and 'stop-sync' commands

{ my $stop_command = undef;
sub stop_command {
	return unless engine_running();
	return ecasound($stop_command) if $stop_command;
	$stop_command = 'stop-sync';
	ecasound($stop_command);
	return unless engine_running();
	$stop_command = 'stop';
	ecasound($stop_command);
}
}


sub valid_engine_setup {
	ecasound("cs-selected") and ecasound("cs-is-valid");
}
sub engine_running {
	ecasound("engine-status") eq "running"
};


sub mixing_only {
	my $i;
	my $am_mixing;
	for (::ChainSetup::really_recording()){
		$i++;
		$am_mixing++ if /Mixdown/;
	}
	$i == 1 and $am_mixing
}

sub sync_transport_position { }

sub midish_running { $setup->{midish_running} }
	

sub toggle_transport {
	if (engine_running()){ stop_transport() } 
	else { start_transport() }
}

sub transport_running { ecasound('engine-status') eq 'running'  }

sub disconnect_transport {
	return if transport_running();
	teardown_engine();
}
sub engine_is {
	my $pos = shift;
	"Engine is ". ecasound("engine-status"). ( $pos ? " at $pos" : "" )
}
sub engine_status { 
	my ($pos, $before_newlines, $after_newlines) = @_;
	pager("\n" x $before_newlines, engine_is($pos), "\n" x $after_newlines);
}
sub current_position { 
	my $pos = ecasound("getpos"); 
	colonize(int($pos || 0)) 
}
sub start_heartbeat {
 	$project->{events}->{poll_engine} = AE::timer(0, 1, \&::heartbeat);
}

sub stop_heartbeat {
	# the following test avoids double-tripping rec_cleanup()
	# following manual stop
	return unless $project->{events}->{poll_engine};
	undef $project->{events}->{poll_engine};
	$ui->reset_engine_mode_color_display();
	rec_cleanup() 
}
sub heartbeat {

	#	print "heartbeat fired\n";

	my $here   = ecasound("getpos");
	my $status = ecasound('engine-status');
	if( $status =~ /finished|error/ ){
		engine_status(current_position(),2,1);
		revise_prompt();
		stop_heartbeat(); 
		sleeper(0.2);
		set_position(0);
	}
		#if $status =~ /finished|error|stopped/;
	#print join " ", $status, colonize($here), $/;
	my ($start, $end);
	$start  = ::Mark::loop_start();
	$end    = ::Mark::loop_end();
	schedule_wraparound() 
		if $mode->{loop_enable} 
		and defined $start 
		and defined $end 
		and ! ::ChainSetup::really_recording();

	update_clock_display();

}

sub update_clock_display { 
	$ui->clock_config(-text => current_position());
}
sub schedule_wraparound {

	return unless $mode->{loop_enable};
	my $here   = ecasound("getpos");
	my $start  = ::Mark::loop_start();
	my $end    = ::Mark::loop_end();
	my $diff = $end - $here;
	logpkg('debug', "here: $here, start: $start, end: $end, diff: $diff");
	if ( $diff < 0 ){ # go at once
		set_position($start);
		cancel_wraparound();
	} elsif ( $diff < 3 ) { #schedule the move
		wraparound($diff, $start);
	}
}
sub cancel_wraparound {
	$project->{events}->{wraparound} = undef;
}
sub limit_processing_time {
	my $length = shift;
 	$project->{events}->{processing_time} 
		= AE::timer($length, 0, sub { ::stop_transport(); print prompt() });
}
sub disable_length_timer {
	$project->{events}->{processing_time} = undef; 
	undef $setup->{runtime_limit};
}
sub wraparound {
	my ($diff, $start) = @_;
	#print "diff: $diff, start: $start\n";
	$project->{events}->{wraparound} = undef;
	$project->{events}->{wraparound} = AE::timer($diff,0, sub{set_position($start)});
}
sub ecasound_select_chain {
	my $n = shift;
	my $cmd = "c-select $n";

	if( 
		# specified chain exists in the chain setup
		::ChainSetup::is_ecasound_chain($n)

		# engine is configured
		and ecasound( 'cs-connected' ) =~ /$file->{chain_setup}->[0]/

	){ 	ecasound($cmd); 
		return 1 

	} else { 
		logpkg('trace',
			"c-select $n: attempted to select non-existing Ecasound chain"); 
		return 0
	}
}
sub stop_do_start {
	my ($coderef, $delay) = @_;
	engine_running() ?  _stop_do_start( $coderef, $delay)
					 : $coderef->()

}
sub _stop_do_start {
	my ($coderef, $delay) = @_;
		stop_command();
		my $result = $coderef->();
		sleeper($delay) if $delay;
		ecasound('start');
		$result
}
sub restart_ecasound {
	pager_newline("killing ecasound processes @{$en{Nama}->{pids}}");
	kill_my_ecasound_processes();
	pager_newline(q(restarting Ecasound engine - your may need to use the "arm" command));	
	select_ecasound_interface();
	reconfigure_engine('force');
}
sub kill_my_ecasound_processes {
	my @signals = (15, 9);
	map{ kill $_, @{$en{Nama}->{pids}}; sleeper(1)} @signals;
}


1
