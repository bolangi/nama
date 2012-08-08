# ------------- Realtime control routines -----------

## loading and running the Ecasound engine

package ::;
use Modern::Perl; use Carp;
no warnings 'uninitialized';
use ::Util qw(process_is_running);

# support both 'stop' and 'stop-sync' commands

{ my $stop_command = undef;
sub stop_command {
	return unless engine_running();
	return eval_iam($stop_command) if $stop_command;
	$stop_command = 'stop-sync';
	eval_iam($stop_command);
	return unless engine_running();
	$stop_command = 'stop';
	eval_iam($stop_command);
}
}


sub valid_engine_setup {
	eval_iam("cs-selected") and eval_iam("cs-is-valid");
}
sub engine_running {
	eval_iam("engine-status") eq "running"
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
	
sub start_transport { 

	my $quiet = shift;

	# set up looping event if needed
	# mute unless recording
	# start
	# wait 0.5s
	# unmute
	# start heartbeat
	# report engine status
	# sleep 1s

	logsub("&start_transport");
	say("\nCannot start. Engine is not configured.\n"),return 
		unless eval_iam("cs-connected");

	say "\n\nStarting at ", current_position() unless $quiet;
	schedule_wraparound();
	mute();
	eval_iam('start');

	# limit engine run time if we are in mixdown or edit mode, 
	# or if requested by user, set timer to specified time
	# defaulting to the result of cs-get-length
	
	limit_processing_time( $setup->{runtime_limit} || $setup->{audio_length}) 
		if mixing_only() 
		or edit_mode() 
		or defined $setup->{runtime_limit};
		# TODO and live processing
 	#$engine->{events}->{post_start_unmute} = AE::timer(0.5, 0, sub{unmute()});
	sleeper(0.5);
	unmute();
	sleeper(0.5);
	$ui->set_engine_mode_color_display();
	start_heartbeat();
	engine_status() unless $quiet;
}
sub stop_transport { 

	my $quiet = shift;
	logsub("&stop_transport"); 
	my $pos = eval_iam('getpos') if eval_iam('cs-connected');
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
	
	eval_iam("setpos $pos") if $pos;
}
sub toggle_transport {
	if (engine_running()){ stop_transport() } 
	else { start_transport() }
}

sub transport_running { eval_iam('engine-status') eq 'running'  }

sub disconnect_transport {
	return if transport_running();
	teardown_engine();
}
sub engine_is {
	my $pos = shift;
	"Engine is ". eval_iam("engine-status"). ( $pos ? " at $pos" : "" )
}
sub engine_status { 
	my ($pos, $before_newlines, $after_newlines) = @_;
	say "\n" x $before_newlines, engine_is($pos), "\n" x $after_newlines;
}
sub current_position { colonize(int eval_iam("getpos")) }

sub start_heartbeat {
 	$engine->{events}->{poll_engine} = AE::timer(0, 1, \&::heartbeat);
}

sub stop_heartbeat {
	$engine->{events}->{poll_engine} = undef; 
	$ui->reset_engine_mode_color_display();
	rec_cleanup() }

sub heartbeat {

	#	print "heartbeat fired\n";

	my $here   = eval_iam("getpos");
	my $status = eval_iam('engine-status');
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
	my $here   = eval_iam("getpos");
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
	$engine->{events}->{wraparound} = undef;
}
sub limit_processing_time {
	my $length = shift;
 	$engine->{events}->{processing_time} 
		= AE::timer($length, 0, sub { ::stop_transport(); print prompt() });
}
sub disable_length_timer {
	$engine->{events}->{processing_time} = undef; 
	undef $setup->{runtime_limit};
}
sub wraparound {
	package ::;
	my ($diff, $start) = @_;
	#print "diff: $diff, start: $start\n";
	$engine->{events}->{wraparound} = undef;
	$engine->{events}->{wraparound} = AE::timer($diff,0, sub{set_position($start)});
}
sub ecasound_select_chain {
	my $n = shift;
	my $cmd = "c-select $n";

	if( 
		# specified chain exists in the chain setup
		::ChainSetup::is_ecasound_chain($n)

		# engine is configured
		and eval_iam( 'cs-connected' ) =~ /$file->{chain_setup}->[0]/

	){ 	eval_iam($cmd); 
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
		eval_iam('start');
		$result
}
sub restart_ecasound {
	pager3("killing ecasound processes @{$engine->{pids}}");
	kill_my_ecasound_processes();
	pager3(q(restarting Ecasound engine - your may need to use the "arm" command));	
	select_ecasound_interface();
	#$setup->{changed}++;
	reconfigure_engine();
}
sub kill_my_ecasound_processes {
	my @signals = (15, 9);
	map{ kill $_, @{$engine->{pids}}; sleeper(1)} @signals;
}


1;
__END__
