# --------- Project related subroutines ---------

package ::;
use Modern::Perl;

our (
	$debug,
	$debug2,
	$ui,
	$cop_id,
	%cops,
	%copp,
	%old_vol,
	@input_chains,
	@output_chains,
	$preview,
	$mastering_mode,
	$saved_version,
	%bunch,
	$this_bus,
	%inputs,
	%outputs,
	%wav_info,
	$offset_run_flag,
	$this_edit,
	$project_name,
	$state_store_file,
	%opts,
	%tn,
	%track_widget,
	%effects_widget,
	$markers_armed,
	@already_muted,
	$old_snapshot,
	$initial_user_mode,
	$project,	
);

sub initialize_project_data {
	$debug2 and print "&initialize_project_data\n";

	return if transport_running();
	$ui->destroy_widgets();
	$ui->project_label_configure(
		-text => uc $project_name, 
		-background => 'lightyellow',
		); 

	# effect variables - no object code (yet)
	
	$cop_id = "A"; # autoincrement counter
	%cops	= ();  # effect and controller objects (hashes)
	%copp   = ();  # chain operator parameters
	               # indexed by {$id}->[$param_no]
	               # zero-based {AB}->[0] (parameter 1)

	%old_vol = (); 

	@input_chains = ();
	@output_chains = ();

	%track_widget = ();
	%effects_widget = ();

	$markers_armed = 0;

	map{ $_->initialize() } qw(
							::Mark
							::Fade
							::Edit
							::Bus
							::Track
							::Insert
							);
	
	# volume settings
	
	%old_vol = ();
	@already_muted = ();

	# $is_armed = 0;
	
	$old_snapshot = {};
	$preview = $initial_user_mode;
	$mastering_mode = 0;
	$saved_version = 0; 
	
	%bunch = ();	
	
	create_system_buses();
	$this_bus = 'Main';

	%inputs = %outputs = ();
	
	%wav_info = ();
	
	clear_offset_run_vars();
	$offset_run_flag = 0;
	$this_edit = undef;

}
sub load_project {
	$debug2 and print "&load_project\n";
	my %h = @_;
	$debug and print yaml_out \%h;
	print("no project name.. doing nothing.\n"),return 
		unless $h{name} or $project;
	$project_name = $h{name} if $h{name};

	if ( ! -d join_path( project_root(), $project_name) ){
		if ( $h{create} ){
			map{create_dir($_)} &project_dir, &this_wav_dir ;
		} else { 
			print qq(
Project "$project_name" does not exist. 
Loading project "untitled".
);
			load_project( qw{name untitled create 1} );
			return;
		}
	} 
	# we used to check each project dir for customized .namarc
	# read_config( global_config() ); 
	
	teardown_engine(); # initialize_ecasound_engine; 
	initialize_project_data();
	remove_riff_header_stubs(); 
	cache_wav_info();
	rememoize();

	restore_state( $h{settings} ? $h{settings} : $state_store_file) unless $opts{m} ;
	if (! $tn{Master}){

		::SimpleTrack->new( 
			group => 'Master', 
			name => 'Master',
			send_type => 'soundcard',
			send_id => 1,
			width => 2,
			rw => 'MON',
			source_type => undef,
			source_id => undef); 

		my $mixdown = ::MixDownTrack->new( 
			group => 'Mixdown', 
			name => 'Mixdown', 
			width => 2,
			rw => 'OFF',
			source_type => undef,
			source_id => undef); 

		#remove_effect($mixdown->vol);
		#remove_effect($mixdown->pan);
	}


	$opts{m} = 0; # enable 
	
	dig_ruins() unless scalar @::Track::all > 2;

	# possible null if Text mode
	
	$ui->global_version_buttons(); 
	$ui->refresh_group;

	$debug and print "project_root: ", project_root(), $/;
	$debug and print "this_wav_dir: ", this_wav_dir(), $/;
	$debug and print "project_dir: ", project_dir() , $/;

 1;
}	

sub dig_ruins { # only if there are no tracks 
	
	$debug2 and print "&dig_ruins";
	return if ::Track::user();
	$debug and print "looking for WAV files\n";

	# look for wave files
		
	my $d = this_wav_dir();
	opendir my $wav, $d or carp "couldn't open $d: $!";

	# remove version numbers
	
	my @wavs = grep{s/(_\d+)?\.wav//i} readdir $wav;

	closedir $wav;

	my %wavs;
	
	map{ $wavs{$_}++ } @wavs;
	@wavs = keys %wavs;

	$debug and print "tracks found: @wavs\n";
 
	$ui->create_master_and_mix_tracks();

	map{add_track($_)}@wavs;

}

sub remove_riff_header_stubs {

	# 44 byte stubs left by a recording chainsetup that is 
	# connected by not started
	
	$debug2 and print "&remove_riff_header_stubs\n";
	

	$debug and print "this wav dir: ", this_wav_dir(), $/;
	return unless this_wav_dir();
         my @wavs = File::Find::Rule ->name( qr/\.wav$/i )
                                        ->file()
                                        ->size(44)
                                        ->extras( { follow => 1} )
                                     ->in( this_wav_dir() );
    $debug and print join $/, @wavs;

	map { unlink $_ } @wavs; 
}
1;
__END__
