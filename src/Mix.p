package ::;
use Modern::Perl;

sub check_level {

	my $track = shift;

	my $ev = add_effect( { track => $track, type => 'ev' } );

	# disable Master so unused tracks are pruned
	
	$tn{Master}->set(rw => 'OFF'); 

	# direct target track to null
	
	my $null_routing = 
	sub { 	my $g = shift;
			$g->add_path($track->name, output_node('null')) };
	generate_setup($null_routing) 
		or say("check_level: generate_setup failed!"), return;
	connect_transport();
	
	eval_iam('start'); # don't use heartbeat
	sleep 2; # time for engine to stabilize
	while( eval_iam('engine-status') ne 'finished'){ 
		print q(.); sleep 1; update_clock_display()}; 
	print " Done\n";

	my $cs = eval_iam('cop-status');

	my ($level_output) = $cs =~ /Status info:\s*?\n(.+)\z/s;
	::mandatory_pager($level_output);

	# restore previous state
	
	remove_effect($ev);
	$tn{Master}->set(rw => 'MON'); 
	$setup->{changed}++;
}

sub automix {

	# get working track set
	
	my @tracks = grep{
					$tn{$_}->rec_status eq 'MON' or
					$bn{$_} and $tn{$_}->rec_status eq 'REC'
				 } $bn{Main}->tracks;

	say "tracks: @tracks";

	## we do not allow automix if inserts are present	

	say("Cannot perform automix if inserts are present. Skipping."), return
		if grep{$tn{$_}->prefader_insert || $tn{$_}->postfader_insert} @tracks;

	#use Smart::Comments '###';
	# add -ev to summed signal
	my $ev = add_effect( { chain => $tn{Master}->n, type => 'ev' } );
	### ev id: $ev

	# turn off audio output
	
	my $old_send_type = $tn{Master}->{send_type};
	my $old_send_id   = $tn{Master}->{send_id};

	$tn{Master}->set(send_type => 'null', send_id => 'null');

	### Status before mixdown:

	process_command('show');

	
	### reduce track volume levels  to 10%

	## accommodate ea and eadb volume controls

	my $vol_operator = type($tn{$tracks[0]}->vol);

	my $reduce_vol_command  = $vol_operator eq 'ea' ? 'vol / 10' : 'vol - 10';
	my $restore_vol_command = $vol_operator eq 'ea' ? 'vol * 10' : 'vol + 10';

	### reduce vol command: $reduce_vol_command

	for (@tracks){ process_command("$_  $reduce_vol_command") }

	process_command('show');

	generate_setup('automix') # pass a bit of magic
		or say("automix: generate_setup failed!"), return;
	connect_transport();
	
	# start_transport() does a rec_cleanup() on transport stop
	
	eval_iam('start'); # don't use heartbeat
	sleep 2; # time for engine to stabilize
	while( eval_iam('engine-status') ne 'finished'){ 
		print q(.); sleep 1; update_clock_display()}; 
	print " Done\n";

	# parse cop status
	my $cs = eval_iam('cop-status');
	### cs: $cs
	my $cs_re = qr/Chain "1".+?result-max-multiplier ([\.\d]+)/s;
	my ($multiplier) = $cs =~ /$cs_re/;

	### multiplier: $multiplier

	remove_effect($ev);

	# deal with all silence case, where multiplier is 0.00000
	
	if ( $multiplier < 0.00001 ){

		say "Signal appears to be silence. Skipping.";
		for (@tracks){ process_command("$_  $restore_vol_command") }
		$tn{Master}->set(rw => 'MON');
		return;
	}

	### apply multiplier to individual tracks

	for (@tracks){ process_command( "$_ vol*$multiplier" ) }

	### mixdown
	process_command('mixdown; arm; start');

	### restore audio output

	$tn{Master}->set( send_type => $old_send_type, send_id => $old_send_id); 

	#no Smart::Comments;
	
}
1
__END__
