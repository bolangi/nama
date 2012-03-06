# -------- Text Interface -----------
## The following subroutines/methods belong to the Text interface class

package ::Text;
use Modern::Perl; use Carp;
no warnings 'uninitialized';
use ::Globals qw(:all);
use ::Assign qw(:all);

our @ISA = '::';
our $VERSION = 1.071;

sub hello {"hello world!";}

sub loop {
	package ::;
	issue_first_prompt();
	$Event::DIED = sub {
	   my ($event, $errmsg) = @_;
	   say $errmsg;
	   $text->{term_attribs}->{line_buffer} = q();
	   $text->{term}->clear_message();
	   $text->{term}->rl_reset_line_state();
	};
	use Data::Dumper::Concise;
	Event::loop();
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
	my $i = $fx_cache->{full_label_to_index}->{ $fx->{applied}->{ $op_id }->{type} };
	my $name = $fx_cache->{registry}->[ $i ]->{name};
	($op_id eq $this_op ? '*' : '') . "$op_id ($name)";
}

sub show_effect {
 		my $op_id = shift;
		my @lines;
		my @params;
 		 my $i = ::effect_index(::type($op_id)); 
 		 push @lines, $op_id. ": " . $fx_cache->{registry}->[ $i ]->{name}.  "\n";
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
sub show_effect_chain_stack {
		return "Bypassed effect chains: "
				.scalar @{ $this_track->effect_chain_stack }.$/
			if @{ $this_track->effect_chain_stack } ;
		undef;
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

sub helpline {
	my $cmd = shift;
	my $out = "Command: $cmd\n";
	$out .=  "Shortcuts: $text->{commands}->{$cmd}->{short}\n"
			if $text->{commands}->{$cmd}->{short};	
	$out .=  "Category: $text->{commands}->{$cmd}->{type}\n";
	$out .=  "Description: $text->{commands}->{$cmd}->{what}\n";
	$out .=  "Usage: $cmd "; 

	if ( $text->{commands}->{$cmd}->{parameters} 
			&& $text->{commands}->{$cmd}->{parameters} ne 'none' ){
		$out .=  $text->{commands}->{$cmd}->{parameters}
	}
	$out .= "\n";
	my $example = $text->{commands}->{$cmd}->{example};
	#$example =~ s/!n/\n/g;
	if ($example){
		$out .=  "Example: ";
		if ($example =~ /\n/s){
			$example = "\n$example";    # add leading newline
			$example =~ s(\n)(\n    )g; # indent
		}
		$out .=  $example;
		$out .= "\n";
	}
	($/, ucfirst $out, $/);
	
}
sub helptopic {
	my $index = shift;
	$index =~ /^(\d+)$/ and $index = $help->{arr_topic}->[$index];
	my @output;
	push @output, "\n-- ", ucfirst $index, " --\n\n";
	push @output, $help->{topic}->{$index}, $/;
	@output;
}

sub help { 
	my $name = shift;
	chomp $name;
	#print "seeking help for argument: $name\n";
	$text->{iam}->{$name} and print <<IAM;

$name is an Ecasound command.  See 'man ecasound-iam'.
IAM
	my @output;
	if ( $help->{topic}->{$name}){
		@output = helptopic($name);
	} elsif ($name =~ /^0/){
		@output = map{ helptopic $_ } @{$help->{arr_topic}};
	} elsif ( $name =~ /^(\d+)$/ and $1 < 20  ){
		@output = helptopic($name)
	} else {
		my %helped = (); 
		my @help = ();
		if ( $text->{commands}->{$name} ){
			push @help, helpline($name);
			$helped{$name}++
		}
		map{  
			my $cmd = $_ ;
			if ($cmd =~ /$name/ ){
				push @help, helpline($cmd) unless $helped{$cmd}; 
				$helped{$cmd}++ ;
			}
			if ( ! $helped{$cmd} and
					grep{ /$name/ } split " ", $text->{commands}->{$cmd}->{short} ){
				push @help, helpline($cmd) 
			}
		} keys %{$text->{commands}};
		if ( @help ){ push @output, 
			qq("$name" matches the following commands:\n\n), @help;
		}
	}
	if (@output){
		::pager( @output ); 
	} else { print "$name: no help found.\n"; }
	
}
sub help_effect {
	my ($input, $id, $no_match, @output);
	$id = $input = shift;
	push @output, "\n";

	# e.g. help tap_reverb    
	#      help 2142
	#      help var_chipmunk # preset

	# convert digits to LADSPA label

	if ($id !~ /\D/){ $id = $fx_cache->{ladspa_id_to_label}->{$id} or $no_match++ } 

	# convert ladspa_label to el:ladspa_label
	# convert preset_name  to pn:preset_name
	
	if ($fx_cache->{full_label_to_index}->{$id}){} # we are ready
	elsif ( $fx_cache->{partial_label_to_full}->{$id} ) { $id = $fx_cache->{partial_label_to_full}->{$id} }
	else { $no_match++ }

	# one-line help for Ecasound presets
	
	if ($id =~ /pn:/) {
		push @output, grep{ /$id/  } @{$fx_cache->{user_help}};
	}

	# full help for LADSPA plugins
	
	elsif ( $id =~ /el:/) {
		@output = $fx_cache->{ladspa_help}->{$id};
	} else { 
		@output = qq("$id" is an Ecasound chain operator.
Type 'man ecasound' at a shell prompt for details.);
	}

	if( $no_match ){ print "No effects were found matching: $input\n\n"; }
	else { ::pager(@output) }
}

sub find_effect {
	my @keys = @_;
	#print "keys: @keys\n";
	#my @output;
	my @matches = grep{ 
		my $_help = $_; 
		my $didnt_match;
		map{ $_help =~ /\Q$_\E/i or $didnt_match++ }  @keys;
		! $didnt_match; # select if no cases of non-matching
	} @{$fx_cache->{user_help}};
	if ( @matches ){
	::pager( $text->{wrap}->paragraphs(@matches) , "\n" );
	} else { print join " ", "No effects were found matching:",@keys,"\n\n" }
}


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
	save_state();
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

## NO-OP GRAPHIC METHODS 

no warnings qw(redefine);
sub init_gui {}
sub transport_gui {}
sub group_gui {}
sub track_gui {}
sub preview_button {}
sub create_master_and_mix_tracks {}
sub time_gui {}
sub refresh {}
sub refresh_group {}
sub refresh_track {}
sub flash_ready {}
sub update_master_version_button {}
sub update_version_button {}
sub paint_button {}
sub project_label_configure{}
sub length_display{}
sub clock_display {}
sub clock_config {}
sub manifest {}
sub global_version_buttons {}
sub destroy_widgets {}
sub destroy_marker {}
sub restore_time_marks {}
sub show_unit {}
sub add_effect_gui {}
sub remove_effect_gui {}
sub marker {}
sub init_palette {}
sub save_palette {}
sub paint_mute_buttons {}
sub remove_track_gui {}
sub reset_engine_mode_color_display {}
sub set_engine_mode_color_display {}

1;
__END__
