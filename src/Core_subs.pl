sub main { 
#	setup_grammar(); # executes directly in body
	process_options();
	initialize_interfaces(); 
	command_process($execute_on_project_load);
	reconfigure_engine();
	command_process($opts{X});
	$ui->loop;
}

## User Customization
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

sub do_user_command {
	#say "args: @_";
	my($cmd, @args) = @_;
	$user_command{$cmd}->(@args);
}	

sub list_plugins {}
		

sub create_system_buses {
	$debug2 and say "&create_system_buses";

	my $buses = q(
			Master		# master fader track
			Mixdown		# mixdown track
			Mastering	# mastering network
			Insert		# auxiliary tracks for inserts
			Cooked		# for track caching
			Temp		# temp tracks while generating setup
			Main		# default mixer bus, new tracks assigned to Main
	);
	($buses) = strip_comments($buses); # need initial parentheses
	@system_buses = split " ", $buses;
	map{ $is_system_bus{$_}++ } @system_buses;
	delete $is_system_bus{Main}; # because we want to display it
	map{ ::Bus->new(name => $_ ) } @system_buses;
	
	# a bus should identify it's mix track
	$bn{Main}->set( send_type => 'track', send_id => 'Master');

	$main = $bn{Main};
	$null = $bn{null};
}

## track and wav file handling

# create read-only track pointing at WAV files of specified
# track name in a different project

sub add_track_alias_project {
	my ($name, $track, $project) = @_;
	my $dir =  join_path(project_root(), $project, '.wav'); 
	if ( -d $dir ){
		if ( glob "$dir/$track*.wav"){
			print "Found target WAV files.\n";
			my @params = (target => $track, project => $project);
			add_track( $name, @params );
		} else { print "No WAV files found.  Skipping.\n"; return; }
	} else { 
		print("$project: project does not exist.  Skipping.\n");
		return;
	}
}

sub discard_object {
	shift @_ if (ref $_[0]) =~ /Nama/;
	@_;
}

# usual track

sub add_track {

	@_ = discard_object(@_);
	$debug2 and print "&add_track\n";
	#return if transport_running();
	my ($name, @params) = @_;
	my %vals = (name => $name, @params);
	my $class = $vals{class} // '::Track';
	
	$debug and print "name: $name, ch_r: $ch_r, ch_m: $ch_m\n";
	
	say ("$name: track name already in use. Skipping."), return 
		if $::Track::by_name{$name};
	say ("$name: reserved track name. Skipping"), return
	 	if grep $name eq $_, @mastering_track_names; 

	my $track = $class->new(%vals);
	return if ! $track; 
	$this_track = $track;
	$debug and print "ref new track: ", ref $track; 
	$track->source($ch_r) if $ch_r;
#		$track->send($ch_m) if $ch_m;

	my $group = $bn{$track->group}; 
	command_process('for mon; mon') if $preview and $group->rw eq 'MON';
	$group->set(rw => 'REC') unless $track->target; # not if is alias

	# normal tracks default to 'REC'
	# track aliases default to 'MON'
	$track->set(rw => $track->target
					?  'MON'
					:  'REC') ;
	$track_name = $ch_m = $ch_r = undef;

	set_current_bus();
	$ui->track_gui($track->n);
	$debug and print "Added new track!\n", $track->dump;
	$track;
}

# create read-only track pointing at WAV files of specified
# name in current project

sub add_track_alias {
	my ($name, $track) = @_;
	my $target; 
	if 		( $tn{$track} ){ $target = $track }
	elsif	( $ti{$track} ){ $target = $ti{$track}->name }
	add_track(  $name, target => $target );
}
sub add_volume_control {
	my $n = shift;
	return unless need_vol_pan($ti{$n}->name, "vol");
	
	my $vol_id = cop_add({
				chain => $n, 
				type => $volume_control_operator,
				cop_id => $ti{$n}->vol, # often undefined
				});
	
	$ti{$n}->set(vol => $vol_id);  # save the id for next time
	$vol_id;
}
sub add_pan_control {
	my $n = shift;
	return unless need_vol_pan($ti{$n}->name, "pan");

	my $pan_id = cop_add({
				chain => $n, 
				type => 'epp',
				cop_id => $ti{$n}->pan, # often undefined
				});
	
	$ti{$n}->set(pan => $pan_id);  # save the id for next time
	$pan_id;
}

# not used at present. we are probably going to offset the playat value if
# necessary

sub add_latency_compensation {
	print('LADSPA L/C/R Delay effect not found.
Unable to provide latency compensation.
'), return unless $effect_j{lcrDelay};
	my $n = shift;
	my $id = cop_add({
				chain => $n, 
				type => 'el:lcrDelay',
				cop_id => $ti{$n}->latency, # may be undef
				values => [ 0,0,0,50,0,0,0,0,0,50,1 ],
				# We will be adjusting the 
				# the third parameter, center delay (index  2)
				});
	
	$ti{$n}->set(latency => $id);  # save the id for next time
	$id;
}

## chain setup generation

sub setup_file { join_path( project_dir(), $chain_setup_file) };

sub show_tracks_limited {

	# Master
	# Mixdown
	# Main bus
	# Current bus

}

		
sub exit_preview_mode { # exit preview and doodle modes

		$debug2 and print "&exit_preview_mode\n";
		return unless $preview;
		stop_transport() if engine_running();
		$debug and print "Exiting preview/doodle mode\n";
		$preview = 0;
		$main->set(rw => $old_group_rw) if $old_group_rw;

}

sub find_duplicate_inputs { # in Main bus only

	%duplicate_inputs = ();
	%already_used = ();
	$debug2 and print "&find_duplicate_inputs\n";
	map{	my $source = $_->source;
			$duplicate_inputs{$_->name}++ if $already_used{$source} ;
		 	$already_used{$source} //= $_->name;
	} 
	grep { $_->rw eq 'REC' }
	map{ $tn{$_} }
	$main->tracks(); # track names;
}


sub adjust_latency {

	$debug2 and print "&adjust_latency\n";
	map { $copp{$_->latency}[0] = 0  if $_->latency() } 
		::Track::all();
	set_preview_mode();
	exit_preview_mode();
	my $cop_status = eval_iam('cop-status');
	$debug and print $cop_status;
	my $chain_re  = qr/Chain "(\d+)":\s+(.*?)(?=Chain|$)/s;
	my $latency_re = qr/\[\d+\]\s+latency\s+([\d\.]+)/;
	my %chains = $cop_status =~ /$chain_re/sg;
	$debug and print yaml_out(\%chains);
	my %latency;
	map { my @latencies = $chains{$_} =~ /$latency_re/g;
			$debug and print "chain $_: latencies @latencies\n";
			my $chain = $_;
		  map{ $latency{$chain} += $_ } @latencies;
		 } grep { $_ > 2 } sort keys %chains;
	$debug and print yaml_out(\%latency);
	my $max;
	map { $max = $_ if $_ > $max  } values %latency;
	$debug and print "max: $max\n";
	map { my $adjustment = ($max - $latency{$_}) /
			$cfg{abbreviations}{frequency} * 1000;
			$debug and print "chain: $_, adjustment: $adjustment\n";
			effect_update_copp_set($ti{$_}->latency, 2, $adjustment);
			} keys %latency;
}

sub jack_plumbing_conf {
	join_path( $ENV{HOME} , '.jack.plumbing' )
}

{ 
  my $fh;
  my $plumbing_tag = q(BEGIN NAMA CONNECTIONS LIST);
  my $plumbing_header = qq(;### $plumbing_tag
;## The following lines are automatically generated.
;## DO NOT place any connection data below this line!!
;
); 
sub initialize_jack_plumbing_conf {  # remove nama lines

		return unless -f -r jack_plumbing_conf();

		# read in file
		my $user_plumbing = io(jack_plumbing_conf())->all;

		# keep user data, deleting below tag
		$user_plumbing =~ s/;[# ]*$plumbing_tag.*//gs;

		# write out file
		$user_plumbing > io(jack_plumbing_conf());
}

my $jack_plumbing_code = sub 
	{
		my ($port1, $port2) = @_;
		my $debug++;
		my $config_line = qq{(connect $port1 $port2)};
		say $fh $config_line; # $fh in lexical scope
		$debug and say $config_line;
	};
my $jack_connect_code = sub
	{
		my ($port1, $port2) = @_;
		my $debug++;
		my $cmd = qq(jack_connect $port1 $port2);
		$debug and say $cmd;
		system $cmd;
	};
sub connect_jack_ports_list {

	my @source_tracks = 
		grep{ 	$_->source_type eq 'jack_ports_list' and
	  	  		$_->rec_status  eq 'REC' 
			} engine_tracks();

	my @send_tracks = 
		grep{ $_->send_type eq 'jack_ports_list' } engine_tracks();

	# we need JACK
	return if ! $jack_running;

	# We need tracks to configure
	return if ! @source_tracks and ! @send_tracks;

	sleeper(0.3); # extra time for ecasound engine to register JACK ports

	if( $use_jack_plumbing )
	{

		# write config file
		initialize_jack_plumbing_conf();
		open $fh, ">>", jack_plumbing_conf();
		print $fh $plumbing_header;
		make_connections($jack_plumbing_code, \@source_tracks, 'in' );
		make_connections($jack_plumbing_code, \@send_tracks,   'out');
		close $fh; 

		# run jack.plumbing
		start_jack_plumbing();
		sleeper(3); # time for jack.plumbing to launch and poll
		kill_jack_plumbing();
		initialize_jack_plumbing_conf();
	}
	else 
	{
		make_connections($jack_connect_code, \@source_tracks, 'in' );
		make_connections($jack_connect_code, \@send_tracks,   'out');
	}
}
}
sub quote { $_[0] =~ /^"/ ? $_[0] : qq("$_[0]")}

sub make_connections {
	my ($code, $tracks, $direction) = @_;
	my $ports_list = $direction eq 'in' ? 'source_id' : 'send_id';
	map{  
		my $track = $_; 
 		my $name = $track->name;
 		my $ecasound_port = "ecasound:$name\_$direction\_";
		my $file = join_path(project_root(), $track->$ports_list);
		say($track->name, 
			": JACK ports file $file not found. No sources connected."), 
			return if ! -e -r $file;
		my $line_number = 0;
		my @lines = io($file)->slurp;
		for my $external_port (@lines){   
			# $external_port is the source port name
			chomp $external_port;
			$debug and say "port file $file, line $line_number, port $external_port";
			# setup shell command
			
			if(! $jack{$external_port}){
				say $track->name, qq(: port "$external_port" not found. Skipping.);
				next
			}
		
			# ecasound port index
			
			my $index = $track->width == 1
				?  1 
				: $line_number % $track->width + 1;

		my @ports = map{quote($_)} $external_port, $ecasound_port.$index;

			  $code->(
						$direction eq 'in'
							? @ports
							: reverse @ports
					);
			$line_number++;
		};
 	 } @$tracks
}
	

sub transport_status {
	
	map{ 
		say("Warning: $_: input ",$tn{$_}->source,
		" is already used by track ",$already_used{$tn{$_}->source},".")
		if $duplicate_inputs{$_};
	} grep { $tn{$_}->rec_status eq 'REC' } $main->tracks;


	# assume transport is stopped
	# print looping status, setup length, current position
	my $start  = ::Mark::loop_start();
	my $end    = ::Mark::loop_end();
	#print "start: $start, end: $end, loop_enable: $loop_enable\n";
	if (%cooked_record_pending){
		say join(" ", keys %cooked_record_pending), ": ready for caching";
	}
	if ($loop_enable and $start and $end){
		#if (! $end){  $end = $start; $start = 0}
		say "looping from ", heuristic_time($start),
				 	"to ",   heuristic_time($end);
	}
	say "\nNow at: ", current_position();
	say "Engine is ". ( engine_running() ? "running." : "ready.");
	say "\nPress SPACE to start or stop engine.\n"
		if $press_space_to_start_transport;
}

sub heuristic_time {
	my $sec = shift;
	d1($sec) .  ( $sec > 120 ? " (" . colonize( $sec ) . ") "  : " " )
}

sub schedule_autosave { 
	# one-time timer 
	my $seconds = (shift || $autosave_interval) * 60;
	$event_id{autosave} = undef; # cancel any existing timer
	return unless $seconds;
	$event_id{autosave} = AE::timer($seconds,0, \&autosave);
}
sub debugging_options {
	grep{$_} $debug, @opts{qw(R D J A E T)};
}
sub mute {
	return if $opts{F};
	return if $tn{Master}->rw eq 'OFF' or really_recording();
	$tn{Master}->mute;
}
sub unmute {
	return if $opts{F};
	return if $tn{Master}->rw eq 'OFF' or really_recording();
	$tn{Master}->unmute;
}

# for GUI transport controls

sub toggle_unit {
	if ($unit == 1){
		$unit = 60;
		
	} else{ $unit = 1; }
}
sub show_unit { $time_step->configure(
	-text => ($unit == 1 ? 'Sec' : 'Min') 
)}

# Mark routines

sub drop_mark {
	$debug2 and print "drop_mark()\n";
	my $name = shift;
	my $here = eval_iam("getpos");

	if( my $mark = $::Mark::by_name{$name}){
		say "$name: a mark with this name exists already at: ", 
			colonize($mark->time);
		return
	}
	if( my ($mark) = grep { $_->time == $here} ::Mark::all()){
		say q(This position is already marked by "),$mark->name,q(");
		 return 
	}

	my $mark = ::Mark->new( time => $here, 
							name => $name);

	$ui->marker($mark); # for GUI
}
sub mark { # GUI_CODE
	$debug2 and print "mark()\n";
	my $mark = shift;
	my $pos = $mark->time;
	if ($markers_armed){ 
			$ui->destroy_marker($pos);
			$mark->remove;
		    arm_mark_toggle(); # disarm
	}
	else{ 

		set_position($pos);
	}
}

sub next_mark {
	my $jumps = shift;
	$jumps and $jumps--;
	my $here = eval_iam("cs-get-position");
	my @marks = ::Mark::all();
	for my $i ( 0..$#marks ){
		if ($marks[$i]->time - $here > 0.001 ){
			$debug and print "here: $here, future time: ",
			$marks[$i]->time, $/;
			eval_iam("setpos " .  $marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
sub previous_mark {
	my $jumps = shift;
	$jumps and $jumps--;
	my $here = eval_iam("getpos");
	my @marks = ::Mark::all();
	for my $i ( reverse 0..$#marks ){
		if ($marks[$i]->time < $here ){
			eval_iam("setpos " .  $marks[$i+$jumps]->time);
			$this_mark = $marks[$i];
			return;
		}
	}
}
	

## jump recording head position

sub to_start { 
	return if really_recording();
	set_position( 0 );
}
sub to_end { 
	# ten seconds shy of end
	return if really_recording();
	my $end = eval_iam('cs-get-length') - 10 ;  
	set_position( $end);
} 
sub jump {
	return if really_recording();
	my $delta = shift;
	$debug2 and print "&jump\n";
	my $here = eval_iam('getpos');
	$debug and print "delta: $delta\nhere: $here\nunit: $unit\n\n";
	my $new_pos = $here + $delta * $unit;
	$new_pos = $new_pos < $length ? $new_pos : $length - 10;
	set_position( $new_pos );
	sleeper( 0.6) if engine_running();
}
	
sub fade {
	my ($id, $param, $from, $to, $seconds) = @_;

	# no fade without Timer::HiRes
	# no fade unless engine is running
	if ( ! engine_running() or ! $hires ){
		effect_update_copp_set ( $id, $param, $to );
		return;
	}

	my $steps = $seconds * $fade_resolution;
	my $wink  = 1/$fade_resolution;
	my $size = ($to - $from)/$steps;
	$debug and print "id: $id, param: $param, from: $from, to: $to, seconds: $seconds\n";
	for (1..$steps - 1){
		modify_effect( $id, $param, '+', $size);
		sleeper( $wink );
	}		
	effect_update_copp_set( 
		$id, 
		$param, 
		$to);
	
}

sub fadein {
	my ($id, $to) = @_;
	my $from  = $fade_out_level{$cops{$id}->{type}};
	fade( $id, 0, $from, $to, $fade_time);
}
sub fadeout {
	my $id    = shift;
	my $from  =	$copp{$id}[0];
	my $to	  = $fade_out_level{$cops{$id}->{type}};
	fade( $id, 0, $from, $to, $fade_time );
}

sub d1 {
	my $n = shift;
	sprintf("%.1f", $n)
}
sub d2 {
	my $n = shift;
	sprintf("%.2f", $n)
}
sub dn {
	my ($n, $places) = @_;
	sprintf("%." . $places . "f", $n);
}
sub round {
	my $n = shift;
	return 0 if $n == 0;
	$n = int $n if $n > 10;
	$n = d2($n) if $n < 10;
	$n;
}
sub colonize { # convert seconds to hours:minutes:seconds 
	my $sec = shift || 0;
	my $hours = int ($sec / 3600);
	$sec = $sec % 3600;
	my $min = int ($sec / 60);
	$sec = $sec % 60;
	$sec = "0$sec" if $sec < 10;
	$min = "0$min" if $min < 10 and $hours;
	($hours ? "$hours:" : "") . qq($min:$sec);
}



sub time_tag {
	my @time = localtime time;
	$time[4]++;
	$time[5]+=1900;
	@time = @time[5,4,3,2,1,0];
	sprintf "%4d.%02d.%02d-%02d:%02d:%02d", @time
}

sub autosave {
	if (engine_running()){ 
		schedule_autosave(1); # try again in 60s
		return;
	}
 	my $file = 'State-autosave-' . time_tag();
 	save_system_state($file);
	my @saved = autosave_files();
	my ($next_last, $last) = @saved[-2,-1];
	schedule_autosave(); # standard interval
	return unless defined $next_last and defined $last;
	if(files_are_identical($next_last, $last)){
		unlink $last;
		undef; 
	} else { 
		$last 
	}
}
sub autosave_files {
	sort File::Find::Rule  ->file()
						->name('State-autosave-*')
							->maxdepth(1)
						 	->in( project_dir());
}
sub files_are_identical {
	my ($filea,$fileb) = @_;
	my $a = io($filea)->slurp;
	my $b = io($fileb)->slurp;
	$a eq $b
}

sub process_control_inputs { }


sub set_position {

    return if really_recording(); # don't allow seek while recording

    my $seconds = shift;
    my $coderef = sub{ eval_iam("setpos $seconds") };

    if( $jack_running and eval_iam('engine-status') eq 'running')
			{ engine_stop_seek_start( $coderef ) }
	else 	{ $coderef->() }
	update_clock_display();
}

sub engine_stop_seek_start {
	my $coderef = shift;
	eval_iam('stop');
	$coderef->();
	sleeper($seek_delay);
	eval_iam('start');
}

sub forward {
	my $delta = shift;
	my $here = eval_iam('getpos');
	my $new = $here + $delta;
	set_position( $new );
}

sub rewind {
	my $delta = shift;
	forward( -$delta );
}
sub solo {
	my @args = @_;

	# get list of already muted tracks if I haven't done so already
	
	if ( ! @already_muted ){
		@already_muted = grep{ $_->old_vol_level} 
                         map{ $tn{$_} } 
						 ::Track::user();
	}

	$debug and say join " ", "already muted:", map{$_->name} @already_muted;

	# convert bunches to tracks
	my @names = map{ bunch_tracks($_) } @args;

	# use hashes to store our list
	
	my %to_mute;
	my %not_mute;
	
	# get dependent tracks
	
	my @d = map{ $tn{$_}->bus_tree() } @names;

	# store solo tracks and dependent tracks that we won't mute

	map{ $not_mute{$_}++ } @names, @d;

	# find all siblings tracks not in depends list

	# - get buses list corresponding to our non-muting tracks
	
	my %buses;
	$buses{Main}++; 				# we always want Main
	
	map{ $buses{$_}++ } 			# add to buses list
	map { $tn{$_}->group } 			# corresponding bus (group) names
	keys %not_mute;					# tracks we want

	# - get sibling tracks we want to mute

	map{ $to_mute{$_}++ }			# add to mute list
	grep{ ! $not_mute{$_} }			# those we *don't* want
	map{ $bn{$_}->tracks }			# tracks list
	keys %buses;					# buses list

	# mute all tracks on our mute list (do we skip already muted tracks?)
	
	map{ $tn{$_}->mute('nofade') } keys %to_mute;

	# unmute all tracks on our wanted list
	
	map{ $tn{$_}->unmute('nofade') } keys %not_mute;
	
	$soloing = 1;
}

sub nosolo {
	# unmute all except in @already_muted list

	# unmute all tracks
	map { $tn{$_}->unmute('nofade') } ::Track::user();

	# re-mute previously muted tracks
	if (@already_muted){
		map { $_->mute('nofade') } @already_muted;
	}

	# remove listing of muted tracks
	@already_muted = ();
	
	$soloing = 0;
}
sub all {

	# unmute all tracks
	map { $tn{$_}->unmute('nofade') } ::Track::user();

	# remove listing of muted tracks
	@already_muted = ();
	
	$soloing = 0;
}

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
sub ecasound_select_chain {
	my $n = shift;
	my $cmd = "c-select $n";

	if( 

		# specified chain exists in the chain setup
		$is_ecasound_chain{$n}

		# engine is configured
		and eval_iam( 'cs-connected' ) =~ /$chain_setup_file/

	){ 	eval_iam($cmd); 
		return 1 

	} else { 
		$debug and carp 
			"c-select $n: attempted to select non-existing Ecasound chain\n"; 
		return 0
	}
}
sub set_current_bus {
	my $track = shift || ($this_track ||= $tn{Master});
	#say "track: $track";
	#say "this_track: $this_track";
	#say "master: $tn{Master}";
	if( $track->name =~ /Master|Mixdown/){ $this_bus = 'Main' }
	elsif( $bn{$track->name} ){$this_bus = $track->name }
	else { $this_bus = $track->group }
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
	
# JACK related functions

sub poll_jack { $event_id{poll_jack} = AE::timer(0,5,\&jack_update) }

sub jack_update {
	# cache current JACK status
	return if engine_running();
	if( $jack_running =  process_is_running('jackd') ){
		my $jack_lsp = qx(jack_lsp -Ap 2> /dev/null); 
		%jack = %{jack_ports($jack_lsp)}
	} else { %jack = () }
}

sub jack_client {

	# returns array of ports if client and direction exist
	
	my ($name, $direction)  = @_;
	$jack{$name}{$direction} // []
}

sub jack_ports {
	my $j = shift || $jack_lsp; 
	#say "jack_lsp: $j";

	# convert to single lines

	$j =~ s/\n\s+/ /sg;

	# system:capture_1 alsa_pcm:capture_1 properties: output,physical,terminal,
	#fluidsynth:left properties: output,
	#fluidsynth:right properties: output,
	my %jack = ();

	map{ 
		my ($direction) = /properties: (input|output)/;
		s/properties:.+//;
		my @port_aliases = /
			\s* 			# zero or more spaces
			([^:]+:[^:]+?) # non-colon string, colon, non-greedy non-colon string
			(?=[-+.\w]+:|\s+$) # zero-width port name or spaces to end-of-string
		/gx;
		map { 
				s/ $//; # remove trailing space
				push @{ $jack{ $_ }{ $direction } }, $_;
				my ($client, $port) = /(.+?):(.+)/;
				push @{ $jack{ $client }{ $direction } }, $_; 

		 } @port_aliases;

	} 
	grep{ ! /^jack:/i } # skip spurious jackd diagnostic messages
	split "\n",$j;
	#print yaml_out \%jack;
	\%jack
}
	
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


	# status_snapshot() 
	#
	# hashref output for detecting if we need to reconfigure engine
	# compared as YAML strings
	#
{
	my @sense_reconfigure = qw(
		name
		width
		group 
		playat
		region_start	
		region_end
		looping
		source_id
		source_type
		send_id
		send_type
		rec_defeat
		rec_status
		current_version
 );
sub status_snapshot {

	
	my %snapshot = ( project 		=> 	$project_name,
					 mastering_mode => $mastering_mode,
					 preview        => $preview,
					 main_out 		=> $main_out,
					 jack_running	=> $jack_running,
					 tracks			=> [], );
	map { push @{$snapshot{tracks}}, $_->snapshot(\@sense_reconfigure) }
	::Track::all();
	\%snapshot;
}
}
sub set_region {
	my ($beg, $end) = @_;
	$this_track->set(region_start => $beg);
	$this_track->set(region_end => $end);
	::Text::show_region();
}
sub new_region {
	my ($beg, $end, $name) = @_;
	$name ||= new_region_name();
	add_track_alias($name, $this_track->name);	
	set_region($beg,$end);
}
sub new_region_name {
	my $name = $this_track->name . '_region_';
	my $i;
	map{ my ($j) = /_(\d+)$/; $i = $j if $j > $i; }
		grep{/$name/} keys %::Track::by_name;
	$name . ++$i
}
sub remove_region {
	if (! $this_track->region_start){
		say $this_track->name, ": no region is defined. Skipping.";
		return;
	} elsif ($this_track->target ){
		say $this_track->name, ": looks like a region...  removing.";
		$this_track->remove;
	} else { undefine_region() }
}
	
sub undefine_region {
	$this_track->set(region_start => undef );
	$this_track->set(region_end => undef );
	print $this_track->name, ": Region definition removed. Full track will play.\n";
}

sub add_sub_bus {
	my ($name, @args) = @_; 
	
	::SubBus->new( 
		name => $name, 
		send_type => 'track',
		send_id	 => $name,
		) unless $::Bus::by_name{$name};

	# create mix track
	@args = ( 
		width 		=> 2,     # default to stereo 
		rec_defeat	=> 1,     # set to rec_defeat (don't record signal)
		rw 			=> 'REC', # set to REC (accept other track signals)
		@args
	);

	$tn{$name} and say qq($name: setting as mix track for bus "$name");

	my $track = $tn{$name} // add_track($name);

	# convert host track to mix track
	
	$track->set(was_class => ref $track); # save the current track (sub)class
	$track->set_track_class('::MixTrack'); 
	$track->set( @args );
	
}
	
sub add_send_bus {

	my ($name, $dest_id, $bus_type) = @_;
	my $dest_type = dest_type( $dest_id );

	# dest_type: soundcard | jack_client | loop | jack_port | jack_multi
	
	print "name: $name: dest_type: $dest_type dest_id: $dest_id\n";
	if ($bn{$name} and (ref $bn{$name}) !~ /SendBus/){
		say($name,": bus name already in use. Aborting."), return;
	}
	if ($bn{$name}){
		say qq(monitor bus "$name" already exists. Updating with new tracks.");
	} else {
	my @args = (
		name => $name, 
		send_type => $dest_type,
		send_id	 => $dest_id,
	);

	my $class = $bus_type eq 'cooked' ? '::SendBusCooked' : '::SendBusRaw';
	my $bus = $class->new( @args );

	$bus or carp("can't create bus!\n"), return;

	}
	map{ ::SlaveTrack->new(	name => "$name\_$_", # BusName_TrackName
							rw => 'MON',
							target => $_,
							group  => $name,
						)
   } $main->tracks;
		
}

sub dest_type {
	my $dest = shift;
	my $type;
	given( $dest ){
		when( undef )       {} # do nothing

		# non JACK related

		when('bus')			   { $type = 'bus'             }
		when('null')           { $type = 'null'            }
		when(/^loop,/)         { $type = 'loop'            }

		when(! /\D/)           { $type = 'soundcard'       } # digits only

		# JACK related

		when(/^man/)           { $type = 'jack_manual'     }
		when('jack')           { $type = 'jack_manual'     }
		when(/(^\w+\.)?ports/) { $type = 'jack_ports_list' }
		default                { $type = 'jack_client'     } 

	}
	$type
}
	
sub update_send_bus {
	my $name = shift;
		add_send_bus( $name, 
						 $bn{$name}->send_id),
						 "dummy",
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
	
	$this_track->import_audio($path, $frequency);

	# check that track is audible
	
	my $bus = $bn{$this_track->group};

	# set MON status unless track _is_ audible
	
	$this_track->set(rw => 'MON') 
		unless $bus->rw eq 'MON' and $this_track->rw eq 'REC';

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

# the following routines are used only by the GUI
sub some_user_tracks {
	my $which = shift;
	my @user_tracks = ::Track::all();
	splice @user_tracks, 0, 2; # drop Master and Mixdown tracks
	return unless @user_tracks;
	my @selected_user_tracks = grep { $_->rec_status eq $which } @user_tracks;
	return unless @selected_user_tracks;
	map{ $_->n } @selected_user_tracks;
}
sub user_rec_tracks { some_user_tracks('REC') }
sub user_mon_tracks { some_user_tracks('MON') }


sub kill_jack_plumbing {
	qx(killall jack.plumbing >/dev/null 2>&1)
	unless $opts{A} or $opts{J};
}
sub start_jack_plumbing {
	
	if ( 	$use_jack_plumbing				# not disabled in namarc
			and ! ($opts{J} or $opts{A})	# we are not testing   

	){ system('jack.plumbing >/dev/null 2>&1 &') }
}
{

my($error,$answer)=('','');
my ($pid, $sel);

sub start_midish {
	my $executable = qx(which midish);
	chomp $executable;
	$executable or say("Midish not found!"), return;
	$pid = open3(\*MIDISH_WRITE, \*MIDISH_READ,\*MIDISH_ERROR,"$executable -v")
		or warn "Midish failed to start!";

	$sel = new IO::Select();

	$sel->add(\*MIDISH_READ);
	$sel->add(\*MIDISH_ERROR);
	midish_command( qq(print "Welcome to Nama/Midish!"\n) );
}

sub midish_command {
	my $query = shift;
	print "\n";
	#$midish_enable or say( qq($query: cannot execute Midish command 
#unless you set "midish_enable: 1" in .namarc)), return;
	#$query eq 'exit' and say("Will exit Midish on closing Nama."), return;

	#send query to midish
	print MIDISH_WRITE "$query\n";

	foreach my $h ($sel->can_read)
	{
		my $buf = '';
		if ($h eq \*MIDISH_ERROR)
		{
			sysread(MIDISH_ERROR,$buf,4096);
			if($buf){print "MIDISH ERR-> $buf\n"}
		}
		else
		{
			sysread(MIDISH_READ,$buf,4096);
			if($buf){map{say "MIDISH-> $_"} grep{ !/\+ready/ } split "\n", $buf}
		}
	}
	print "\n";
}

sub close_midish {
	midish_command('exit');
	sleeper(0.1);
	kill 15,$pid;
	sleeper(0.1);
	kill 9,$pid;
	sleeper(0.1);
	waitpid($pid, 1);
# It is important to waitpid on your child process,  
# otherwise zombies could be created. 
}	
}

