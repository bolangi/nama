# --------------------- Grammar ----------------------

package ::;
use Modern::Perl;

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
	my @result;
	@result = eval $code;
	if ($@){
		print( "Perl command failed: \ncode: $code\nerror: $@");
		undef $@;
	}
	else { pager(join "\n", @result) }
	print "\n";
}	
}

sub show_versions {
		if (@{$this_track->versions} ){
			my $cache_map = $this_track->cache_map;
			"All versions: ". join(" ", 
				map { $_ . ( $cache_map->{$_} and 'c') } @{$this_track->versions}
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
	my $type = ::original_type($op_id);
	my $i = ::effect_index($type);
	my $name = ::original_name($op_id);
	$name .= q(, bypassed) if my @dummy = ::is_bypassed($op_id);
	($op_id eq $this_op ? '*' : '') . "$op_id ($name)";
}

sub show_effect {
 		my $op_id = shift;
		my @lines;
		my @params;

 		my $name =  $op_id. ": " . ::original_name($op_id);
		my $i = ::effect_index(::original_type($op_id));
		 
		return "$name (bypassed)\n" if my @dummy = ::is_bypassed($op_id);

		# return effect parameters for the non-bypass case

		$name .= "\n";

		 push @lines, $name;
 		 my @pnames = @{$fx_cache->{registry}->[ $i ]->{params}};
			map{ push @lines,
			 	"    ".($_+1).q(. ) . $pnames[$_]->{name} . ": ".  $fx->{params}->{$op_id}->[$_] . "\n";
		 	} (0..scalar @pnames - 1);
			map{ push @lines,
			 	"    ".($_+1).": ".  $fx->{params}->{$op_id}->[$_] . "\n";
		 	} (scalar @pnames .. (scalar @{$fx->{params}->{$op_id}} - 1)  )
				if scalar @{$fx->{params}->{$op_id}} - scalar @pnames - 1; 
			#push @lines, join("; ", @params) . "\n";
		@lines
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
@>>  @<<<<<<<<<<<<<<< @>  @<<  @||||  @|||||||||||||   @<<<<<<<<<  @>>  @>> 
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
	
	my ($screen_lines, $columns) = $text->{term}->get_screen_size();

	return $section if scalar @list <= $screen_lines - 5;

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
	$debug and print "hook: $config->{execute_on_project_load}\n";
	::command_process($config->{execute_on_project_load});
		
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
	print "Enabling mixdown to file.\n";
	$tn{Mixdown}->set(rw => 'REC'); 
	$tn{Master}->set(rw => 'OFF'); 
	$bn{Main}->set(rw => 'REC');
}
sub mixplay { 
	print "Setting mixdown playback mode.\n";
	$tn{Mixdown}->set(rw => 'MON');
	$tn{Master}->set(rw => 'MON'); 
	$bn{Main}->set(rw => 'OFF');
}
sub mixoff { 
	print "Leaving mixdown mode.\n";
	$tn{Mixdown}->set(rw => 'OFF');
	$tn{Master}->set(rw => 'MON'); 
	$bn{Main}->set(rw => 'REC') if $bn{Main}->rw eq 'OFF';
}
sub bunch {
	package ::;
	my ($bunchname, @tracks) = @_;
	if (! $bunchname){
		::pager(yaml_out( $project->{bunch} ));
	} elsif (! @tracks){
		$project->{bunch}->{$bunchname} 
			and print "bunch $bunchname: @{$project->{bunch}->{$bunchname}}\n" 
			or  print "bunch $bunchname: does not exist.\n";
	} elsif (my @mispelled = grep { ! $tn{$_} and ! $ti{$_}} @tracks){
		print "@mispelled: mispelled track(s), skipping.\n";
	} else {
	$project->{bunch}->{$bunchname} = [ @tracks ];
	}
}
sub add_to_bunch {}

sub remove_fade {
	my $i = shift;
	my $fade = $::Fade::by_index{$i}
		or print("fade index $i not found. Aborting."), return 1;
	print "removing fade $i from track " .$fade->track ."\n"; 
	$fade->remove;
}

1;
