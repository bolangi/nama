# --------------------- Command Grammar ----------------------

package ::;
use ::Effects qw(:all);
use Modern::Perl;

sub setup_grammar {

	### COMMAND LINE PARSER 

	logsub("&setup_grammar");

	$text->{commands_yml} = get_data_section("commands_yml");
	$text->{commands_yml} = quote_yaml_scalars($text->{commands_yml});
	$text->{commands} = yaml_in( $text->{commands_yml}) ;
	map
	{ 
		my $full_name = $_; 
		my $shortcuts = $text->{commands}->{$full_name}->{short};
		my @shortcuts = ();
		@shortcuts = split " ", $shortcuts if $shortcuts;
		map{ $text->{command_shortcuts}->{$_} = $full_name } @shortcuts;

	} keys %{$text->{commands}};

	$::AUTOSTUB = 1;
	$::RD_TRACE = 1;
	$::RD_ERRORS = 1; # Make sure the parser dies when it encounters an error
	$::RD_WARN   = 1; # Enable warnings. This will warn on unused rules &c.
	$::RD_HINT   = 1; # Give out hints to help fix problems.

	$text->{grammar} = get_data_section('grammar');

	$text->{parser} = Parse::RecDescent->new($text->{grammar}) or croak "Bad grammar!\n";

	# Midish command keywords
	
	$midi->{keywords} = 
	{
			map{ $_, 1} split " ", get_data_section("midish_commands")
	};

	# print remove_spaces("bulwinkle is a...");

}
{
my %exclude_from_undo_buffer = map{ $_ => 1} 
		qw(tag commit branch br new_branch nbr load save get restore);
sub process_line {
	logsub("&process_line");
	no warnings 'uninitialized';
	my ($user_input) = @_;
	logpkg('debug',"user input: $user_input");
	if (defined $user_input and $user_input !~ /^\s*$/) {
		$text->{term}->addhistory($user_input) 
			unless $user_input eq $text->{previous_cmd};
		$text->{previous_cmd} = $user_input;
		if ($mode->{midish_terminal}){
				$user_input =~ /^\s*(midish_mode_off|mmx)/ 
					?  process_command($user_input)
					:  midish_command($user_input);	
		}
		else {
			my $success = process_command( $user_input );
				
			push @{$project->{undo_buffer}}, 

			{
				context => context(),
				command => $user_input,
			#	commit 	=> $commit 
			}

				unless ! $success 
					   or $user_input =~ /^\s*([a-z_]+)/
						and $exclude_from_undo_buffer{$1};
			autosave() if $config->{use_git} and $config->{autosave} eq 'undo';
			reconfigure_engine();
				#or eval_iam('cs-connected') 
				#and remove_latency_ops() 
				#and calculate_and_adjust_latency();
		}
		revise_prompt( $mode->{midish_terminal} ? "Midish > " : prompt());
	}
}
}
sub context {
	my $context = {};
	$context->{track} = $this_track->name;
	$context->{bus}   = $this_bus;
	$context->{op}    = $this_op;
	$context
}
	
sub process_command {
	state $total_effects_count;
	my $input = shift;
	my $input_was = $input;

	# parse repeatedly until all input is consumed
	
	my $was_error;
	
	try {
	while (do { no warnings 'uninitialized'; $input =~ /\S/ }) { 
		logpkg('debug',"input: $input");
		$text->{parser}->meta(\$input) or do
		{
			print("bad command: $input_was\n"); 
			$was_error++;
			system($config->{beep_command}) if $config->{beep_command};
			last;
		};
			
	}
	}
	catch { $was_error++; warn "caught error: $_" };
		
	$ui->refresh; # in case we have a graphic environment
	set_current_bus();
	# select chain operator if appropriate
	no warnings 'uninitialized';
	if ($this_op and $this_track->n eq chain($this_op)){
		eval_iam("c-select ".$this_track->n);
		eval_iam("cop-select ".  ecasound_effect_index($this_op));
	}

	my $result = check_fx_consistency();
	logpkg('logcluck',"Inconsistency found in effects data",
		Dumper ($result)) if $result->{is_error};

	my $current_count= 0;
	map{ $current_count++ } keys %{$fx->{applied}};
	if ($current_count < $total_effects_count){
		say "Total effects count: $current_count, change: ",$current_count - $total_effects_count; 
		$total_effects_count = $current_count;
	}
	# return true on complete success
	# return false on any part of command failure
	
	return ! $was_error
		
}
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
	my $format = "json";
	my $fname = join_path( project_root(), $tmp);
	save_system_state($fname,$format);
	file_pager("$fname.$format");
}


sub leading_track_spec {
	my $cmd = shift;
	if( my $track = $tn{$cmd} || $ti{$cmd} ){
		logpkg('debug',"Selecting track ",$track->name);
		$this_track = $track;
		set_current_bus();
		ecasound_select_chain( $this_track->n );
		1;
	}
		
}

### allow commands to abbreviate Audio::Nama::Class as ::Class

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
	EffectChain
	ChainSetup
);

my $namespace_root = 'Audio::Nama';

sub eval_perl {
	my $code = shift;
	map{ $code =~ s/(^|[^A-Za-z])::$_/$1$namespace_root\::$_/ } @namespace_abbreviations; # SKIP_PREPROC
	my $err;
	my @result = eval $code;
	if ($@){
		print( "Perl command failed: \ncode: $code\nerror: $@");
		undef $@;
	}
	else { 
		no warnings 'uninitialized';
		@result = map{ dumper($_) } @result;
		pager(join "\n", @result) 
	}	
}
} # end namespace abbreviations

#### Formatted text output

sub show_versions {
		no warnings 'uninitialized';
		if (@{$this_track->versions} ){
			"All versions: ". join(" ", 
				map { $_ . ( is_cached($this_track, $_)  and 'c') } @{$this_track->versions}
			). $/
		} else {}
}


sub show_send { "Send: ". $this_track->send_id. $/ 
					if $this_track->rec_status ne 'OFF'
						and $this_track->send_id
}

sub show_bus { "Bus: ". $this_track->group. $/ if $this_track->group ne 'Main' }

sub show_effects {
	::sync_effect_parameters();
	join "", map { show_effect($_) } @{ $this_track->ops };
}
sub list_effects {
	::sync_effect_parameters();
	join " ", "Effects on", $this_track->name.':', map{ list_effect($_) } @{ $this_track->ops };
}

sub list_effect {
	my $op_id = shift;
	my $name = name($op_id);
	$name .= q(, bypassed) if bypassed($op_id);
	($op_id eq $this_op ? '*' : '') . "$op_id ($name)";
}


sub show_effect {
 	my $op_id = shift;
	my @lines;
	my @params;
 	my $i = fxindex($op_id);
	my $name = name($op_id);
	my $ladspa_id = $fx_cache->{ladspa_label_to_unique_id}->{type($op_id)} ;
	$name .= " ($ladspa_id)" if $ladspa_id;
	$name .= " (bypassed)" if bypassed($op_id);
	$name .= "\n";
 	push @lines, "$op_id: $name";
	my @pnames = @{$fx_cache->{registry}->[ $i ]->{params}};
	{
	no warnings 'uninitialized';
	map
	{ 
		my $name = $pnames[$_]->{name};
		$name .= " (read-only)" if $pnames[$_]->{dir} eq 'output';
		push @lines, "    ".($_+1).q(. ) . $name . ": ".  params($op_id)->[$_] . "\n";
	} (0..scalar @pnames - 1);
	}
	map
	{ 	push @lines,
	 	"    ".($_+1).": ".  $fx->{params}->{$op_id}->[$_] . "\n";
	} (scalar @pnames .. (scalar @{$fx->{params}->{$op_id}} - 1)  )
		if scalar @{$fx->{params}->{$op_id}} - scalar @pnames - 1; 
	#push @lines, join("; ", @params) . "\n";
	@lines
}
sub named_effects_list {
	my @ops = @_;
	join("\n", map{ "$_ (" . ::name($_). ")" } @ops), "\n";
}
 
sub show_modifiers {
	join "", "Modifiers: ",$this_track->modifiers, $/
		if $this_track->modifiers;
}
sub show_region {
	my $t = $::this_track;
	return unless $t->rec_status eq 'MON';
	my @lines;
	push @lines,join " ",
		"Length:",time2($t->adjusted_length),"\n";
	$t->playat and push @lines,join " ",
		"Play at:",time2($t->adjusted_playat_time),
		join($t->playat, qw[ ( ) ])."\n";
	$t->region_start and push @lines,join " ",
		"Region start:",time2($t->adjusted_region_start_time),
		join($t->region_start, qw[ ( ) ])."\n";
	$t->region_end and push @lines,join " ",
		"Region end:",time2($t->adjusted_region_end_time),
		join($t->region_end, qw[ ( ) ])."\n";
	return(join "", @lines);
}
sub time2 {
	package ::;
	my $n = shift;
	dn($n,3),"/",colonize(int ($n + 0.5));
}
sub show_status {
	print "\n";
	package ::;
	my @modes;
	push @modes, $mode->{preview} if $mode->{preview};
	push @modes, "master" if $mode->{mastering};
	push @modes, "edit"   if ::edit_mode();
	push @modes, "offset run" if ::offset_run_mode();
	say   "Modes settings:   ", join(", ", @modes) if @modes;
	my @actions;
	push @actions, "record" if grep{ ! /Mixdown/ } ::ChainSetup::really_recording();
	push @actions, "playback" if grep { $_->rec_status eq 'MON' } 
		map{ $tn{$_} } $bn{Main}->tracks, q(Mixdown);

	# We only check Main bus for playback. 
	# sub-buses will route their playback signals through the 
	# Main bus, however it may be that sub-bus mixdown
	# tracks are set to REC (with rec-to-file disabled)
	
	
	push @actions, "mixdown" if $tn{Mixdown}->rec_status eq 'REC';
	say "Pending actions:  ", join(", ", @actions) if @actions;
	say "Main bus allows:  ", $bn{Main}->allows, " track status";
	say "Main bus version: ",$bn{Main}->version if $bn{Main}->version;
	say "Setup length is:  ", ::heuristic_time($setup->{audio_length}); 
	say "Run time limit:   ", ::heuristic_time($setup->{runtime_limit})
      if $setup->{runtime_limit};
		
}
sub placeholder { 
	my $val = shift;
	return $val if defined $val;
	$config->{use_placeholders} ? q(--) : q() 
}

sub show_inserts {
	my $output;
	$output = $::Insert::by_index{$this_track->prefader_insert}->dump
		if $this_track->prefader_insert;
	$output .= $::Insert::by_index{$this_track->postfader_insert}->dump
		if $this_track->postfader_insert;
	"Inserts:\n".join( "\n",map{" "x4 . $_ } split("\n",$output))."\n" if $output;
}

$text->{format_top} = <<TOP;
 No. Name            Ver  Set  Stat       Source       Bus         Vol  Pan
=============================================================================
TOP

$text->{format_divider} = '-' x 77 . "\n";

my $format_picture = <<PICTURE;
@>>  @<<<<<<<<<<<<<< @>>  @<<  @||||  @|||||||||||||   @<<<<<<<<<  @>>  @>> 
PICTURE

sub show_tracks_section {
    no warnings;
	#$^A = $text->{format_top};
    my @tracks = grep{ ref $_ } @_; # HACK! undef should not be passed
    map {   formline $format_picture, 
            $_->n,
            $_->name,
            placeholder( $_->current_version || undef ),
			lc $_->rw,
            $_->rec_status_display,
			placeholder($_->source_status),
			placeholder($_->group),
			placeholder($fx->{params}->{$_->vol}->[0]),
			placeholder($fx->{params}->{$_->pan}->[0]),
        } @tracks;
        
	my $output = $^A;
	$^A = "";
	#$output .= show_tracks_extra_info();
	$output;
}
sub show_tracks {
	my @array_refs = @_;
	my @list = $text->{format_top};
	for( @array_refs ){
		my ($mix,$bus) = splice @$_, 0, 2;
		push @list, 
			::Bus::settings_line($mix, $bus),
			show_tracks_section(@$_), 
	}
	@list
}
sub showlist {
	package ::;

	my @list = grep{ ! $_->hide } ::Track::all();
	my $section = [undef,undef,@list];
	my ($screen_lines, $columns);
	if( $text->{term} )
	{
		($screen_lines, $columns) = $text->{term}->get_screen_size();
	}

	return $section if scalar @list <= $screen_lines - 5
					or ! $screen_lines; 

	my @sections;

		push @sections, [undef,undef, map $tn{$_},qw(Master Mixdown)];
		push @sections, [$tn{Master},$bn{Main},map $tn{$_},$bn{Main}->tracks ];

	if( $mode->{mastering} ){

		push @sections, [undef,undef, map $tn{$_},$bn{Mastering}->tracks]

	} elsif($this_bus ne 'Main'){

		push @sections, [$tn{$this_bus},$bn{$this_bus},
					map $tn{$_}, $this_bus, $bn{$this_bus}->tracks]
	}
	@sections
}


format STDOUT_TOP =
Track Name      Ver. Setting  Status   Source           Send        Vol  Pan 
=============================================================================
.
format STDOUT =
@>>   @<<<<<<<<< @>    @<<     @<< @|||||||||||||| @||||||||||||||  @>>  @>> ~~
splice @{$text->{format_fields}}, 0, 9
.


#### Some Text Commands

sub t_load_project {
	package ::;
	return if engine_running() and ::ChainSetup::really_recording();
	my $name = shift;
	print "input name: $name\n";
	my $newname = remove_spaces($name);
	$newname =~ s(/$)(); # remove trailing slash
	print("Project $newname does not exist\n"), return
		unless -d join_path(project_root(), $newname);
	stop_transport();
	load_project( name => $newname );
	print "loaded project: $project->{name}\n";
	logpkg('debug',"load hook: $config->{execute_on_project_load}");
	::process_command($config->{execute_on_project_load});
}
sub t_create_project {
	package ::;
	my $name = shift;
	load_project( 
		name => remove_spaces($name),
		create => 1,
	);
	print "created project: $project->{name}\n";

}
sub mixdown {
	my $quiet = shift;
	pager3("Enabling mixdown to file") if ! $quiet;
	$tn{Mixdown}->set(rw => 'REC'); 
	$tn{Master}->set(rw => 'OFF'); 
	$bn{Main}->set(rw => 'REC');
}
sub mixplay { 
	my $quiet = shift;
	pager3("Setting mixdown playback mode.") if ! $quiet;
	$tn{Mixdown}->set(rw => 'MON');
	$tn{Master}->set(rw => 'MON'); 
	$bn{Main}->set(rw => 'OFF');
}
sub mixoff { 
	my $quiet = shift;
	pager3("Leaving mixdown mode.") if ! $quiet;
	$tn{Mixdown}->set(rw => 'OFF');
	$tn{Master}->set(rw => 'MON'); 
	$bn{Main}->set(rw => 'REC') if $bn{Main}->rw eq 'OFF';
}
sub remove_fade {
	my $i = shift;
	my $fade = $::Fade::by_index{$i}
		or print("fade index $i not found. Aborting."), return 1;
	print "removing fade $i from track " .$fade->track ."\n"; 
	$fade->remove;
}
sub import_audio {

	my ($track, $path, $frequency) = @_;
	
	$track->import_audio($path, $frequency);

	# check that track is audible

	$track->set(rw => 'MON');

}
sub destroy_current_wav {
	carp($this_track->name.": must be set to MON."), return
		unless $this_track->rec_status eq 'MON';
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
		restart_wav_memoize();
	}
	$text->{term}->remove_history($text->{term}->where_history);
	$this_track->set(version => 0);  # reset
	$this_track->set(version => $this_track->current_version); 
	1;
}

sub pan_check {
	my ($track, $new_position) = @_;
	my $current = $fx->{params}->{ $track->pan }->[0];
	$track->set(old_pan_level => $current)
		unless defined $track->old_pan_level;
	effect_update_copp_set(
		$track->pan,	# id
		0, 					# parameter
		$new_position,		# value
	);
}

sub remove_track_cmd {
	my ($track, $quiet) = @_;
	
	# avoid having ownerless SlaveTracks.  
 	::ChainSetup::remove_temporary_tracks();
 	
	# remove track quietly if requested
		if ( 	! $quiet 
			and ! $config->{quietly_remove_tracks}) 
		{
			my $name = $track->name; 
			my $reply = $text->{term}->readline("remove track $name? [n] ");
			$reply =~ /y/i or return
			pager2( "Removing track. All WAV files will be kept.")
		}
		$track->remove;
		1
}
sub unity {
	my ($track, $save_level) = @_;
	if ($save_level){
		$track->set(old_vol_level => params($track->vol)->[0]);
	}
	effect_update_copp_set( 
		$track->vol, 
		0, 
		$config->{unity_level}->{type($track->vol)}
	);
}
sub vol_back {
	my $track = shift;
	my $old = $track->old_vol_level;
	if (defined $old){
		effect_update_copp_set(
			$track->vol,	# id
			0, 					# parameter
			$old,				# value
		);
		$track->set(old_vol_level => undef);
	}
}
	
sub pan_back {
	my $track = shift;
	my $old = $track->old_pan_level;
	if (defined $old){
		effect_update_copp_set(
			$track->pan,	# id
			0, 					# parameter
			$old,				# value
		);
		$track->set(old_pan_level => undef);
	}
}
