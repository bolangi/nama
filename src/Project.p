# --------- Project related subroutines ---------

{
package ::Project;
use Modern::Perl; use Carp;
sub hello { my $self = shift; say "hello $self: ",::Dumper $::project}
}
{
package ::;
use Modern::Perl;
use Carp;
use File::Slurp;

# this sub caches the symlink-resolved form of the 
# project root directory

sub project_root { 
	state %proot;
	$proot{$config->{root_dir}} ||= resolve_path($config->{root_dir})
}

sub config_file { $config->{opts}->{f} ? $config->{opts}->{f} : ".namarc" }

{ # OPTIMIZATION
my %wdir; 
sub this_wav_dir {
	$config->{opts}->{p} and return $config->{root_dir}; # cwd
	$project->{name} and
	$wdir{$project->{name}} ||= resolve_path(
		join_path( project_root(), $project->{name}, q(.wav) )  
	);
}
}
sub waveform_dir { join_path(project_dir(), q(.waveform) ) }
sub project_dir {
	$config->{opts}->{p} and return $config->{root_dir}; # cwd
	$project->{name} and join_path( project_root(), $project->{name}) 
}
# we prepend a slash 
sub bus_track_display { 
	my ($busname, $trackname) = ($this_bus, $this_track && $this_track->name || '');
	($busname eq "Main" ? "": "$busname/" ). $trackname
}
sub list_projects {
	my $projects = join "\n", sort map{
			my ($vol, $dir, $lastdir) = File::Spec->splitpath($_); $lastdir
		} File::Find::Rule  ->directory()
							->maxdepth(1)
							->extras( { follow => 1} )
						 	->in( project_root());
	pager($projects);
}

sub initialize_project_data {

	logsub("&initialize_project_data");

	-d ::waveform_dir() or mkdir ::waveform_dir();
	$ui->destroy_widgets();
	$ui->project_label_configure(
		-text => uc $project->{name}, 
		-background => 'lightyellow',
		); 

	$gui->{tracks} = {};
	$gui->{fx} = {};

	$gui->{_markers_armed} = 0;

	map{ $_->initialize() } qw(
							::Edit
							::Fade
							::Mark
							::Bus
							::Track
							::Insert
							::Effect
							::EffectChain
							);
	# $is_armed = 0;

	$setup->{_old_snapshot} = "";

	$mode->{mastering} = 0;

	$project->{save_file_version_number} = 0; 
	$project->{track_comments} = {};
	$project->{track_version_comments} = {};
	$project->{repo} = undef;
	$project->{artist} = undef;
	$project->{bunch} = {};	
	$project->{sample_rate} = $config->{sample_rate};
	
	create_system_buses();
	$this_bus = 'Main';

	$setup->{wav_info} = {};
	
	clear_offset_run_vars();
	$mode->{offset_run} = 0;
	$this_edit = undef;
	
	{
	no warnings 'uninitialized';
	$mode->{preview}++ if $config->{initial_mode} eq 'preview';
	$mode->{doodle}++  if $config->{initial_mode} eq 'doodle';
	}

	::ChainSetup::initialize();
	reset_hotkey_buffers();
	reset_command_buffer();
	$this_engine->reset_ecasound_selections_cache();

}

sub load_project {
	logsub("&load_project");
	my %args = @_;
	logpkg('debug', sub{json_out \%args});
	$project->{name} = $args{name} if $args{name};
	$config->{opts}->{c} and $args{create}++;
	if (! $project->{name} or $project->{name} and ! -d project_dir() and ! $args{create})
	{
		no warnings 'uninitialized';
		::pager_newline(qq(Project "$project->{name}" not found. Loading project "untitled".)); 
		$project->{name} = "untitled", $args{create}++,
	}
	if ( ! -d project_dir() )
	{
		map{create_dir($_)} project_dir(), this_wav_dir(), waveform_dir() if $args{create};
	}

	# we used to check each project dir for customized .namarc
	# read_config( global_config() ); 
	
	teardown_engine();
	trigger_rec_cleanup_hooks();
	initialize_project_data();
	remove_riff_header_stubs(); 
	cache_wav_info();
	restart_wav_memoize();
	initialize_project_git_repository();
	restore_state($args{settings}) unless $config->{opts}->{M} ;

	$config->{opts}->{M} = 0; # enable 
	
	initialize_mixer();
	dig_ruins(); # in case there are audio files, but no tracks present

	git_commit("initialize new project") if $config->{use_git};

	# possible null if Text mode
	
	#$ui->global_version_buttons(); 
	#$ui->refresh_group;

	logpkg('debug', "project_root: ", project_root());
	logpkg('debug', "this_wav_dir: ", this_wav_dir());
	logpkg('debug', "project_dir: ", project_dir());

 1;
}	
sub restore_state {
		my $name = shift;

		if( ! $name  or $name =~ /.json$/ or !  $config->{use_git})
		{
			restore_state_from_file($name)
		}
		else { restore_state_from_vcs($name)  }
}
sub initialize_mixer {
	return if $tn{Main};
		::SimpleTrack->new( 
			group => 'Null', 
			name => 'Main',
			send_type => 'soundcard',
			send_id => 1,
			width => 2,
			rw => MON,
			source_type => 'bus',
			source_id => 'Main',
			); 

		my $mixdown = ::MixDownTrack->new( 
			group => 'Mixdown', 
			name => 'Mixdown', 
			width => 2,
			rw => OFF,
			source_type => 'track',
			source_id => 'Main',
			send_type => 'soundcard',
			send_id => 1,
			); 
	$ui->create_master_and_mix_tracks();
}



sub dig_ruins {
	
	logsub("&dig_ruins");
	return if user_tracks_present();
	logpkg('debug', "looking for audio files");

	my $d = this_wav_dir();
	opendir my $wav, $d or carp "couldn't open directory $d: $!";

	# remove version numbers
	
	my @wavs = grep{s/(_\d+)?\.wav$//i} readdir $wav;

	closedir $wav if $wav;

	my %wavs;
	
	map{ $wavs{$_}++ } @wavs;
	@wavs = keys %wavs;

	logpkg('debug', "tracks found: @wavs");
 
	map{add_track($_)}@wavs;

}

sub remove_riff_header_stubs {

	# 44 byte stubs left by a recording chainsetup that is 
	# connected by not started
	
	logsub("&remove_riff_header_stubs");
	

	logpkg('debug', "this wav dir: ", this_wav_dir());
	return unless this_wav_dir();
         my @wavs = File::Find::Rule ->name( qr/\.wav$/i )
                                        ->file()
                                        ->size(44)
                                        ->extras( { follow => 1} )
                                     	->in( this_wav_dir() )
									if -d this_wav_dir();
    logpkg('debug', join $/, @wavs);

	map { unlink $_ } @wavs; 
}

sub create_system_buses {
	logsub("&create_system_buses");

	my $buses = q(
		Main 		::SubBus send_type track send_id Main	# master fader track
		Mixdown		::Bus									# mixdown track
		Mastering	::Bus									# mastering network
		Insert		::Bus									# auxiliary tracks for inserts
		Cooked		::Bus									# for track caching
		Temp		::Bus									# temp tracks while generating setup
        Null		::Bus 									# unrouted for Main
		Midi		::MidiBus	send_type null send_id null # all MIDI tracks
		Aux			::SubBus	send_type null 				# routed only from track source_* and send_* fields
	);
	($buses) = strip_comments($buses); 	# need initial parentheses
	$buses =~ s/\A\s+//; 		   	   	# remove initial newline and whitespace
	$buses =~ s/\s+\z//; 		   		# remove terminating newline and whitespace
	my @buses = split "\n", $buses;
	for my $bus (@buses)
	{
		my ($name, $class, @args) = split " ",$bus;
		$class->new(name => $name, @args);
	}
}


## project templates

sub new_project_template {
	my ($template_name, $template_description) = @_;

	my @tracks = all_tracks();

	# skip if project is empty

	throw("No user tracks found, aborting.\n",
		"Cannot create template from an empty project."), 
		return if ! user_tracks_present();

	# save current project status to temp state file 
	
	my $previous_state = '_previous_state.json';
	save_state($previous_state);

	# edit current project into a template
	
	# No tracks are recorded, so we'll remove 
	#	- version (still called 'active')
	# 	- track caching
	# 	- region start/end points
	# Also
	# 	- unmute all tracks
	# 	- throw away any pan caching

	map{ my $track = $_;
		 $track->unmute;
		 map{ $track->set($_ => undef)  } 
			qw( version	
				old_pan_level
				region_start
				region_end
			);
	} @tracks;

	# Throw away command history
	
	$text->{term}->SetHistory();
	
	# Buses needn't set version info either
	
	map{$_->set(version => undef)} values %bn;
	
	# create template directory if necessary
	
	mkdir join_path(project_root(), "templates");

	# save to template name
	
	save_state( join_path(project_root(), "templates", "$template_name.json"));

	# add description, but where?
	
	# recall temp name
	
 	load_project(  # restore_state() doesn't do the whole job
 		name     => $project->{name},
 		settings => $previous_state,
	);

	# remove temp state file
	
	unlink join_path( project_dir(), $previous_state) ;
	
}
sub use_project_template {
	my $name = shift;
	my @tracks = ::Track::all();

	# skip if project isn't empty

	throw("User tracks found, aborting. Use templates in an empty project."), 
		return if scalar @tracks > 2;

	# load template
	
 	load_project(
 		name     => $project->{name},
 		settings => join_path(project_root(),"templates","$name.json"),
	);
	save_state();
}
sub list_project_templates {
	my @templates= map{ /(.+?)\.json$/; $1}  read_dir(join_path(project_root(), "templates"));
	
	pager(join "\n","Templates:",@templates);
}
sub remove_project_template {
	map{my $name = $_; 
		pager("$name: removing template");
		$name .= ".yml" unless $name =~ /\.yml$/;
		unlink join_path( project_root(), "templates", $name);
	} @_;
	
}
} # end package ::
1;
__END__
