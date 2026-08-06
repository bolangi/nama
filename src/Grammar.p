# --------------------- Command Grammar ----------------------

package ::;
use ::Effect  qw(:all);
use v5.36;
use Path::Tiny qw(path);

sub setup_grammar {

	### COMMAND LINE PARSER 

	logsub((caller(0))[3]);

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
	
	# prepend 'm' to all midish commands
	# suppress midi record, play, stop commands - Nama will handle them
	# also suppress ct tnew tdel tren
	my %skip = map{$_, 1} qw(r p s ct tnew tdel tren);

	$text->{midi_cmd} = 
	{
		map{ 'm'.$_, 1} grep{ !$skip{$_} } split " ", get_data_section("midi_commands")
	};
	for (keys %{$text->{midi_cmd}}){
		::terminal_say("$_: midi command same as Nama command") if $text->{commands}->{$_}
	}

}
sub process_line {
	state $total_effects_count;
	logsub((caller(0))[3]);
	no warnings 'uninitialized';
	my ($user_input) = @_;
	logpkg('debug',"user input: $user_input");
	if (defined $user_input and $user_input !~ /^\s*$/) {
		push $text->{command_history}->@*, $user_input;
		$text->{command_index} = scalar $text->{command_history}->@*;
		# convert hyphenated commands to underscore form
		while( my($from, $to) = each %{$text->{hyphenated_commands}} ){ $user_input =~ s/$from/$to/g }
			my $context = context();
			my $success = nama_cmd( $user_input );
			my $command_stamp = { context => $context, 
								  command => $user_input };
			push(@{$project->{command_buffer}}, $command_stamp);
			
			reconfigure_engine();

		# reset current track to Main if it is
		# undefined, or the track has been removed
		# from the index
		$this_track = $tn{Main} if ! $this_track or
			(ref $this_track and ! $tn{$this_track->name});
	}
	if (! $this_engine->started() ){
		my $result = check_fx_consistency();
		::terminal_say("Inconsistency found in effects data",
			Dumper ($result)) if $result->{is_error};
	}
	my $output = delete $text->{output_buffer};
	revise_prompt();
}
sub context {
	return unless $this_track;
	my $context = {};
	$context->{track} = $this_track->name;
	$context->{bus}   = $this_bus;
	$context->{op}    = $this_track->op;
	$context
}
sub nama_cmd {
	my $input_was = my $input = shift;

	# parse repeatedly until all input is consumed
	# return true on complete success
	# return false if any part of command fails
	
	my $was_error = 0;
	
	try {
		while (do { no warnings 'uninitialized'; $input =~ /\S/ }) { 
			logpkg('debug',"input: $input");
			$text->{parser}->meta(\$input) or do
			{
				throw("bad command: $input_was\n"); 
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
	# and there is a current track

	$this_engine->valid_setup() or return;
	if ($this_track){
		my $FX = fxn($this_track->op);
		if ($FX and $this_track->n eq $FX->chain){
			$this_engine->current_chain($this_track->n);
			$FX->is_controller 
				? $this_engine->current_controller($FX->ecasound_controller_index)
				: $this_engine->current_chain_operator($FX->ecasound_effect_index);
		}
	}

	! $was_error
}
sub do_user_command {
	my($cmd, @args) = @_;
	$text->{user_command}->{$cmd}->(@args);
}	

sub do_script {

	my $name = shift;
	my $script;
	if ($name =~ / /){
		$script = $name
	}
	else {
		my $filename;
		# look in project_dir() and project_root()
		# if filename provided does not contain slash
		if( $name =~ m!/!){ $filename = $name }
		else {
			$filename = join_path(project_dir(),$name);
			if(-e $filename){}
			else{ $filename = join_path(project_root(),$name) }
		}
		-e $filename or throw("$filename: file not found. Skipping"), return;
		$script = path($filename)->slurp_utf8
	}
	my @lines = split "\n",$script;
	my $old_opt_r = $config->{opts}->{R};
	$config->{opts}->{R} = 1; # turn off auto reconfigure
	map{ s/#.*$// } @lines;
	for my $input (@lines) { process_line($input) unless $input =~ /^\s*#/};
	$config->{opts}->{R} = $old_opt_r;
}

sub dump_all {
	my $tmp = ".dump_all";
	my $format = "json";
	my $fname = join_path( project_root(), $tmp);
	save_system_state($fname,$format);
	file_pager("$fname.$format");
}


sub set_current_track {
	my $cmd = shift;
	if( my $track = $tn{$cmd} || $ti{$cmd} ){
		logpkg('debug',"Selecting track ",$track->name);
		$track->select_track;
		1
	}
}


sub eval_perl {
	my $code = shift;
	$code = expand_root($code);
	my $err;
	undef $text->{eval_result};
	my @result = eval $code;
	if ($@){
		throw( "Perl command failed: \ncode: $code\nerror: $@");
		undef $@;
	}
	else { 
		no warnings 'uninitialized';
		@result = map{ dumper($_) } @result;
		$text->{eval_result} = join " ", @result;
		pager(join "\n", @result) 
	}	
}

sub expand_root {
	my ($text) = @_;
	my $new_root = 'Audio::Nama';

		my $new = join "\n",map{ 
			s/([^\w\}\\\/]|^)(::)([\w:])/$1$new_root$2$3/g unless /SKIP_PREPROC/;
			s/([^\w\}\\\/]|^)(::)([^\w])/$1$new_root$3/mg unless /SKIP_PREPROC/;
			$_;
		} split "\n",$text;
		$new;
}
::terminal_say(expand_root('Audio::Nama', '@::Tempo::chunks'));
#### Formatted text output

sub show_versions {
		no warnings 'uninitialized';
		if (@{$this_track->versions} ){
			"Versions: ". join(" ", 
				map { 
					my $cached = is_cached($this_track, $_) ? 'c' : '';
					$_ . $cached } @{$this_track->versions}
			). $/
		} else {}
}
sub show_track_comment {
	my $track = shift;
	my $text = $track->is_comment;
	$text and "Track comment: $text\n";
}
sub show_track_comment_brief {
	my $track = shift;
	my $text = $track->is_comment;
	$text and "Comment: $text\n";
}
sub show_version_comment {
	my ($track, $version) = @_;
	my $text = $track->is_version_comment($version);
	$text and "Version comment: $text\n";
}
sub show_version_comment_brief {
	my ($track, $version) = @_;
	my $text = $track->is_version_comment($version);
	$text and "  $version: $text\n";
}
sub show_send { "Send: ". $this_track->send_id. $/ 
					if ! $this_track->candidate_off
						and $this_track->send_id
}

sub show_bus { "Bus: ". $this_track->group. $/ if $this_track->group ne 'Main' }

sub show_effects {
	::sync_effect_parameters();
	join "", map { show_effect($_) } @{ $this_track->ops };
}
sub list_effects {
	::sync_effect_parameters();
	join "", "Effects on ", $this_track->name,":\n", map{ list_effect($_) } @{ $this_track->ops };
}

sub list_effect {
	my $op_id = shift;
	my $FX = fxn($op_id);
	my $line = $FX->nameline;
	$line .= q(, bypassed) if $FX->bypassed;
	($op_id eq $this_track->op ? ' *' : '  ') . $line;
}

sub show_effect {
 	my $op_id = shift;
	my $with_track = shift;
	my $FX = fxn($op_id);
	return unless $FX;
	my @lines = $FX->nameline;
	#EQ: GVerb, gverb, 1216, bypassed, famp5, neap
 	my $i = $FX->registry_index;
	my @pnames = @{$fx_cache->{registry}->[ $i ]->{params}};
	{
	no warnings 'uninitialized';
	push @lines, parameter_info_padded($op_id, $_) for 0..scalar @pnames - 1;
	}
	scalar @{$FX->params} - scalar @pnames - 1 
		and push @lines, parameter_info_padded($op_id, $_) for scalar @pnames .. (scalar @{$FX->params} - 1);
	@lines
}
sub parameter_info {
	no warnings 'uninitialized';
	my ($op_id, $parameter) = @_;  # zero based
	my $FX = fxn($op_id);
	return unless $FX;
	my $entry = $FX->about->{params}->[$parameter];
	my $name = $entry->{name};
	$name .= " (read-only)" if $entry->{dir} eq 'output';
	($parameter+1).q(. ) . $name . ": ".  $FX->params->[$parameter];
}
sub parameter_info_padded {
	" "x 4 . parameter_info(@_) . "\n";
}
sub named_effects_list {
	my @ops = @_;
	join("\n", map{ "$_ (" . fxn($_)->name. ")" } @ops), "\n";
}
 
sub show_modifiers {
	join "", "Modifiers: ",$this_track->modifiers, $/
		if $this_track->modifiers;
}
sub show_region {
	my $t = $::this_track;
	return unless $t->candidate_play;
	my @lines;
	push @lines,join " ",
		"Length:",time2($t->adjusted_duration),"\n";
	$t->playat and push @lines,join " ",
		"Play at:",time2($t->adjusted_timeline_position),
		join($t->playat, qw[ ( ) ])."\n";
	$t->region_start and push @lines,join " ",
		"Region start:",time2($t->adjusted_startpoint),
		join($t->region_start, qw[ ( ) ])."\n";
	$t->region_end and push @lines,join " ",
		"Region end:",time2($t->adjusted_endpoint),
		join($t->region_end, qw[ ( ) ])."\n";
	return(join "", @lines);
}
sub time2 {
	package ::;
	my $n = shift;
	dn($n,3),"/",colonize(int ($n + 0.5));
}
sub show_status {
	package ::;
	my @output;
	my @modes;
	push @modes, 'preview' if $mode->{preview};
	push @modes, 'doodle' if $mode->{doodle};
	push @modes, "master" if $mode->mastering;
	push @modes, "edit"   if ::edit_mode();
	push @modes, "offset run" if ::is_offset_run_mode();
	push @output, "Modes settings:   ", join(", ", @modes), $/ if @modes;
	my @actions;
	push @actions, "record" if grep{ ! /Mixdown/ } ::ChainSetup::really_recording();
	push @actions, "playback" if grep { $_->effective_play }
		map{ $tn{$_} } $bn{Main}->tracks, q(Mixdown);

	# We only check Main bus for playback. 
	# buses will route their playback signals through the 
	# Main bus, however it may be that other bus mixdown
	# tracks are set to REC (with rec-to-file disabled)
	
	
	push @actions, "mixdown" if $tn{Mixdown}->effective_rec;
	push @output, "Pending actions:  ", join(", ", @actions), $/ if @actions;
	push @output, "Main bus version: ",$bn{Main}->version, $/ if $bn{Main}->version;
	push @output, "Setup length is:  ", ::heuristic_time($setup->{audio_length}), $/; 
	push @output, "Run time limit:   ", ::heuristic_time($setup->{runtime_limit}), $/
      if $setup->{runtime_limit};
	@output
}
sub placeholder { 
	my $val = shift;
	return $val if defined $val and $val !~ /^\s*$/;
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
 No. Name            Setting        Source             Destination  Vol   Pan
================================================================================
TOP

$text->{format_divider} = '-' x 77 . "\n";

my $format_picture = <<PICTURE;
@>>  @<<<<<<<<<<<<<< @<<<<<<<<<<<<  @<<<<<<<<<<<<<<<<< @<<<<<<<<<<< @>>>  @>>>
PICTURE

sub show_tracks_section {
    no warnings;
	#$^A = $text->{format_top};
    my @tracks = grep{ ref $_ } @_; # HACK! undef should not be passed
    map {   formline $format_picture, 
            $_->n,
            $_->name,
			$_->show_tracks_setting,
			placeholder($_->show_tracks_source),
			placeholder($_->show_tracks_destination),
			placeholder($_->show_tracks_volume),
			placeholder($_->show_tracks_pan),
			($_->is_comment ? 'C' : undef)
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

	my @list = grep{ ! $_->hide } ::all_tracks();
	my $section = [undef,undef,@list];

	return $section ;
=begin comment

	if scalar @list <= $screen_lines - 5 or ! $screen_lines; 

	my @sections;

		push @sections, [undef,undef, map $tn{$_},qw(Main Mixdown)];
		push @sections, [$tn{Main},$bn{Main},map $tn{$_},$bn{Main}->tracks ];

	if( $mode->mastering ){

		push @sections, [undef,undef, map $tn{$_},$bn{Mastering}->tracks]

	} elsif($this_bus ne 'Main'){

		push @sections, [$tn{$this_bus},$bn{$this_bus},
					map $tn{$_}, $this_bus, $bn{$this_bus}->tracks]
	}
	@sections

=end comment

=cut
}


#### Some Text Commands

sub t_load_project {
	package ::;
	return if $this_engine->started() and ::ChainSetup::really_recording();
	my $name = shift;
	my %args = @_;
	pager("input name: $name\n");
	$name = sanitize($name);
	throw("Project $name does not exist\n"), return
		unless -d join_path(project_root(), $name) or $args{create};
	stop_transport() if $this_engine->started(); 
	load_project( name => $name, %args );
	pager("loaded project: $project->{name}\n") unless $args{create};
	{no warnings 'uninitialized';
	logpkg('debug',"load hook: $config->{execute_on_project_load}");
	}
	::nama_cmd($config->{execute_on_project_load});
}
sub sanitize {
	my $name = shift;
	my $newname = remove_spaces($name);
	$newname =~ s(/$)(); # remove trailing slash
	$newname;
}
sub t_create_project {
	package ::;
	my $name = shift;
	t_load_project($name, create => 1);
	pager("created project: $project->{name}\n");

}
sub mixdown {
	::terminal_say("Enabling mixdown to file") if ! $quiet;
	$tn{Mixdown}->set(rw => REC); 
	$tn{Main}->set(rw => MON); 
}
sub mixplay { 
	::terminal_say("Setting mixdown playback mode.") if ! $quiet;
	$tn{Mixdown}->set(rw => PLAY);
	$tn{Main}->set(rw => OFF); 
}
sub mixoff { 
	::terminal_say("Leaving mixdown mode.") if ! $quiet;
	$tn{Mixdown}->set(rw => OFF);
	$tn{Main}->set(rw => MON); 
}
sub remove_fade {
	my $i = shift;
	my $fade = $::Fade::by_index{$i}
		or throw("fade index $i not found. Aborting."), return 1;
	pager("removing fade $i from track " .$fade->track ."\n");
	$fade->remove;
}
sub import_audio {

	my ($track, $path, $frequency) = @_;
	
	$track->import_audio($path, $frequency);

	# check that track is audible

	$track->set(rw => PLAY);

}
sub destroy_current_wav {
	throw($this_track->name.": must be set to PLAY."), return
		unless $this_track->candidate_play;
	$this_track->current_version or
		throw($this_track->name, 
			": No current version (track set to OFF?) Skipping."), return;
	my $wav = $this_track->full_path;
		# remove version comments, if any
		delete $project->{track_version_comments}{$this_track->name}{$this_track->version};
		pager("Unlinking $wav");
		unlink $wav or warn "couldn't unlink: $!\n";
		refresh_wav_cache();
	$this_track->set(version => $this_track->last); 
	1;
}

sub pan_set {
	my ($track, $new_position) = @_;
	my $current = $track->pan_o->params->[0];
	$track->set(old_pan_level => $current)
		unless defined $track->old_pan_level;
	update_effect(
		$track->pan_id,	# id
		0, 					# parameter
		$new_position,		# value
	);
}

sub remove_track_cmd {
	my ($track) = @_;
	
	# avoid having ownerless SlaveTracks.  
 	::ChainSetup::remove_temporary_tracks();
		$quiet or pager( join '',"Removing track ",$track->name,". WAV files will be kept. Other data will be lost.");
		remove_submix_helper_tracks($track->name);
		$track->remove;
		$this_track = $tn{Main};
		1
}
sub unity {
	my ($track, $save) = @_;
	if ($save){
		$track->set(old_vol_level => $track->volume_effect->params->[0]);
	}
	update_effect( 
		$track->vol, 
		0, 
		$config->{unity_level}->{$track->volume_effect->type}
	);
}
sub vol_back {
	my $track = shift;
	my $old = $track->old_vol_level;
	if (defined $old){
		update_effect(
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
		update_effect(
			$track->pan_id,	# id
			0, 					# parameter
			$old,				# value
		);
		$track->set(old_pan_level => undef);
	}
}

sub get_sample_rate {
	pager("project $project->{name}: audio engine sample rate is ",$project->{sample_rate} );
	$project->{sample_rate}
}

sub set_sample_rate {
	my ($srate) = @_;
	my @allowable = qw{ 96000 88200 64000 48000 44100 32000 24000 22050 16000 11025 8000 };
	my %allowable = map{$_ => 1} @allowable; 
	if ( $allowable{$srate} ){
		$project->{sample_rate} = $srate;
		pager("project $project->{name}: setting audio engine sample rate to $srate Hz for future runs." );
		$srate
	}
	else {
		get_sample_rate();
		pager qq(The value "$srate" is not an allowable sample rate.);
		pager("Use one of: @allowable");
	}
}
sub list_buses {
	::pager(map{ $_->list } ::Bus::all())

}
