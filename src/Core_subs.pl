sub main { 
#	setup_grammar(); 		# executes directly in body
	process_options(); 		# Option_subs.pm
	initialize_interfaces();# Initialize_subs.pm
	command_process($execute_on_project_load);
	reconfigure_engine();	# Engine_setup_sups.pm
	command_process($opts{X});
	$ui->loop;
}

## User Customization -- called by initialize_interfaces()
#  we leave it here because it needs access to all global variables

sub setup_user_customization {
	my $file = user_customization_file();
	return unless -r $file;
	say "reading user customization file $user_customization_file";
	my @return;
	unless (@return = do $file) {
		say "couldn't parse $file: $@\n" if $@;
		return;
	}
	# convert key-value pairs to hash
	$debug and print join "\n",@return;
	my %custom = @return ; 
	my $prompt;
	$prompt = gen_coderef('prompt', $custom{prompt}) if $custom{prompt};
	{ no warnings 'redefine';
		*prompt = $prompt if $prompt;
	}
	my @commands = keys %{ $custom{commands} };
	for my $cmd(@commands){
		my $coderef = gen_coderef($cmd,$custom{commands}{$cmd}) or next;
		$user_command{$cmd} = $coderef;
	}
	%user_alias   = %{ $custom{aliases}  };
}
sub user_customization_file { join_path(project_root(),$user_customization_file) }

sub gen_coderef {
	my ($cmd,$code) = @_;
	my $coderef = eval "sub{ use feature ':5.10'; $code }";
	say("couldn't parse command $cmd: $@"), return if $@;
	$coderef
}

# called from grammar

sub do_user_command {
	#say "args: @_";
	my($cmd, @args) = @_;
	$user_command{$cmd}->(@args);
}	

# called from ChainSetup.pm and Engine_setup_subs.pm

sub setup_file { join_path( project_dir(), $chain_setup_file) };



# throw away first argument

sub discard_object {
	shift @_ if (ref $_[0]) =~ /Nama/;
	@_;
}


sub debugging_options {
	grep{$_} $debug, @opts{qw(R D J A E T)};
}
sub process_control_inputs { }


sub dump_all {
	my $tmp = ".dump_all";
	my $fname = join_path( project_root(), $tmp);
	save_state($fname);
	file_pager("$fname.yml");
}


sub show_io {
	my $output = yaml_out( \%inputs ). yaml_out( \%outputs ); 
	pager( $output );
}

sub command_process {
	my $input = shift;
	my $input_was = $input;

	# parse repeatedly until all input is consumed
	
	while ($input =~ /\S/) { 
		$debug and say "input: $input";
		$parser->meta(\$input) or print("bad command: $input_was\n"), last;
	}
	$ui->refresh; # in case we have a graphic environment
	set_current_bus();
}


sub leading_track_spec {
	my $cmd = shift;
	if( my $track = $tn{$cmd} || $ti{$cmd} ){
		$debug and print "Selecting track ",$track->name,"\n";
		$this_track = $track;
		set_current_bus();
		ecasound_select_chain( $this_track->n );
		1;
	}
		
}
sub eval_perl {
	my $code = shift;
	my (@result) = eval $code;
	print( "Perl command failed: $@\n") if $@;
	pager(join "\n", @result) unless $@;
	print "\n";
}	

sub is_bunch {
	my $name = shift;
	$bn{$name} or $bunch{$name}
}
my %set_stat = ( 
				 (map{ $_ => 'rw' } qw(rec mon off) ), 
				 map{ $_ => 'rec_status' } qw(REC MON OFF)
				 );

sub bunch_tracks {
	my $bunchy = shift;
	my @tracks;
	if ( my $bus = $bn{$bunchy}){
		@tracks = $bus->tracks;
	} elsif ( $bunchy eq 'bus' ){
		$debug and print "special bunch: bus\n";
		@tracks = grep{ ! $bn{$_} } $bn{$this_bus}->tracks;
	} elsif ($bunchy =~ /\s/  # multiple identifiers
		or $tn{$bunchy} 
		or $bunchy !~ /\D/ and $ti{$bunchy}){ 
			$debug and print "multiple tracks found\n";
			# verify all tracks are correctly named
			my @track_ids = split " ", $bunchy;
			my @illegal = grep{ ! track_from_name_or_index($_) } @track_ids;
			if ( @illegal ){
				say("Invalid track ids: @illegal.  Skipping.");
			} else { @tracks = map{ $_->name} 
							   map{ track_from_name_or_index($_)} @track_ids; }

	} elsif ( my $method = $set_stat{$bunchy} ){
		$debug and say "special bunch: $bunchy, method: $method";
		$bunchy = uc $bunchy;
		@tracks = grep{$tn{$_}->$method eq $bunchy} 
				$bn{$this_bus}->tracks
	} elsif ( $bunch{$bunchy} and @tracks = @{$bunch{$bunchy}}  ) {
		$debug and print "bunch tracks: @tracks\n";
	} else { say "$bunchy: no matching bunch identifier found" }
	@tracks;
}
sub track_from_name_or_index { /\D/ ? $tn{$_[0]} : $ti{$_[0]}  }
	
	
sub automix {

	# get working track set
	
	my @tracks = grep{
					$tn{$_}->rec_status eq 'MON' or
					$bn{$_} and $tn{$_}->rec_status eq 'REC'
				 } $main->tracks;

	say "tracks: @tracks";

	## we do not allow automix if inserts are present	

	say("Cannot perform automix if inserts are present. Skipping."), return
		if grep{$tn{$_}->prefader_insert || $tn{$_}->postfader_insert} @tracks;

	#use Smart::Comments '###';
	# add -ev to summed signal
	my $ev = add_effect( { chain => $tn{Master}->n, type => 'ev' } );
	### ev id: $ev

	# turn off audio output
	
	$main_out = 0;

	### Status before mixdown:

	command_process('show');

	
	### reduce track volume levels  to 10%

	## accommodate ea and eadb volume controls

	my $vol_operator = $cops{$tn{$tracks[0]}->vol}{type};

	my $reduce_vol_command  = $vol_operator eq 'ea' ? 'vol / 10' : 'vol - 10';
	my $restore_vol_command = $vol_operator eq 'ea' ? 'vol * 10' : 'vol + 10';

	### reduce vol command: $reduce_vol_command

	for (@tracks){ command_process("$_  $reduce_vol_command") }

	command_process('show');

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
		for (@tracks){ command_process("$_  $restore_vol_command") }
		$main_out = 1;
		return;
	}

	### apply multiplier to individual tracks

	for (@tracks){ command_process( "$_ vol*$multiplier" ) }

	# $main_out = 1; # unnecessary: mixdown will turn off and turn on main out
	
	### mixdown
	command_process('mixdown; arm; start');

	### turn on audio output

	# command_process('mixplay'); # rec_cleanup does this automatically

	#no Smart::Comments;
	
}
# vol/pan requirements of mastering and mixdown tracks

{ my %volpan = (
	Eq => {},
	Low => {},
	Mid => {},
	High => {},
	Boost => {vol => 1},
	Mixdown => {},
);

sub need_vol_pan {

	# this routine used by 
	#
	# + add_track() to determine whether a new track _will_ need vol/pan controls
	# + add_track_gui() to determine whether an existing track needs vol/pan  
	
	my ($track_name, $type) = @_;

	# $type: vol | pan
	
	# Case 1: track already exists
	
	return 1 if $tn{$track_name} and $tn{$track_name}->$type;

	# Case 2: track not yet created

	if( $volpan{$track_name} ){
		return($volpan{$track_name}{$type}	? 1 : 0 )
	}
	return 1;
}
}

sub pan_check {
	my $new_position = shift;
	my $current = $copp{ $this_track->pan }->[0];
	$this_track->set(old_pan_level => $current)
		unless defined $this_track->old_pan_level;
	effect_update_copp_set(
		$this_track->pan,	# id
		0, 					# parameter
		$new_position,		# value
	);
}

# track width in words

sub width {
	my $count = shift;
	return 'mono' if $count == 1;
	return 'stereo' if $count == 2;
	return "$count channels";
}


sub cleanup_exit {
 	remove_riff_header_stubs();
	# for each process: 
	# - SIGINT (1st time)
	# - allow time to close down
	# - SIGINT (2nd time)
	# - allow time to close down
	# - SIGKILL
	map{ my $pid = $_; 
		 map{ my $signal = $_; 
			  kill $signal, $pid; 
			  sleeper(0.2) 
			} (2,2,9)
	} @ecasound_pids;
 	#kill 15, ecasound_pid() if $sock;  	
	close_midish() if $midish_enable;
	$term->rl_deprep_terminal() if defined $term;
	exit; 
}
END { cleanup_exit() }

sub do_script {

	my $name = shift;
	my $file;
	# look in project_dir() and project_root()
	# if filename provided does not contain slash
	if( $name =~ m!/!){ $file = $name }
	else {
		$file = join_path(project_dir(),$name);
		if(-e $file){}
		else{ $file = join_path(project_root(),$name) }
	}
	-e $file or say("$file: file not found. Skipping"), return;
	my @lines = split "\n",read_file($file);
	my $old_opt_r = $opts{R};
	$opts{R} = 1; # turn off auto reconfigure
	for my $input (@lines) { process_line($input)};
	$opts{R} = $old_opt_r;
}
sub import_audio {

	my ($track, $path, $frequency) = @_;
	
	$track->import_audio($path, $frequency);

	# check that track is audible
	
	my $bus = $bn{$track->group};

	# set MON status unless track _is_ audible
	
	$track->set(rw => 'MON') 
		unless $bus->rw eq 'MON' and $track->rw eq 'REC';

	# warn if bus is OFF
	
	print("You must set bus to MON (i.e. \"bus_mon\") to hear this track.\n") 
		if $bus->rw eq 'OFF';
}
sub destroy_current_wav {
	my $old_group_status = $main->rw;
	$main->set(rw => 'MON');
	$this_track->current_version or
		say($this_track->name, 
			": No current version (track set to OFF?) Skipping."), return;
	my $wav = $this_track->full_path;
	my $reply = $term->readline("delete WAV file $wav? [n] ");
	#my $reply = chr($term->read_key()); 
	if ( $reply =~ /y/i ){
		# remove version comments, if any
		delete $this_track->{version_comment}{$this_track->current_version};
		print "Unlinking.\n";
		unlink $wav or warn "couldn't unlink $wav: $!\n";
		rememoize();
	}
	$term->remove_history($term->where_history);
	$main->set(rw => $old_group_status);
	1;
}

# TODO

sub list_plugins {}
		
sub show_tracks_limited {

	# Master
	# Mixdown
	# Main bus
	# Current bus

}

		
