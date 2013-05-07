# --------- Project related subroutines ---------

{
package ::Project;
use Modern::Perl; use Carp;
sub hello { my $self = shift; say "hello $self: ",::Dumper $::project}
}

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

sub project_dir {
	$config->{opts}->{p} and return $config->{root_dir}; # cwd
	$project->{name} and join_path( project_root(), $project->{name}) 
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

	return if transport_running();
	$ui->destroy_widgets();
	$ui->project_label_configure(
		-text => uc $project->{name}, 
		-background => 'lightyellow',
		); 

	$gui->{tracks} = {};
	$gui->{fx} = {};

	$gui->{_markers_armed} = 0;

	map{ $_->initialize() } qw(
							::Mark
							::Fade
							::Edit
							::Bus
							::Track
							::Insert
							);
	initialize_effects_data();

	# $is_armed = 0;

	$setup->{_old_snapshot} = {};

	$mode->{preview} = $config->{initial_mode};
	$mode->{mastering} = 0;

	$project->{save_file_version_number} = 0; 
	$project->{track_comments} = {};
	$project->{track_version_comments} = {};
	$project->{undo_buffer} = [];
	$project->{repo} = undef;
	$project->{artist} = undef;
	
	$project->{bunch} = {};	
	
	create_system_buses();
	$this_bus = 'Main';

	$setup->{wav_info} = {};
	
	clear_offset_run_vars();
	$mode->{offset_run} = 0;
	$this_edit = undef;
	
	$mode->{preview} = 0;

	::ChainSetup::initialize();

}
sub initialize_effects_data {

	# effect variables - no object code (yet)
	
	$fx->{id_counter} = "A"; # autoincrement counter
	$fx->{applied}	= {};  # effect and controller objects (hashes)
	$fx->{params}   = {};  # chain operator parameters
	               # indexed by {$id}->[$param_no]
	               # zero-based {AB}->[0] (parameter 1)

	# volume settings
	
	$fx->{muted} = [];

}

	

sub load_project {
	logsub("&load_project");
	my %args = @_;
	logpkg('debug', sub{json_out \%args});
	throw("no project name.. doing nothing."),return 
		unless $args{name} or $project->{name};

	$project->{name} = $args{name} if $args{name};

	if ( ! -d project_dir() )
	{ 	
		if ( $args{create} )
		{ 
			map{create_dir($_)} project_dir(), this_wav_dir() ;
		}
		else 
		{ ::pager3(
			qq(Project "$project->{name}" does not exist.\n Loading project "untitled".)
			);
			load_project( qw{name untitled create 1} );
			return;
		}	
	}

	# we used to check each project dir for customized .namarc
	# read_config( global_config() ); 
	
	teardown_engine();
	trigger_rec_cleanup_hooks();
	initialize_project_data();
	remove_riff_header_stubs(); 
	cache_wav_info();
	restart_wav_memoize();
	

	if( $config->{use_git} ){
		my $initializing_repo;
		Git::Repository->run( init => project_dir()), $initializing_repo++
			unless -d join_path( project_dir().  '.git');
		$project->{repo} = Git::Repository->new( work_tree => project_dir() );
		write_file($file->git_state_store, "{}\n"), $initializing_repo++
			if ! -e $file->git_state_store and ! $project->{repo}->run( 'branch' );

		if ($initializing_repo){
			$project->{repo}->run( add => $file->git_state_store );
			$project->{repo}->run( commit => '--quiet', '--message', "initial commit");
		}
	}

	restore_state($args{settings}) unless $config->{opts}->{M} ;

	if (! $tn{Master}){

		::SimpleTrack->new( 
			group => 'Master', 
			name => 'Master',
			send_type => 'soundcard',
			send_id => 1,
			width => 2,
			rw => 'REC',
			rec_defeat => 1,
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


	$config->{opts}->{M} = 0; # enable 
	
	# $args{nodig} allow skip for convert_project_format
	dig_ruins() unless (scalar @::Track::all > 2 ) or $args{nodig};

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

sub dig_ruins { # only if there are no tracks 
	
	logsub("&dig_ruins");
	return if ::Track::user();
	logpkg('debug', "looking for WAV files");

	# look for wave files
		
	my $d = this_wav_dir();
	opendir my $wav, $d or carp "couldn't open directory $d: $!";

	# remove version numbers
	
	my @wavs = grep{s/(_\d+)?\.wav//i} readdir $wav;

	closedir $wav if $wav;

	my %wavs;
	
	map{ $wavs{$_}++ } @wavs;
	@wavs = keys %wavs;

	logpkg('debug', "tracks found: @wavs");
 
	$ui->create_master_and_mix_tracks();

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

	# The following are ::Bus objects, no routing.
	# They are hidden from the user.
	
	my $buses = q(
			Master		# master fader track
			Mixdown		# mixdown track
			Mastering	# mastering network
			Insert		# auxiliary tracks for inserts
			Cooked		# for track caching
			Temp		# temp tracks while generating setup
	);
	($buses) = strip_comments($buses); # need initial parentheses
	my @system_buses = split " ", $buses;

	# create them
	
	map{ ::Bus->new(name => $_ ) } @system_buses;

	map{ $config->{_is_system_bus}->{$_}++ } @system_buses;

	# create Main bus (the mixer)

	::MasterBus->new(
		name 		=> 'Main',
		send_type 	=> 'track', 
		send_id => 'Master');

	# null bus, routed only from track source_* and send_send_* fields 
	::SubBus->new(
		name 		=> 'null', 
		send_type => 'null',
	);
}


## project templates

sub new_project_template {
	my ($template_name, $template_description) = @_;

	my @tracks = ::Track::all();

	# skip if project is empty

	throw("No user tracks found, aborting.\n",
		"Cannot create template from an empty project."), 
		return if scalar @tracks < 3;

	# save current project status to temp state file 
	
	my $previous_state = '_previous_state.yml';
	save_state($previous_state);

	# edit current project into a template
	
	# No tracks are recorded, so we'll remove 
	#	- version (still called 'active')
	# 	- track caching
	# 	- region start/end points
	# 	- effect_chain_stack
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
		 map{ $track->set($_ => [])  } 
			qw(	effect_chain_stack  );
		
	} @tracks;

	# Throw away command history
	
	$text->{term}->SetHistory();
	
	# Buses needn't set version info either
	
	map{$_->set(version => undef)} values %bn;
	
	# create template directory if necessary
	
	mkdir join_path(project_root(), "templates");

	# save to template name
	
	save_state( join_path(project_root(), "templates", "$template_name.yml"));

	# add description, but where?
	
	# recall temp name
	
 	load_project(  # restore_state() doesn't do the whole job
 		name     => $project->{name},
 		settings => $previous_state,
	);

	# remove temp state file
	
	unlink join_path( project_dir(), "$previous_state.yml") ;
	
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
 		settings => join_path(project_root(),"templates",$name),
	);
	save_state();
}
sub list_project_templates {
	my $read = read_file(join_path(project_root(), "templates"));
	push my @templates, "\nTemplates:\n", map{ m|([^/]+).yml$|; $1, "\n"} $read;        
	pager(@templates);
}
sub remove_project_template {
	map{my $name = $_; 
		pager2("$name: removing template");
		$name .= ".yml" unless $name =~ /\.yml$/;
		unlink join_path( project_root(), "templates", $name);
	} @_;
	
}
1;
__END__
