sub main { 
#	setup_grammar(); 		# executes directly in body
	process_options(); 		# Option_subs.pm
	initialize_interfaces();# Initialize_subs.pm
	command_process($config->{execute_on_project_load});
	reconfigure_engine();	# Engine_setup_subs.pm
	command_process($config->{opts}->{X});
	$ui->loop;
}

## User Customization -- called by initialize_interfaces()
#  we leave it here because it needs access to all global variables

sub setup_user_customization {
	my $filename = user_customization_file();
	return unless -r $filename;
	say "reading user customization file $filename";
	my %custom;
	unless (%custom = do $filename) {
		say "couldn't parse $filename: $@\n" if $@;
		return;
	}
	$debug and say 'customization :', yaml_out(\%custom);
	my $prompt;
	$prompt = gen_coderef('prompt', $custom{prompt}) if $custom{prompt};
	*prompt = $prompt if $prompt;
	my @commands = keys %{ $custom{commands} };
	for my $cmd(@commands){
		my $coderef = gen_coderef($cmd,$custom{commands}{$cmd}) or next;
		$text->{user_command}->{$cmd} = $coderef;
	}
	$text->{user_alias}   = $custom{aliases};
}
sub user_customization_file { join_path(project_root(),$file->{user_customization}) }

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
	$text->{user_command}->{$cmd}->(@args);
}	

sub do_script {

	my $name = shift;
	my $filename;
	# look in project_dir() and project_root()
	# if filename provided does not contain slash
	if( $name =~ m!/!){ $filename = $name }
	else {
		$filename = join_path(project_dir(),$name);
		if(-e $filename){}
		else{ $filename = join_path(project_root(),$name) }
	}
	-e $filename or say("$filename: file not found. Skipping"), return;
	my @lines = split "\n",read_file($filename);
	my $old_opt_r = $config->{opts}->{R};
	$config->{opts}->{R} = 1; # turn off auto reconfigure
	for my $input (@lines) { process_line($input)};
	$config->{opts}->{R} = $old_opt_r;
}

sub dump_all {
	my $tmp = ".dump_all";
	my $fname = join_path( project_root(), $tmp);
	save_system_state($fname);
	file_pager("$fname.yml");
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
{ my @namespace_abbreviations = qw(
	Assign 
	Track
	Bus
	Mark
	IO
	Graph
	Wav
	Insert
	Fade                                                      
	Edit
	Text
	ChainSetup
);

my $namespace_root = 'Audio::Nama';

sub eval_perl {
	my $code = shift;
	map{ $code =~ s/::$_/$namespace_root\::$_/ } @namespace_abbreviations; # SKIP_PREPROC
	my (@result) = eval $code;
	print( "Perl command failed: $@\n") if $@;
	pager(join "\n", @result) unless $@;
	print "\n";
}	
}
sub import_audio {

	my ($track, $path, $frequency) = @_;
	
	$track->import_audio($path, $frequency);

	# check that track is audible

	$track->set(rw => 'MON');

}
sub destroy_current_wav {
	my $old_group_status = $bn{Main}->rw;
	$bn{Main}->set(rw => 'MON');
	$this_track->current_version or
		say($this_track->name, 
			": No current version (track set to OFF?) Skipping."), return;
	my $wav = $this_track->full_path;
	my $reply = $text->{term}->readline("delete WAV file $wav? [n] ");
	#my $reply = chr($text->{term}->read_key()); 
	if ( $reply =~ /y/i ){
		# remove version comments, if any
		delete $this_track->{version_comment}{$this_track->current_version};
		print "Unlinking.\n";
		unlink $wav or warn "couldn't unlink $wav: $!\n";
		rememoize();
	}
	$text->{term}->remove_history($text->{term}->where_history);
	$bn{Main}->set(rw => $old_group_status);
	1;
}


sub is_bunch {
	my $name = shift;
	$bn{$name} or $project->{bunch}->{$name}
}

sub pan_check {
	my $new_position = shift;
	my $current = $fx->{params}->{ $this_track->pan }->[0];
	$this_track->set(old_pan_level => $current)
		unless defined $this_track->old_pan_level;
	effect_update_copp_set(
		$this_track->pan,	# id
		0, 					# parameter
		$new_position,		# value
	);
}

# called from grammar_body.pl, Mute_Solo_Fade, Effect_chain_subs
{
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
	} elsif ( $project->{bunch}->{$bunchy} and @tracks = @{$project->{bunch}->{$bunchy}}  ) {
		$debug and print "bunch tracks: @tracks\n";
	} else { say "$bunchy: no matching bunch identifier found" }
	@tracks;
}
}
sub track_from_name_or_index { /\D/ ? $tn{$_[0]} : $ti{$_[0]}  }

# called from almost everywhere

sub command_process {
	my $input = shift;
	my $input_was = $input;

	# parse repeatedly until all input is consumed
	
	while ($input =~ /\S/) { 
		$debug and say "input: $input";
		$text->{parser}->meta(\$input) or print("bad command: $input_was\n"), last;
	}
	$ui->refresh; # in case we have a graphic environment
	set_current_bus();
}
	
## called from ChainSetup.pm and Engine_setup_subs.pm

sub setup_file { join_path( project_dir(), $file->{chain_setup}) };

## called from 
# Track_subs
# Graphical_subs
# Refresh_subs
# Core_subs
# Realtime_subs

# vol/pan requirements of mastering and mixdown tracks

# called from Track_subs, Graphical_subs
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

# track width in words
# called from grammar_body.pl,Track.pm

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
	} @{$engine->{pids}};
 	#kill 15, ecasound_pid() if $engine->{socket};  	
	close_midish() if $config->{use_midish};
	$text->{term}->rl_deprep_terminal() if defined $text->{term};
	exit; 
}
END { cleanup_exit() }

# TODO

sub list_plugins {}
		
sub show_tracks_limited {

	# Master
	# Mixdown
	# Main bus
	# Current bus

}
sub process_control_inputs { }

sub hardware_latency {
	$config->{devices}->{$config->{alsa_capture_device}}{hardware_latency} || 0
}
	

### end Core_subs
