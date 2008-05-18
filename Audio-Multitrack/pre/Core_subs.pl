use Carp;

sub mainloop { 
	prepare(); 
	$ui->loop;
}
sub status_vars {
	serialize -class => '::', -vars => \@status_vars;
}
sub config_vars {
	serialize -class => '::', -vars => \@config_vars;
}

sub discard_object {
	shift @_ if (ref $_[0]) =~ /Multitrack/;  # HARDCODED
	@_;
}

sub first_run {
	if ( ! -e $wav_dir ) {
		print "Project directory $wav_dir not found.\n";
		print "Would you like to create it? [Y] ";
		my $reply = <STDIN>;
		chomp $reply;
		$reply = lc $reply;
		if ($reply !~ /n/i) {
			create_dir $wav_dir;
			print "\n... Done!\n\n";
		} 
	}

		my $config = join_path($ENV{HOME}, ".ecmdrc");
	if ( ! -e $config) {
		print "Configuration file $config not found.\n";
		print "Would you like to create it? [Y] ";
		my $reply = <STDIN>;
		chomp $reply;
		if ($reply !~ /n/i){
			$default =~ s/wav_dir:.*$/wav_dir: $ENV{HOME}\/ecmd/m;
			$default > io( $config );
			print "\n.... Done!\n\nPlease edit this file and restart program\n";
		}
		exit;
	}
}
	

	
sub prepare {  

	$debug2 and print "&prepare\n";
	

	$ecasound  = $ENV{ECASOUND} ? $ENV{ECASOUND} : q(ecasound);
	new_engine();

	### Option Processing ###
	# push @ARGV, qw( -e  );
	#push @ARGV, qw(-d /media/sessions test-abc  );
	getopts('mcegsdt:f:', \%opts); 
	#print join $/, (%opts);
	# d: ecmd project dir
	# c: create project
	# f: configuration file
	# g: gui mode # default
	# m: don't load state info on initial startup
	# e: don't load static effects data
	# s: don't load static effects data cache
	# t: text mode
	$project_name = shift @ARGV;
	$debug and print "project name: $project_name\n";

	$debug and print ("\%opts\n======\n", yaml_out(\%opts)); ; 

	read_config(); 

	# wav_dir should be called ecmd_dir 
	$wav_dir = $opts{d} if $opts{d};
	$wav_dir = join_path($ENV{HOME}, "ecmd" )  unless $wav_dir ;
	$wav_dir = File::Spec::Link->resolve_all( $wav_dir ); # resolve links

	first_run();
	
	# init our buses
	
	$tracker_bus  = ::Bus->new(
		name => 'Tracker_Bus',
		groups => [qw(Tracker)],
		tracks => [],
		rules  => [ qw( mix_setup rec_setup mon_setup multi rec_file) ],
	);

	# print join (" ", map{ $_->name} ::Rule::all_rules() ), $/;

	$master_bus  = ::Bus->new(
		name => 'Master_Bus',
		rules  => [ qw(mixer_out mix_link) ],
		groups => ['Master'],
	);
	$mixdown_bus  = ::Bus->new(
		name => 'Mixdown_Bus',
		groups => [qw(Mixdown) ],
		rules  => [ qw(mon_setup mix_setup_mon  mix_file ) ],
	);


	prepare_static_effects_data() unless $opts{e};

	#print "keys effect_i: ", join " ", keys %effect_i;
	#map{ print "i: $_, code: $effect_i{$_}->{code}\n" } keys %effect_i;
	#die "no keys";	
	
	# UI object for interface polymorphism
	
	$ui = ! $opts{t} ?  ::Graphical->new : ::Text->new;

	$ui->init_gui;
	$ui->transport_gui;
	#$ui->oid_gui;
	$ui->time_gui;

	#print "project_name: $project_name\n";
	load_project( name => $project_name, create => $opts{c}) 
	  if $project_name;

	# if there is no project name, we still init using pwd

	$debug and print "wav_dir: ", wav_dir(), $/;
	$debug and print "this_wav_dir: ", this_wav_dir(), $/;
	$debug and print "project_dir: ", project_dir() , $/;
	1;	
}




sub eval_iam {
	local $debug = 0;	
	$debug2 and print "&eval_iam\n";
	my $command = shift;
	$debug and print "iam command: $command\n";
	my $result = $e->eci($command);
	$debug and print "$result\n" unless $command =~ /register/;
	my $errmsg = $e->errmsg();
	# $errmsg and carp("IAM WARN: ",$errmsg), 
	# not needed ecasound prints error on STDOUT
	$e->errmsg('');
	$result;
}
## configuration file

sub wav_dir { $wav_dir };  # we agree to hereinafter use &wav_dir
sub config_file { $opts{f} ? $opts{f} : ".ecmdrc" }
sub this_wav_dir {$project_name and join_path(&wav_dir,
$project_name, q(.wav) ) }
sub project_dir  {$project_name and join_path(&wav_dir, $project_name)
}

sub global_config{
print ("reading config file $opts{f}\n"), return io( $opts{f})->all if $opts{f} and -r $opts{f};
my @search_path = (project_dir(), $ENV{HOME}, wav_dir() );
my $c = 0;
	map{ 
#print $/,++$c,$/;
			if (-d $_) {
				my $config = join_path($_, config_file());
				#print "config: $config\n";
				if( -f $config ){ 
					my $yml = io($config)->all ;
					return $yml;
				}
			}
		} ( @search_path) 
}

sub read_config {
	$debug2 and print "&read_config\n";
	
	my $config = shift;
	my $yml = length $config > 100 ? $config : $default;
	strip_comments( $yml );
	strip_blank_lines( $yml );
	$yml !~ /^---/ and $yml = join "\n", "---", $yml, "...";
	%cfg = %{  $yr->read($yml)  };
	#print yaml_out( $cfg{abbreviations}); exit;
	*subst = \%{ $cfg{abbreviations} }; # alias
#	*devices = \%{ $cfg{devices} }; # alias
	#print yaml_out( \%subst ); exit;
	walk_tree(\%cfg);
	walk_tree(\%cfg); # second pass completes substitutions
	assign_var( \%cfg, @config_vars); 
	#print "config file: $yml";

}
sub walk_tree {
	#$debug2 and print "&walk_tree\n";
	my $ref = shift;
	map { substitute($ref, $_) } 
		grep {$_ ne q(abbreviations)} 
			keys %{ $ref };
}
sub substitute{
	my ($parent, $key)  = @_;
	my $val = $parent->{$key};
	#$debug and print qq(key: $key val: $val\n);
	ref $val and walk_tree($val)
		or map{$parent->{$key} =~ s/$_/$subst{$_}/} keys %subst;
}
## project handling

sub load_project {
	local $debug = 1;
	my %h = @_;
	$debug2 and print "&load_project\n";
	print yaml_out \%h;
	# return unless $h{name} or $project;

	# we could be called from Tk with variable $project _or_
	# called with a hash with 'name' and 'create' fields.
	
	my $project = remove_spaces($project); # internal spaces to underscores
	$project_name = $h{name} if $h{name};
	$project_name = $project if $project;
	$debug and print "project name: $project_name create: $h{create}\n";
	$project_name and $h{create} and 
		print ("Creating directories....\n"),
		map{create_dir($_)} &this_wav_dir, &project_dir;
	read_config( global_config() ); 
	initialize_rules();
	initialize_project_data();
	remove_small_wavs(); 
	#print "reached here!!!\n";

	retrieve_state( $h{settings} ? $h{settings} : $state_store_file) unless $opts{m} ;
	$opts{m} = 0; # enable 
	
	dig_ruins() unless $#::Track::by_index > 2;

	$tracker_group_widget = $ui->group_gui('Tracker');

	# possible null if Text mode
	
	$ui->global_version_buttons(); 
	$ui->refresh_t;

#The mix track will always be track index 1 i.e. $ti[$n]
# for $n = 1, And take index 1.

}

sub initialize_rules {

	package ::Rule;
		$n = 0;
		@by_index = ();	# return ref to Track by numeric key
		%by_name = ();	# return ref to Track by name
		%rule_names = (); 
	package ::;

	my $mixer_out = ::Rule->new( #  this is the master output
		name			=> 'mixer_out', 
		chain_id		=> 'MixerOut', 

		target			=> 'MON',

	# condition =>	sub{ defined $inputs{mixed}  
	# 	or $debug and print("no customers for mixed, skipping\n"), 0},

		input_type 		=> 'mixed', # bus name
		input_object	=> $loopb, 

		output_type		=> 'device',
		output_object	=> $mixer_out_device,

		status			=> 1,

	);

	my $mix_down = ::Rule->new(

		name			=> 'mix_file', 
		chain_id		=> 'MixDown',
		target			=> 'REC', 
		
		# sub{ defined $outputs{mixed} or $debug 
		#		and print("no customers for mixed, skipping mixdown\n"), 0}, 

		input_type 		=> 'mixed', # bus name
		input_object	=> $loopb,

		output_type		=> 'file',


		# - a hackish conditional way to include the mixdown format
		# - seems to work
		# - it would be better to add another output type

		output_object   => sub {
			my $track = shift; 
			join " ", $track->full_path, $mix_to_disk_format},

		status			=> 1,
	);

	my $mix_link = ::Rule->new(

		name			=>  'mix_link',
		chain_id		=>  sub{ my $track = shift; $track->n },
		target			=>  'all',
		condition =>	sub{ defined $inputs{mixed}->{$loopb} },
		input_type		=>  'mixed',
		input_object	=>  $loopa,
		output_type		=>  'mixed',
		output_object	=>  $loopb,
		status			=>  1,
		
	);

	my $mix_setup = ::Rule->new(

		name			=>  'mix_setup',
		chain_id		=>  sub { my $track = shift; "J". $track->n },
		target			=>  'all',
		input_type		=>  'cooked',
		input_object	=>  sub { my $track = shift; "loop," .  $track->n },
		output_object	=>  $loopa,
		output_type		=>  'cooked',
		condition 		=>  sub{ defined $inputs{mixed}->{$loopb} },
		status			=>  1,
		
	);

	my $mix_setup_mon = ::Rule->new(

		name			=>  'mix_setup_mon',
		chain_id		=>  sub { my $track = shift; "K". $track->n },
		target			=>  'MON',
		input_type		=>  'cooked',
		input_object	=>  sub { my $track = shift; "loop," .  $track->n },
		output_object	=>  $loopa,
		output_type		=>  'cooked',
		# condition 		=>  sub{ defined $inputs{mixed} },
		status			=>  1,
		
	);



	my $mon_setup = ::Rule->new(
		
		name			=>  'mon_setup', 
		target			=>  'MON',
		chain_id 		=>	sub{ my $track = shift; $track->n },
		input_type		=>  'file',
		input_object	=>  sub{ my $track = shift; $track->full_path },
		output_type		=>  'cooked',
		output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
		post_input		=>	sub{ my $track = shift; $track->mono_to_stereo},
		condition 		=> sub { my $track = shift; 
								return "satisfied" if defined
								$inputs{cooked}->{"loop," . $track->n}; 
								0 } ,
		status			=>  1,
	);
		
	my $rec_file = ::Rule->new(

		name		=>  'rec_file', 
		target		=>  'REC',
		chain_id	=>  sub{ my $track = shift; 'R'. $track->n },   
		input_type	=>  'device',
		input_object=>  $record_device,
		output_type	=>  'file',
		output_object   => sub {
			my $track = shift; 
			join " ", $track->full_path, $raw_to_disk_format},
		status		=>  1,
	);

	# Rec_setup: must come last in oids list, convert REC
	# inputs to stereo and output to loop device which will
	# have Vol, Pan and other effects prior to various monitoring
	# outputs and/or to the mixdown file output.
			
	my $rec_setup = ::Rule->new(

		name			=>	'rec_setup', 
		chain_id		=>  sub{ my $track = shift; $track->n },   
		target			=>	'REC',
		input_type		=>  'device',
		input_object	=>  $record_device,
		output_type		=>  'cooked',
		output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
		post_input			=>	sub{ my $track = shift;
										$track->rec_route .
										$track->mono_to_stereo 
										},
		condition 		=> sub { my $track = shift; 
								return "satisfied" if defined
								$inputs{cooked}->{"loop," . $track->n}; 
								0 } ,
		status			=>  1,
	);

	# route cooked signals to multichannel device in the 
	# case that monitor_channel is specified
	#
	# thus we could apply guitar effects for output
	# to a PA mixing board
	#
	# seems ready... just need to turn on status!
	
	my $multi  = ::Rule->new(  

		name			=>  'multi', 
		target			=>  'REC',
		chain_id 		=>	sub{ my $track = shift; "M".$track->n },
		input_type		=>  'device', # raw
		input_object	=>  sub{ my $track = shift; "loop," .  $track->n},
		output_type		=>  'device',
		output_object	=>  'multi',
		pre_output		=>	sub{ my $track = shift; $track->pre_multi},
		condition 		=> sub { my $track = shift; 
								return "satisfied" if $track->ch_m; } ,
		status			=>  0,
	);

=comment
# Live: apply effects to REC channels route to multichannel sound card
# as above. 
#
=cut

}

sub initialize_project_data {
	$debug2 and print "&initialize_project_data\n";

	return if transport_running();
	$ui->destroy_widgets();
	$ui->project_label_configure(
		-text => uc $project_name, 
		-background => 'lightyellow',
		); 

	# assign_var($project_init_file, @project_vars);

	%cops        = ();   
	$cop_id           = "A"; # autoincrement
	%copp           = ();    # chain operator parameters, dynamic
	                        # indexed by {$id}->[$param_no]
							# and others
	%old_vol = ();

	@input_chains = ();
	@output_chains = ();

	%widget_c = ();
	@widget_t = ();
	%widget_e = ();
	

	# time related
	
	$markers_armed = 0;
	%marks = ();
	
	# volume settings
	
	%old_vol = ();

	# $is_armed = 0;
	
	$::Group::n = 0; 
	@::Group::by_index = ();
	%::Group::by_name = ();

	$::Track::n = 0; 	# incrementing numeric key
	@::Track::by_index = ();	# return ref to Track by numeric key
	%::Track::by_name = ();	# return ref to Track by name
	%::Track::track_names = (); 

	$master = ::Group->new(name => 'Master');
	$mixdown =  ::Group->new(name => 'Mixdown');
	$tracker = ::Group->new(name => 'Tracker', rw => 'REC');

	#print yaml_out( \%::Track::track_names );


# create magic tracks, we will create their GUI later, after retrieve

	$master_track = ::SimpleTrack->new( 
		group => 'Master', 
		name => 'Master',
		rw => 'MON',); # no dir, we won't record tracks


	$mixdown_track = ::Track->new( 
		group => 'Mixdown', 
		name => 'Mixdown', 
		rw => 'MON'); 

}
## track and wav file handling

sub add_track {

	@_ = discard_object(@_);
	$debug2 and print "&add_track\n";
	return if transport_running();
	my $name = shift;
	#print "name: $name, ch_r: $ch_r, ch_m: $ch_m\n";
	my $track = ::Track->new(
		name => $name,
		ch_r => $ch_r,
		ch_m => $ch_m,
	);
	return if ! $track; 
	print "ref new track: ", ref $track; 

	# $ch_r and $ch_m are public variables set by GUI
	# Okay, so we will do that for the grammar, too
	# $::chr = 
	
	my $group = $::Group::by_name{$track->group};
	$group->set(rw => 'REC');
	$track_name = $ch_m = $ch_r = undef;

	$ui->track_gui($track->n);
	$debug and print "Added new track!\n", $track->dump;
}

sub dig_ruins { 
	

	# only if there are no tracks , 
	
	$debug2 and print "&dig_ruins";
	return if $tracker->tracks;

	# look for wave files
		
		my $d = this_wav_dir();
		opendir WAV, $d or carp "couldn't open $d: $!";

		# remove version numbers
		
		my @wavs = grep{s/(_\d+)?\.wav//i} readdir WAV;

		my %wavs;
		
		map{ $wavs{$_}++ } @wavs;
		@wavs = keys %wavs;

		$debug and print "tracks found: @wavs\n";
	 
		create_master_and_mix_tracks();

		map{add_track($_)}@wavs;

#	}
}

sub remove_small_wavs {

	# 44 byte stubs left by a recording chainsetup that is 
	# connected by not started

	local $debug = 1;
	$debug2 and print "&remove_small_wavs\n";
	
         my @wavs = File::Find::Rule ->name( '*.wav' )
                                        ->file()
                                        ->size(44)
                                        ->extras( { follow => 1} )
                                     ->in( this_wav_dir() );
    $debug and print join $/, @wavs;

	map { unlink $_ } @wavs; 
}

sub add_volume_control {
	my $n = shift;
	
	my $vol_id = cop_add({
				chain => $n, 
				type => 'ea',
				cop_id => $ti[$n]->vol, # often undefined
				});
	
	$ti[$n]->set(vol => $vol_id);  # save the id for next time
	$vol_id;
}
sub add_pan_control {
	my $n = shift;
	
	my $pan_id = cop_add({
				chain => $n, 
				type => 'epp',
				cop_id => $ti[$n]->pan, # often undefined
				});
	
	$ti[$n]->set(pan => $pan_id);  # save the id for next time
	$pan_id;
}
## version functions

=comment
sub set_active_version {
	my $n = shift;
	$debug and print "chain $n: versions: @{$ti[$n]->versions}\n";    
		$ti[$n]->active = $ti[$n]->versions->[-1]  # XXX
			if $ti[$n]->versions;    
		$debug and print "active version, chain $n: $ti[$n]->active\n\n";
}
=cut

sub mon_vert {
	my $ver = shift;
	$tracker->set(version => $ver);
	$ui->refresh();
}
## chain setup generation


=comment


			# TODO no channel copy for stereo input files
            # such as version 1 backing.wav

			# n.b. no signal multiplier needed with current Ecasound
			
=cut


=comment    

%inputs
  |----->device-->$devname-->[ chain_id, chain_id,... ]
  |----->file---->$filename->[ chain_id, chain_id,... ]
  |----->bus1---->loop_id--->[ chain_id, chain_id,... ]
  |----->cooked-->loop_id--->[ chain_id, chain_id,... ]
  |_____>mixed___>loop_id___>[ chain_id, chain_id,... ]

%outputs
  |----->device-->$devname-->[ chain_id, chain_id,... ]
  |----->file---->$key**---->[ chain_id, chain_id,... ]
  |----->bus1---->loop_id--->[ chain_id, chain_id,... ]
  |----->cooked-->loop_id--->[ chain_id, chain_id,... ]
  |_____>mixed___>loop_id___>[ chain_id, chain_id,... ]

  ** consists of full path to the file ($filename) followed
  by a space, followed the output format specification.

=cut

sub all_chains {
	my @active_tracks = grep { $_->rec_status ne q(MUTE) } ::Track::all() 
		if ::Track::all();
	map{ $_->n} @active_tracks if @active_tracks;
}

sub user_rec_tracks {
	my @user_tracks = ::Track::all();
	splice @user_tracks, 0, 2; # drop Master and Mixdown tracks
	return unless @user_tracks;
	my @user_rec_tracks = grep { $_->rec_status eq 'REC' } @user_tracks;
	return unless @user_rec_tracks;
	map{ $_->n } @user_rec_tracks;
}
sub user_mon_tracks {
	my @user_tracks = ::Track::all();
	splice @user_tracks, 0, 2; # drop Master and Mixdown tracks
	return unless @user_tracks;
	my @user_mon_tracks = grep { $_->rec_status eq 'MON' } @user_tracks;
	return unless @user_mon_tracks;
	map{ $_->n } @user_mon_tracks;

}

sub really_recording {  # returns filename stubs

#	scalar @record  
	#print join "\n", "", ,"file recorded:", keys %{$outputs{file}}; # includes mixdown
	keys %{$outputs{file}}; # includes mixdown
}

sub write_chains {
	$debug2 and print "&write_chains\n";

	# $bus->apply;
	# $mixer->apply;
	# $ui->write_chains

	# we can assume that %inputs and %outputs will have the
	# same lowest-level keys
	#
	my @buses = grep { $_ ne 'file' and $_ ne 'device' } keys %inputs;
	
	### Setting devices as inputs (used by i.e. rec_setup)
	
	for my $dev (keys %{ $inputs{device} } ){

		$debug and print "dev: $dev\n";
		push  @input_chains, 
		join " ", "-a:" . (join ",", @{ $inputs{device}->{$dev} }),
			"-f:" .  $devices{$dev}->{input_format},
			"-i:" .  $devices{$dev}->{ecasound_id}, 
	}
	#####  Setting devices as outputs
	#
	for my $dev ( keys %{ $outputs{device} }){
			push @output_chains, join " ",
				"-a:" . (join "," , @{ $outputs{device}->{$dev} }),
				"-f:" . $devices{$dev}->{output_format},
				"-o:". $devices{$dev}->{ecasound_id};
	}
	### Setting loops as inputs 

	for my $bus( @buses ){ # i.e. 'mixed', 'cooked'
		for my $loop ( keys %{ $inputs{$bus} }){
			push  @input_chains, 
			join " ", 
				"-a:" . (join ",", @{ $inputs{$bus}->{$loop} }),
				"-i:$loop";
		}
	}
	### Setting loops as outputs 

	for my $bus( @buses ){ # i.e. 'mixed', 'cooked'
		for my $loop ( keys %{ $outputs{$bus} }){
			push  @output_chains, 
			join " ", 
				"-a:" . (join ",", @{ $outputs{$bus}->{$loop} }),
				"-o:$loop";
		}
	}
	##### Setting files as inputs (used by mon_setup)

	for my $full_path (keys %{ $inputs{file} } ) {
		$debug and print "monitor input file: $full_path\n";
		my $chain_ids = join ",",@{ $inputs{file}->{$full_path} };
		push @input_chains, join ( " ",
					"-a:".$chain_ids,
			 		"-i:".$full_path,

	   );
 	}
	##### Setting files as outputs (used by rec_file and mix)

	for my $key ( keys %{ $outputs{file} } ){
		my ($full_path, $format) = split " ", $key;
		$debug and print "record output file: $full_path\n";
		my $chain_ids = join ",",@{ $outputs{file}->{$key} };
		
		push @output_chains, join ( " ",
			 "-a:".$chain_ids,
			 "-f:".$format,
			 "-o:".$full_path,
		 );
			 
			 
	}

	## write general options
	
	my $ecs_file = "# ecasound chainsetup file\n\n";
	$ecs_file   .= "# general\n\n";
	$ecs_file   .= "$ecasound_globals\n\n";
	$ecs_file   .= "# audio inputs\n\n";
	$ecs_file   .= join "\n", sort @input_chains;
	$ecs_file   .= "\n\n# post-input processing\n\n";
	$ecs_file   .= join "\n", sort map{ "-a:$_ $post_input{$_}"} keys %post_input;
	$ecs_file   .= "\n\n# pre-output processing\n\n";
	$ecs_file   .= join "\n", sort map{ "-a:$_ $pre_output{$_}"} keys %pre_output;
	$ecs_file   .= "\n\n# audio outputs";
	$ecs_file   .= join "\n", sort @output_chains, "\n";
	
	$debug and print "ECS:\n",$ecs_file;
	my $sf = join_path(&project_dir, $chain_setup_file);
	open ECS, ">$sf" or croak "can't open file $sf:  $!\n";
	print ECS $ecs_file;
	close ECS;
}
## templates for generating chains

sub convert_to_jack {
	map{ $_->{input} = q(jack)} grep{ $_->{name} =~ /rec_/ } @oids;	
	map{ $_->{output} = q(jack)} grep{ $_->{name} =~ /live|multi|stereo/ } @oids;	
}
sub convert_to_alsa { initialize_oids }

## transport functions

sub load_ecs {
		local $debug = 1;
		my $project_file = join_path(&project_dir , $chain_setup_file);
		eval_iam("cs-disconnect");
		eval_iam("cs-remove $project_file");
		eval_iam("cs-load ". $project_file);
		$debug and map{print "$_\n\n"}map{$e->eci($_)} qw(cs es fs st ctrl-status);
}
sub new_engine { 
	my $ecasound  = $ENV{ECASOUND} ? $ENV{ECASOUND} : q(ecasound);
	#print "ecasound name: $ecasound\n";
	system qq(killall $ecasound);
	sleep 1;
	system qq(killall -9 $ecasound);
	$e = Audio::Ecasound->new();
}
sub setup_transport { # create chain setup
	remove_small_wavs();
	$debug2 and print "&setup_transport\n";
	%inputs = %outputs 
			= %post_input 
			= %pre_output 
			= @input_chains 
			= @output_chains 
			= ();
	my @tracks = ::Track::all;
	shift @tracks; # drop Master

	
	my $have_source = join " ", map{$_->name} 
								grep{ $_ -> rec_status ne 'MUTE'} 
								@tracks;
	# BUG: doesn't detect case of trying to mixdown with no
	# playback tracks
	#print "have source: $have_source\n";
	if ($have_source) {
		$mixdown_bus->apply; # mix_file
		$master_bus->apply; # mix_out, mix_link

		## we want to apply 'multi' only to tracks with
		### with mon_ch defined, and $multi_enable on
		
		$tracker_bus->apply;
		#map{ eliminate_loops($_) } all_chains();
		#print "minus loops\n \%inputs\n================\n", yaml_out(\%inputs);
		#print "\%outputs\n================\n", yaml_out(\%outputs);
		write_chains();
		return 1;
	} else { print "Mixdown not possible, no inputs\n";
	return 0};
}

sub connect_transport {
	load_ecs(); 
	carp("Invalid chain setup, cannot arm transport.\n"),return unless eval_iam("cs-is-valid");
	find_op_offsets(); 
	apply_ops();
	eval_iam('cs-connect');
	carp("Invalid chain setup, cannot arm transport.\n"), return 
		unless eval_iam("engine-status") eq 'not started' ;
	eval_iam('engine-launch');
	carp("Invalid chain setup, cannot arm transport.\n"), return
		unless eval_iam("engine-status") eq 'stopped' ;
	$length = eval_iam('cs-get-length'); 
	$ui->length_display(-text => colonize($length));
	# eval_iam("cs-set-length $length") unless @record;
	$ui->clock_config(-text => colonize(0));
	#print eval_iam("fs");
	$ui->flash_ready();
	
}
sub start_transport { 
	$debug2 and print "&start_transport\n";
	carp("Invalid chain setup, aborting start.\n"),return unless eval_iam("cs-is-valid");
	eval_iam('start');
	sleep 1; # time for engine
	start_clock();
}
sub stop_transport { 
	$debug2 and print "&stop_transport\n"; 
	eval_iam('stop');	
	$ui->project_label_configure(-background => $old_bg);
# 	$clock_id->cancel; # if (ref $clock_id =~ /Tk::after/); 
# 	sleep 1;
# 	$clock_id->cancel; # if (ref $clock_id =~ /Tk::after/); 
# 	sleep 1;
# 	$clock_id->cancel; # if (ref $clock_id =~ /Tk::after/); 
	# what if we are recording
}
sub transport_running {
#	$debug2 and print "&transport_running\n";
	 eval_iam('engine-status') eq 'running' ;
}
sub disconnect_transport {
	return if transport_running();
	eval_iam('cs-disconnect') }


sub toggle_unit {
	if ($unit == 1){
		$unit = 60;
		
	} else{ $unit = 1; }
}
sub show_unit { $time_step->configure(
	-text => ($unit == 1 ? 'Sec' : 'Min') 
)}
sub drop_mark {
		my $pos = shift; # for restore, otherwise
		$pos = $pos ? $pos : eval_iam("cs-get-position");
		return if $marks{$pos}; 
		$marks{$pos}++; # sufficient  for text mode
		$ui->marker($pos); # for GUI
}
sub mark {
	my $pos = shift; 
	my $here = eval_iam("cs-get-position");
	if ($markers_armed and abs( $pos - $here) < 0.005){
			$ui->destroy_marker($pos);
			delete $marks{$pos};
		    arm_mark_toggle(); # disarm
	}
	else{ 

		eval_iam(qq(cs-set-position $pos));
	}
}
## clock and clock-refresh functions ##
#

sub update_clock { 
	$ui->clock_config(-text => colonize(eval_iam('cs-get-position')));
}
sub start_clock {
	#eval qq($clock_id->cancel);
	$clock_id = $clock->after(1000, \&refresh_clock);
}
sub restart_clock {
	start_clock();
}
sub refresh_clock{
	
	update_clock();
	$clock_id = $clock->after(1000, \&refresh_clock) if transport_running();
	my $status = eval_iam('engine-status');
	$debug 
	   and print colonize(eval_iam('getpos')),  "  engine status: $status\n";
	
	new_engine() if $status eq 'error';
	if (! &transport_running){
		&really_recording and rec_cleanup() or connect_transport();
	}
}

## jump recording head position

sub to_start { 
	return if really_recording();
	eval_iam(qq(cs-set-position 0));
	restart_clock();
}
sub to_end { 
	# ten seconds shy of end
	return if really_recording();
	my $end = eval_iam(qq(cs-get-length)) - 10 ;  
	eval_iam(qq(cs-set-position $end));
	restart_clock();
} 
sub jump {
	return if really_recording();
	my $delta = shift;
#	my $running = eval_iam("engine-status") eq 'running' ?  1 : 0;
#	eval_iam "stop"; #  if $running;
	$debug2 and print "&jump\n";
	my $here = eval_iam(qq(getpos));
	$debug and print "delta: $delta\nhere: $here\nunit: $unit\n\n";
	my $new_pos = $here + $delta * $unit;
	$new_pos = $new_pos < $length ? $new_pos : $length - 10;
	# eval_iam("setpos $new_pos");
	my $cmd = "setpos $new_pos";
	$e->eci("setpos $new_pos");
	# print "$cmd\n";
	# eval_iam "start" if $running;
	sleep 1;
 # restart_clock();
}
## post-recording functions

sub rec_cleanup {  
	$debug2 and print "&rec_cleanup\n";
	$debug and print "I was recording!\n";
 	my @k = really_recording();
	disconnect_transport();
	my $recorded = 0;
 	for my $k (@k) {    
 		my ($n) = $outputs{file}{$k}[-1] =~ m/(\d+)/; 
 		my $test_wav = $ti[$n]->full_path;
		$debug and print "track: $n, file: $test_wav\n";
 		my ($v) = ($test_wav =~ /_(\d+)\.wav$/); 
		$debug and print "n: $n\nv: $v\n";
		$debug and print "testing for $test_wav\n";
		if (-e $test_wav) {
			if (-s $test_wav > 44100) { # 0.5s x 16 bits x 44100/s
				$ti[$n]->set(active => $ti[$n]->last); 
				update_version_button($n, $v);
			$recorded++;
			}
			else { unlink $test_wav }
		}
	}
	my $mixed = scalar ( grep{ /\bmix*.wav/} @k );
	
	$debug and print "recorded: $recorded mixed: $mixed\n";
	if ( ($recorded -  $mixed) >= 1) {
			# i.e. there are first time recorded tracks
			$ui->update_master_version_button();
			$tracker->set( rw => 'MON');
			setup_transport() and connect_transport();
			$ui->refresh();
	}
		
} 
## effect functions
sub add_effect {
	local $debug = 1;
	
	$debug2 and print "&add_effect\n";
	
	my %p 			= %{shift()};
	my $n 			= $p{chain};
	my $code 			= $p{type};
	my $parent_id = $p{parent_id};  
	my $id		= $p{cop_id};   # initiates restore
	my $parameter		= $p{parameter}; 
	my $i = $effect_i{$code};
	my $values = $p{values};

	return if $id eq $ti[$n]->vol or
	          $id eq $ti[$n]->pan;   # skip these effects 
			   								# already created in add_track

	$id = cop_add(\%p); 
	my %pp = ( %p, cop_id => $id); # replace chainop id
	$ui->add_effect_gui(\%pp);
	apply_op($id) if eval_iam("cs-is-valid");

}

sub remove_effect {
	@_ = discard_object(@_);
	$debug2 and print "&remove_effect\n";
	my $id = shift;
	my $n = $cops{$id}->{chain};
		
	$debug and print "ready to remove cop_id: $id\n";

	# if i belong to someone remove their ownership of me

	if ( my $parent = $cops{$id}->{belongs_to} ) {
	$debug and print "parent $parent owns list: ", join " ",
		@{ $cops{$parent}->{owns} }, "\n";

		@{ $cops{$parent}->{owns} }  =  grep{ $_ ne $id}
		@{ $cops{$parent}->{owns} } ; 
	$debug and print "parent $parent new owns list: ", join " ",
	}

	# recursively remove children
	$debug and print "children found: ", join "|",@{$cops{$id}->{owns}},"\n";
		
	# parameter controllers are not separate ops
	map{remove_effect($_)}@{ $cops{$id}->{owns} };

	
	# remove my own cop_id from the stack
	$ui->remove_effect_gui($id), remove_op($id)  unless $cops{$id}->{belongs_to};

}
sub remove_effect_gui { 
	@_ = discard_object(@_);
	$debug2 and print "&remove_effect_gui\n";
	my $id = shift;
	my $n = $cops{$id}->{chain};
	$debug and print "id: $id, chain: $n\n";

	$ti[$n]->set(ops =>  
		[ grep{ $_ ne $id} @{ $ti[ $cops{$id}->{chain} ]->ops } ]);
	$debug and print "i have widgets for these ids: ", join " ",keys %widget_e, "\n";
	$debug and print "preparing to destroy: $id\n";
	$widget_e{$id}->destroy();
	delete $widget_e{$id}; 

}

sub remove_op {

	my $id = shift;
	my $n = $cops{$id}->{chain};
	if ( $cops{$id}->{belongs_to}) { 
		return;
	}
	my $index; 
	$debug and print "ops list for chain $n: @{$ti[$n]->ops}\n";
	$debug and print "operator id to remove: $id\n";
		for my $pos ( 0.. scalar @{ $ti[$n]->ops } - 1  ) {
			($index = $pos), last if $ti[$n]->ops->[$pos] eq $id; 
		};
	$debug and print "ready to remove from chain $n, operator id $id, index $index\n";
	$debug and eval_iam ("cs");
	 eval_iam ("c-select $n");
	eval_iam ("cop-select ". ($ti[$n]->offset + $index));
	eval_iam ("cop-remove");
	$debug and eval_iam ("cs");

	delete $cops{$id};
	delete $copp{$id};
}
sub cop_add {
	my %p 			= %{shift()};
	my $n 			= $p{chain};
	my $code		= $p{type};
	my $parent_id = $p{parent_id};  
	my $id		= $p{cop_id};   # causes restore behavior when present
	my $i       = $effect_i{$code};
	my @values = @{ $p{values} } if $p{values};
	my $parameter	= $p{parameter};  # needed for parameter controllers
	$debug2 and print "&cop_add\n";
$debug and print <<PP;
n:          $n
code:       $code
parent_id:  $parent_id
cop_id:     $id
effect_i:   $i
parameter:  $parameter
PP

	return $id if $id; # do nothing if cop_id has been issued

	# make entry in %cops with chain, code, display-type, children

	$debug and print "Issuing a new cop_id for track $n: $cop_id\n";
	# from the cop_id, we may also need to know chain number and effect

	$cops{$cop_id} = {chain => $n, 
					  type => $code,
					  display => $effects[$i]->{display},
					  owns => [] }; # DEBUGGIN TEST

	$p{cop_id} = $cop_id;
 	cop_init ( \%p );

	if ($parent_id) {
		$debug and print "parent found: $parent_id\n";

		# store relationship
		$debug and print "parent owns" , join " ",@{ $cops{$parent_id}->{owns}}, "\n";

		push @{ $cops{$parent_id}->{owns}}, $cop_id;
		$debug and print join " ", "my attributes:", (keys %{ $cops{$cop_id} }), "\n";
		$cops{$cop_id}->{belongs_to} = $parent_id;
		$debug and print join " ", "my attributes again:", (keys %{ $cops{$cop_id} }), "\n";
		$debug and print "parameter: $parameter\n";
		$copp{$cop_id}->[0] = $parameter + 1; # set fx-param to the parameter number.
 		# find position of parent and insert child immediately afterwards

 		my $end = scalar @{ $ti[$n]->ops } - 1 ; 
 		for my $i (0..$end){
 			splice ( @{$ti[$n]->ops}, $i+1, 0, $cop_id ), last
 				if $ti[$n]->ops->[$i] eq $parent_id 
 		}
	}
	else { push @{$ti[$n]->ops }, $cop_id; } 

	# set values if present
	
	$copp{$cop_id} = \@values if @values; # needed for text mode

	$cop_id++; # return value then increment
}

sub cop_init {
	
	$debug2 and print "&cop_init\n";
	my $p = shift;
	my %p = %$p;
	my $id = $p{cop_id};
	my $parent_id = $p{parent_id};
	my $vals_ref  = $p{vals_ref};
	
	$debug and print "cop__id: $id\n";

	my @vals;
	if (ref $vals_ref) {
	# untested
		@vals = @{ $vals_ref };
		$debug and print ("values supplied\n");
		@{ $copp{$id} } = @vals;
		return;
	} 
	else { 
		$debug and print "no settings found, loading defaults if present\n";
		my $i = $effect_i{ $cops{$id}->{type} };
		
		# CONTROLLER
		# don't initialize first parameter if operator has a parent
		# i.e. if operator is a controller
		for my $p ($parent_id ? 1 : 0..$effects[$i]->{count} - 1) {
		# XXX support controller-type operators
		
		# for my $p (0..$effects[$i]->{count} - 1) {
			my $default = $effects[$i]->{params}->[$p]->{default};
			push @vals, $default;
		}
		@{ $copp{$id} } = @vals;
		$debug and print "copid: $id defaults: @vals \n";
	}
}
sub effect_update {
	
	# why not use this routine to update %copp values as
	# well?
	
	local $debug = 1;
	my $es = eval_iam "engine-status";
	return if $es !~ /not started|stopped|running/;
	my ($chain, $id, $param, $val) = @_;
	$debug2 and print "&effect_update\n";
	return if $ti[$chain]->rec_status eq "MUTE"; 
	return if $ti[$chain]->name eq 'Mixdown' and 
			  $ti[$chain]->rec_status eq 'REC';
 	$debug and print join " ", @_, "\n";	

	# update Ecasound's copy of the parameter

	$debug and print "valid: ", eval_iam("cs-is-valid"), "\n";
	my $controller; 
	for my $op (0..scalar @{ $ti[$chain]->ops } - 1) {
		$ti[$chain]->ops->[$op] eq $id and $controller = $op;
	}
	$param++; # so the value at $p[0] is applied to parameter 1
	$controller++; # translates 0th to chain-operator 1
	$debug and print 
	"cop_id $id:  track: $chain, controller: $controller, offset: ",
	$ti[$chain]->offset, " param: $param, value: $val$/";
	eval_iam ("c-select $chain");
	eval_iam ("cop-select ". ($ti[$chain]->offset + $controller));
	eval_iam ("copp-select $param");
	eval_iam ("copp-set $val");
}
sub find_op_offsets {

=comment
	Op offsets are needed to calculate the index to an effect (chain operator).
	If reverb is added and it is the first user-added effect, the offset will
	typically include an operator for routing (which will appear in the chain
	setup file) plus operators for volume and pan, which are provided for each
	track.

	find_op_offsets reads the output of the cs command to determine
	the number of chain operators from the setup file, then adds 
	two for the volume and pan operators, to give the index offset
	for the first user effect.

	Here is the relevant line from the 'cs' command output:

		Chain "1" [selected] "Channel copy"
			
	we will count the quotes, divide by two, and subtract one (for the chain id)
	to get offset. Then we add two for volume and pan. Finally, we will
	add 1, since perl arrays (used to represent chain operators) are indexed
	starting at 0, whereas ecasound indexes operators starting at 1.

	In this example, the first user effect will have an index of 4, which
	will also be the offset needed for our start-at-zero array. 
=cut


	
	$debug2 and print "&find_op_offsets\n";
	eval_iam('c-select-all');
		#my @op_offsets = split "\n",eval_iam("cs");
		my @op_offsets = grep{ /"\d+"/} split "\n",eval_iam("cs");
		shift @op_offsets; # remove comment line
		$debug and print join "\n\n",@op_offsets; 
		for my $output (@op_offsets){
			my $chain_id;
			($chain_id) = $output =~ m/Chain "(\w*\d+)"/;
			# print "chain_id: $chain_id\n";
			next if $chain_id =~ m/\D/; # skip id's containing non-digits
										# i.e. M1
			my $quotes = $output =~ tr/"//;
			$debug and print "offset: $quotes in $output\n"; 
			$ti[$chain_id]->set( offset => $quotes/2 - 1);   # XXX

		}
}
sub apply_ops {  # in addition to operators in .ecs file
	
	local $debug = 1;
	$debug2 and print "&apply_ops\n";
	my $last = scalar @::Track::by_index - 1;
	print "looping over 1 to $last\n";
	for my $n (1..$last) {
	$debug and print "chain: $n, offset: ", $ti[$n]->offset, "\n";
 		next if $ti[$n]->rec_status eq "MUTE" ;
		#next if $n == 2; # no volume control for mix track
		#next if ! defined $ti[$n]->offset; # for MIX
 		#next if ! $ti[$n]->offset ;
		for my $id ( @{ $ti[$n]->ops } ) {
		#	next if $cops{$id}->{belongs_to}; 
		apply_op($id);
		}
	}
}
sub apply_op {
	$debug2 and print "&apply_op\n";
	local $debug = 1;
	
	my $id = shift;
	$debug and print "id: $id\n";
	my $code = $cops{$id}->{type};
	$debug and print "chain: $cops{$id}->{chain} type: $cops{$id}->{type}, code: $code\n";
	#  if code contains colon, then follow with comma (preset, LADSPA)
	#  if code contains no colon, then follow with colon (ecasound,  ctrl)
	
	$code = '-' . $code . ($code =~ /:/ ? q(,) : q(:) );
	my @vals = @{ $copp{$id} };
	$debug and print "values: @vals\n";

	# we start to build iam command

	
	my $add = "cop-add "; 
	$add .= $code . join ",", @vals;

	# if my parent has a parent then we need to append the -kx  operator

	my $dad = $cops{$id}->{belongs_to};
	$add .= " -kx" if $cops{$dad}->{belongs_to};
	$debug and print "operator:  ", $add, "\n";

	eval_iam ("c-select $cops{$id}->{chain}") 
		unless $cops{$id}->{belongs_to}; # avoid reset
	eval_iam ($add);
	$debug and print "children found: ", join ",", "|",@{$cops{$id}->{owns}},"|\n";
	map{apply_op($_)} @{ $cops{$id}->{owns} };

}
## static effects data



# @ladspa_sorted # XXX

sub prepare_static_effects_data{
	
	$debug2 and print "&prepare_static_effects_data\n";

	my $effects_cache = join_path(&wav_dir, $effects_cache_file);

	# TODO re-read effects data if ladspa or user presets are
	# newer than cache

	if (-f $effects_cache and ! $opts{s}){  
		$debug and print "found effects cache: $effects_cache\n";
		assign_var($effects_cache, @effects_static_vars);
	} else {
		
		$debug and print "reading in effects data, please wait...\n";
		read_in_effects_data(); 
		get_ladspa_hints();
		integrate_ladspa_hints();
		sort_ladspa_effects();
		serialize (
			-file => $effects_cache, 
			-vars => \@effects_static_vars,
			-class => '::',
			-storable => 1 ); #  unless $wav_dir eq '.';
	}

}
sub extract_effects_data {
	my ($lower, $upper, $regex, $separator, @lines) = @_;
	carp ("incorrect number of lines ", join ' ',$upper-$lower,scalar @lines)
		if $lower + @lines - 1 != $upper;
	$debug and print"lower: $lower upper: $upper  separator: $separator\n";
	#$debug and print "lines: ". join "\n",@lines, "\n";
	$debug and print "regex: $regex\n";
	
	for (my $j = $lower; $j <= $upper; $j++) {
		my $line = shift @lines;
	
		$line =~ /$regex/ or carp("bad effect data line: $line\n"),next;
		my ($no, $name, $id, $rest) = ($1, $2, $3, $4);
		$debug and print "Number: $no Name: $name Code: $id Rest: $rest\n";
		my @p_names = split $separator,$rest; 
		map{s/'//g}@p_names; # remove leading and trailing q(') in ladspa strings
		$debug and print "Parameter names: @p_names\n";
		$effects[$j]={};
		$effects[$j]->{number} = $no;
		$effects[$j]->{code} = $id;
		$effects[$j]->{name} = $name;
		$effects[$j]->{count} = scalar @p_names;
		$effects[$j]->{params} = [];
		$effects[$j]->{display} = qq(field);
		map{ push @{$effects[$j]->{params}}, {name => $_} } @p_names;
	}
}
sub sort_ladspa_effects {
	$debug2 and print "&sort_ladspa_effects\n";
#	print yaml_out(\%e_bound); 
	my $aa = $e_bound{ladspa}{a};
	my $zz = $e_bound{ladspa}{z};
#	print "start: $aa end $zz\n";
	map{push @ladspa_sorted, 0} ( 1 .. $aa ); # fills array slice [0..$aa-1]
	splice @ladspa_sorted, $aa, 0,
		 sort { $effects[$a]->{name} cmp $effects[$b]->{name} } ($aa .. $zz) ;
	$debug and print "sorted array length: ". scalar @ladspa_sorted, "\n";
}		
sub read_in_effects_data {

	local $debug = 0;
	$debug2 and print "&read_in_effects_data\n";
	read_in_tkeca_effects_data();

	# read in other effects data
	
	my $lr = eval_iam("ladspa-register");

	#print $lr; 
	
	my @ladspa =  split "\n", $lr;

	
	#$lr > io("lr");
	#split /\n+/, 
	
	# grep {! /^\w*$/ } 
	
	# join the two lines of each entry
	my @lad = map { join " ", splice(@ladspa,0,2) } 1..@ladspa/2; 

	my @preset = grep {! /^\w*$/ } split "\n", eval_iam("preset-register");
	my @ctrl  = grep {! /^\w*$/ } split "\n", eval_iam("ctrl-register");


#	print eval_iam("ladspa-register");
	
	$debug and print "found ", scalar @lad, " LADSPA effects\n";
	$debug and print "found ", scalar @preset, " presets\n";
	$debug and print "found ", scalar @ctrl, " controllers\n";

	# index boundaries we need to make effects list and menus

	$e_bound{ladspa}{a} = $e_bound{tkeca}{z} + 1;
	$e_bound{ladspa}{b} = $e_bound{tkeca}{z} + int(@lad/4);
	$e_bound{ladspa}{c} = $e_bound{tkeca}{z} + 2*int(@lad/4);
	$e_bound{ladspa}{d} = $e_bound{tkeca}{z} + 3*int(@lad/4);
	$e_bound{ladspa}{z} = $e_bound{tkeca}{z} + @lad;
	$e_bound{preset}{a} = $e_bound{ladspa}{z} + 1;
	$e_bound{preset}{b} = $e_bound{ladspa}{z} + int(@preset/2);
	$e_bound{preset}{z} = $e_bound{ladspa}{z} + @preset;
	$e_bound{ctrl}{a}   = $e_bound{preset}{z} + 1;
	$e_bound{ctrl}{z}   = $e_bound{preset}{z} + @ctrl;

	my $preset_re = qr/
		^(\d+) # number
		\.    # dot
		\s+   # spaces+
		(\w+) # name
		,\s*  # comma spaces* 
		-(pn:\w+)    # preset_id 
		:?     # maybe colon (if parameters)
		(.*$)  # rest
	/x;

	my $ladspa_re = qr/
		^(\d+) # number
		\.    # dot
		\s+  # spaces
		(\w.+?) # name, starting with word-char,  non-greedy
		\s+     # spaces
		-(el:\w+),? # ladspa_id maybe followed by comma
		(.*$)        # rest
	/x;

	my $ctrl_re = qr/
		^(\d+) # number
		\.     # dot
		\s+    # spaces
		(\w.+?) # name, starting with word-char,  non-greedy
		,\s*    # comma, zero or more spaces
		-(k\w+):?    # ktrl_id maybe followed by colon
		(.*$)        # rest
	/x;

	extract_effects_data(
		$e_bound{ladspa}{a},
		$e_bound{ladspa}{z},
		$ladspa_re,
		q(','),
		@lad,
	);

	extract_effects_data(
		$e_bound{preset}{a},
		$e_bound{preset}{z},
		$preset_re,
		q(,),
		@preset,
	);
	extract_effects_data(
		$e_bound{ctrl}{a},
		$e_bound{ctrl}{z},
		$ctrl_re,
		q(,),
		@ctrl,
	);



	for my $i (0..$#effects){
		 $effect_i{ $effects[$i]->{code} } = $i; 
		 $debug and print "i: $i code: $effects[$i]->{code} display: $effects[$i]->{display}\n";
	}

	$debug and print "\@effects\n======\n", yaml_out(\@effects); ; 
}
sub read_in_tkeca_effects_data {

# Based on GPL code in Tkeca

# controller (effect) data format
# code|name|number_of_parameters| ( Label|scale_start|scale_end|default|resolution ) x number_of_parameters

# I left the tcl code 'as is' in the following pasted section, using regexes 
# so future updates from him can be pasted in without editing.

# divide by lines, remove stuff outside quotes, 
# then make an anonymous array of the fields of each line

	my @effects_data = 	map { [split /\|/, $_ ]  }  
						map{ s/^.*?"//; s/"\s*$//; $_} 
						split "\n",$tkeca_effects_data; 
	
	$e_bound{tkeca}{a}  = 1;
	$e_bound{tkeca}{z}  = scalar @effects_data;  

	for my $i (1..@effects_data){
		my @row = @{ shift @effects_data };
		@{$effects[$i]}{ qw(code name count) } = splice @row, 0, 3;

		# default display format

		$effects[$i]->{display} = qq(scale);

	# maps effect code (i.e. epp) to an index in array holding static effects data
	#print "effects code: $i stands for ", $effects[$i]->{code}, "\n";
	#print "count: $effects[$i]->{count}\n";

			for (1..$effects[$i]->{count}){
				my %p;
				#print join " / ",splice (@row, 0,5), "\n";
				@p{ qw(name begin end default resolution) }  =  splice @row, 0, 5;
				# print "\%p\n======\n", yaml_out(\%p);
				push @{$effects[$i]->{params}}, \%p;

			}
	}

}
sub get_ladspa_hints{
	$debug2 and print "&get_ladspa_hints\n";
	my @dirs =  split ':', $ENV{LADSPA_PATH};
	my $data = '';
	for my $dir (@dirs) {
		opendir DIR, $dir or carp qq(can't open LADSPA dir "$dir" for read: $!\n);
		my @plugins = grep{ /\.so$/ } readdir DIR;
		$data .= join "", map { `analyseplugin $_` } @plugins;
		closedir DIR;
	}
	# print $data; exit;
	my @plugin_stanzas = split "\n\n\n", $data;
	# print scalar @plugin_stanzas; exit;
	# print $data;

	# print "@plugins"; exit;
	# | perl -ne 'chomp; s/$ENV{LADSPA_PATH}//; system qq(analyseplugin $_)'
	my $ladspa_sample_rate = 44100; # for sample-rate dependent effect
	use Data::Dumper;

	my $pluginre = qr/
	Plugin\ Name: \s+ "([^"]+)" \s+
	Plugin\ Label:\s+ "([^"]+)" \s+
	[^\x00]+(?=Ports) 		# swallow maximum up to Ports
	Ports: \s+ ([^\x00]+) 	# swallow all
	/x;

	my $paramre = qr/
	"([^"]+)"   #  name inside quotes
	\s+
	(.+)        # rest
	/x;



	for my $stanza (@plugin_stanzas) {

		$stanza =~ /$pluginre/ or carp "*** couldn't match plugin stanza $stanza ***";

		my ($plugin_name, $plugin_label, $ports) = ($1, $2, $3);
		#print "$1\n$2\n$3"; exit;

		 my @lines = split "\n",$ports;
	#	print join "\n",@lines; exit;
		my @params;  # data

		my @names;
		for my $p (@lines) {
			next if $p =~ /^\s*$/;
			$p =~ /$paramre/;
			my ($name, $rest) = ($1, $2);
			my ($dir, $type, $range, $default, $hint) = split /\s*,\s*/ , $rest, 5;
			#print join "|",$dir, $type, $range, $default, $hint;
			next if $type eq q(audio);
			my %p;
			$p{name} = $name;
			$p{dir} = $dir;
			$p{hint} = $hint;
			my ($beg, $end, $default_val, $resolution) = range($name, $range, $default, $hint);
			$p{begin} = $beg;
			$p{end} = $end;
			$p{default} = $default_val;
			$p{resolution} = $resolution;
			push @params, { %p };
		}

		$plugin_label = "el:" . $plugin_label;
		$effects_ladspa {$plugin_label}->{params} = [ @params ];
		$effects_ladspa {$plugin_label}->{count} = scalar @params;
		$effects_ladspa {$plugin_label}->{display} = 'scale';
	}

	$debug and print yaml_out(\%effects_ladspa); 
}
sub range {
	my ($name, $range, $default, $hint) = @_; 
	my $multiplier = 1;;
	$multiplier = $ladspa_sample_rate if $range =~ s/\*srate//g;
	my ($beg, $end) = split /\s+to\s+/, $range;
	# if end is '...' set to $default + 10dB or $default * 10
	$default =~ s/default\s+//;
	$end =~ /\.{3}/ and $end = (
		$default == 0 ? 10  # '0' is probably 0db, so 0+10db
					  : $default * 10
		);
#	print "1 beg: $beg  end: $end\n";
	$beg = $beg * $multiplier;
	$end = $end * $multiplier;
#	print "2 beg: $beg  end: $end\n";

	my $resolution = ($end - $beg) / 100;
	if    ($hint =~ /integer/ ) { $resolution = 1; }
	elsif ($hint =~ /logarithmic/ ) {
		$beg = 0.0001 * $multiplier if ! $beg;
		$beg = round ( log $beg );
		$end = round ( log $end );
		$resolution = ($end - $beg) / 100;
		$default = round (log $default);
	}
	
	$resolution = d2( $resolution + 0.002) if $resolution < 1  and $resolution > 0.01;
	$resolution = dn ( $resolution, 3 ) if $resolution < 0.01;
	$resolution = int ($resolution + 0.1) if $resolution > 1 ;
	
	#print "3 beg: $beg  end: $end\n";
	($beg, $end, $default, $resolution)

}
sub integrate_ladspa_hints {
	map{ 
		my $i = $effect_i{$_};
		# print ("$_ not found\n"), 
		next unless $i;
		$effects[$i]->{params} = $effects_ladspa{$_}->{params};
		$effects[$i]->{display} = $effects_ladspa{$_}->{display};
	} keys %effects_ladspa;

my %L;
my %M;

map { $L{$_}++ } keys %effects_ladspa;
map { $M{$_}++ } grep {/el:/} keys %effect_i;

for my $k (keys %L) {
	$M{$k} or $debug and print "$k not found in ecasound listing\n";
}
for my $k (keys %M) {
	$L{$k} or $debug and print "$k not found in ladspa listing\n";
}


$debug and print join "\n", sort keys %effects_ladspa;
$debug and print '-' x 60, "\n";
$debug and print join "\n", grep {/el:/} sort keys %effect_i;

#print yaml_out \@effects; exit;

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
	

=comment

 ls $LADSPA_PATH | perl -ne 'chomp; s/$ENV{LADSPA_PATH}//; system qq(analyseplugin $_)'

my $ds = q(
Plugin Name: "LS Filter"
Plugin Label: "lsFilter"
Plugin Unique ID: 1908
Maker: "Steve Harris <steve@plugin.org.uk>"
Copyright: "GPL"
Must Run Real-Time: No
Has activate() Function: Yes
Has deativate() Function: No
Has run_adding() Function: Yes
Environment: Normal or Hard Real-Time
Ports:  "Filter type (0=LP, 1=BP, 2=HP)" input, control, 0 to 2, default 0, integer
        "Cutoff frequency (Hz)" input, control, 0.002*srate to 0.5*srate, default 0.0316228*srate, logarithmic
        "Resonance" input, control, 0 to 1, default 0
        "Input" input, audio
        "Output" output, audio
);
=cut
## persistent state support

sub save_state {

	$debug2 and print "&save_state\n";
	my $file = shift;

	# remove nulls in %cops 
	delete $cops{''};

	map{ 
		my $found; 
		$found = "yes" if @{$cops{$_}->{owns}};
		$cops{$_}->{owns} = '~' unless $found;
	} keys %cops;

	# restore muted volume levels
	#
	my %muted;
	map{ $copp{ $ti[$_]->vol }->[0] = $old_vol{$_} ; 
		 $muted{$_}++;
	#	 $ui->paint_button($widget_c{$_}{mute}, q(brown) );
		} grep { $old_vol{$_} } all_chains();
	# TODO: old_vol should be incorporated into Track object
	# not separate variable

 # old vol level has been stored, thus is muted
	$file = $file ? $file : $state_store_file;
	$file = join_path(&project_dir, $file);
		$debug and 1;
	# print "filename base: $file\n";

    # sort marks
	
	my @marks = sort keys %marks;
	%marks = ();
	map{ $marks{$_}++ } @marks;
	
# prepare tracks for storage

@tracks_data = (); # zero based, iterate over these to restore

map { push @tracks_data, $_->hashref } ::Track::all();
# print "found ", scalar @tracks_data, "tracks\n";

@groups_data = ();
map { push @groups_data, $_->hashref } ::Group::all();

	serialize(
		-file => $file, 
		-vars => \@persistent_vars,
		-class => '::',
	#	-storable => 1,
		);


# store alsa settings

	my $result2 = system "alsactl -f $file.alsa store";
	$debug and print "alsactl store result: ", $result2 >>8, "\n";

	# now remute
	
	map{ $copp{ $ti[$_]->vol }->[0] = 0} 
	grep { $muted{$_}} 
	all_chains();

	# restore %cops
	map{ $cops{$_}->{owns} eq '~' and $cops{$_}->{owns} = [] } keys %cops; 

}
sub assign_var {
	my ($source, @vars) = @_;
	assign_vars(
				-source => $source,
				-vars   => \@vars,
				-class => '::');
}
sub retrieve_state {
	$debug2 and print "&retrieve_state\n";
	my $file = shift;
	$file = $file ? $file : $state_store_file;
	$file = join_path(project_dir(), $file);
	my $yamlfile = $file;
	$yamlfile .= ".yml" unless $yamlfile =~ /yml$/;
	$file = $yamlfile if -f $yamlfile;
	! -f $file and carp("file not found: $file\n"), return;
	$debug and print "using file: $file";

	assign_var( $file, @persistent_vars );

	##  print yaml_out \@groups_data; 
	# %cops: correct 'owns' null (from YAML) to empty array []
	
	map{ $cops{$_}->{owns} or $cops{$_}->{owns} = [] } keys %cops; 

	#  set group parameters

	map {my $g = $_; 
		map{
			$::Group::by_index[$g->{n}]->set($_ => $g->{$_})
			} keys %{$g};
	} @groups_data;

	#  set Master and Mixdown parmeters
	
	map {my $t = $_; 
		map{
			$::Track::by_index[$t->{n}]->set($_ => $t->{$_})
			} keys %{$t};
	} @tracks_data[0,1];

	splice @tracks_data, 0, 2;

	#  now create the widgets
	
	create_master_and_mix_tracks();


	# create user tracks
	
	my $did_apply = 0;

	map{ 
		my %h = %$_; 
		#print "old n: $h{n}\n";
		#print "h: ", join " ", %h, $/;
		delete $h{n};
		#my @hh = %h; print "size: ", scalar @hh, $/;
		my $track = ::Track->new( %h ) ;
		my $n = $track->n;
		#print "new n: $n\n";
		$debug and print "restoring track: $n\n";
		$ui->track_gui($n); # applies vol and pan operators
		for my $id (@{$ti[$n]->ops}){
			$did_apply++ 
				unless $id eq $ti[$n]->vol
					or $id eq $ti[$n]->pan;
			
			add_effect({
						chain => $cops{$id}->{chain},
						type => $cops{$id}->{type},
						cop_id => $id,
						parent_id => $cops{$id}->{belongs_to},
						});

		# TODO if parent has a parent, i am a parameter controller controlling
		# a parameter controller, and therefore need the -kx switch
		}
	} @tracks_data;
	#print "\n---\n", $tracker->dump;  
	#print "\n---\n", map{$_->dump} ::Track::all;# exit; 
	$did_apply and $ui->manifest;
	$debug and print join " ", 
		(map{ ref $_, $/ } @::Track::by_index), $/;



	#my $toggle_jack = $widget_o[$#widget_o]; # JACK
	#convert_to_jack if $jack_on;
	#$ui->paint_button($toggle_jack, q(lightblue)) if $jack_on;
	$ui->refresh_oids();

	# restore mixer settings

	my $result = system "sudo alsactl -f $file.alsa restore";
	$debug and print "alsactl restore result: " , $result >> 8 , "\n";

	$ui->restore_time_marks();

} 
sub create_master_and_mix_tracks {


	my @rw_items = (
			[ 'command' => "MON",
				-command  => sub { 
						$tn{Master}->set(rw => "MON");
						refresh_c($master_track->n);
			}],
			[ 'command' => "MUTE", 
				-command  => sub { 
						$tn{Master}->set(rw => "MUTE");
						refresh_c($master_track->n);
			}],
		);
	$ui->track_gui( $master_track->n, @rw_items );

	$ui->track_gui( $mixdown_track->n); 

}


sub save_effects {
	$debug2 and print "&save_effects\n";
	my $file = shift;
	
	# restore muted volume levels
	#
	my %muted;
	
	map  {$copp{ $ti[$_]->vol }->[0] = $old_vol{$_} ;
		  $ui->paint_button($widget_c{$_}{mute}, $old_bg ) }
	grep { $old_vol{$_} }  # old vol level stored and muted
	all_chains();

	# we need the ops list for each track
	#
	# i dont see why, do we overwrite the effects section
	# in one of the init routines?
	# I will follow for now 12/6/07
	
	%state_c_ops = ();
	map{ 	$state_c_ops{$_} = $ti[$_]->ops } all_chains();

	# map {remove_op} @{ $ti[$_]->ops }

	store_vars(
		-file => $file, 
		-vars => \@effects_dynamic_vars,
		-class => '::');

}

=comment
sub r {
	retrieve_effects(shift);
}

sub r5 { r("eff5") };
=cut
sub retrieve_effects {
	$debug2 and print "&retrieve_effects\n";
	my $file = shift;
	my %current_cops = %cops; # XXX why bother
	my %current_copp = %copp; # similar name!!!!
	assign_vars($file, @effects_dynamic_vars);
	my %old_copp = %copp;  # XXX why bother
	my %old_cops = %cops; 
	%cops = %current_cops;
	%copp = %current_copp; ## similar name!!


	#print "\%state_c_ops\n ", yaml_out( \%state_c_ops), "\n\n";
	#print "\%old_cops\n ", yaml_out( \%old_cops), "\n\n";
	#print "\%old_copp\n ", yaml_out( \%old_copp), "\n\n";
#	return;

	restore_time_marker_labels();

	# remove effects except vol and pan, in which case, update vals

	map{ 	
	
		$debug and print "found chain $_: ", join " ",
		@{ $ti[$_]->ops }, "\n";

		my $n = $_;
		map {	my $id = $_; 
				$debug and print "checking chain $n, id $id: ";
				
				if (	$ti[$n]->vol eq $id or
						$ti[$n]->pan eq $id  ){

					# do nothing
				$debug and print "is vol/pan\n";

				}
				else {
					
					$debug and print "is something else\n";
					remove_effect($id) ;
					remove_op($id)
			}

		} @{ $ti[$_]->ops }
	} all_chains();
			
	return;

	# restore ops list
	
	map{ $ti[$_]->set(ops => $state_c_ops{$_}) } all_chains();

	# restore ops->chain mapping
	
	%cops = %old_copp;

	# add the correct copp entry for each id except vol/pan
	map{ my $n = $_;
			map {	my $id = $_; 
				if (	$ti[$n]->vol eq $id or
						$ti[$n]->pan eq $id  ){

					$copp{$id}->[0] = $old_copp{$id}->[0];
				}
				else {  $copp{$id} = $old_copp{$id} }

			} @{ $ti[$_]->ops }
		} all_chains();

	# apply ops
	
	my $did_apply = 0;

	for my $n (all_chains() ) { 
		for my $id (@{$ti[$n]->ops}){
			$did_apply++ 
				unless $id eq $ti[$n]->vol
					or $id eq $ti[$n]->pan;

			
			add_effect({  
						chain => $cops{$id}->{chain},
						type => $cops{$id}->{type},
						cop_id => $id,
						parent_id => $cops{$id}->{belongs_to},
						});

		# TODO if parent has a parent, i am a parameter controller controlling
		# a parameter controller, and therefore need the -kx switch
		}
	}
	# $did_apply and print "########## applied\n\n";
	
	# $ew->deiconify or $ew->iconify;

}

	

### end
