# ----------- Engine Setup and Teardown -----------

package ::;
use Modern::Perl;
our (
	$debug,
	$debug2,
	$regenerate_setup,
	$length,
	$ui,
	$seek_delay,
	$jack_seek_delay,
);	

sub load_ecs {
	my $setup = setup_file();
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
	$regenerate_setup++;
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
	$length = eval_iam('cs-get-length'); 
	$ui->length_display(-text => colonize($length));
	# eval_iam("cs-set-length $length") unless @record;
	$ui->clock_config(-text => colonize(0));
	sleeper(0.2); # time for ecasound engine to launch
	{ # set delay for seeking under JACK
	my $track_count; map{ $track_count++ } engine_tracks();
	$seek_delay = $jack_seek_delay || 0.1 + 0.1 * $track_count / 20;
	}
	connect_jack_ports_list();
	transport_status() unless $quiet;
	$ui->flash_ready();
	#print eval_iam("fs");
	1;
	
}
1;
__END__
