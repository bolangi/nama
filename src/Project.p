# --------- Project related subroutines ---------

package ::;
use Modern::Perl;
use Carp;
use File::Slurp;

use ::Globals qw(:all);

{ # OPTIMIZATION

  # we allow for the (admitted rare) possibility that
  # $config->{root_dir} may change

my %proot;
sub project_root { 
	$proot{$config->{root_dir}} ||= resolve_path($config->{root_dir})
}
}

sub config_file { $config->{opts}->{f} ? $config->{opts}->{f} : ".namarc" }

{ # OPTIMIZATION
my %wdir; 
sub this_wav_dir {
	$config->{opts}->{p} and return $config->{root_dir}; # cwd
	$gui->{_project_name}->{name} and
	$wdir{$gui->{_project_name}->{name}} ||= resolve_path(
		join_path( project_root(), $gui->{_project_name}->{name}, q(.wav) )  
	);
}
}

sub project_dir {
	$config->{opts}->{p} and return $config->{root_dir}; # cwd
	$gui->{_project_name}->{name} and join_path( project_root(), $gui->{_project_name}->{name}) 
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
	$debug2 and print "&initialize_project_data\n";

	return if transport_running();
	$ui->destroy_widgets();
	$ui->project_label_configure(
		-text => uc $gui->{_project_name}->{name}, 
		-background => 'lightyellow',
		); 

	# effect variables - no object code (yet)
	
	$fx->{id_counter} = "A"; # autoincrement counter
	%{$fx->{applied}}	= ();  # effect and controller objects (hashes)
	%{$fx->{params}}   = ();  # chain operator parameters
	               # indexed by {$id}->[$param_no]
	               # zero-based {AB}->[0] (parameter 1)

	%{$gui->{tracks}} = ();
	%{$gui->{fx}} = ();

	$gui->{_markers_armed} = 0;

	map{ $_->initialize() } qw(
							::Mark
							::Fade
							::Edit
							::Bus
							::Track
							::Insert
							);
	
	# volume settings
	
	@{$fx->{muted}} = ();

	# $is_armed = 0;
	
	$setup->{_old_snapshot} = {};
	$mode->{preview} = $config->{initial_mode};
	$mode->{mastering} = 0;
	$gui->{_project_name}->{save_file_version_number} = 0; 
	
	%{$gui->{_project_name}->{bunch}} = ();	
	
	create_system_buses();
	$this_bus = 'Main';

	%{$setup->{wav_info}} = ();
	
	clear_offset_run_vars();
	$mode->{offset_run} = 0;
	$this_edit = undef;

	::ChainSetup::initialize();
}
sub load_project {
	$debug2 and print "&load_project\n";
	my %h = @_;
	$debug and print yaml_out \%h;
	print("no project name.. doing nothing.\n"),return 
		unless $h{name} or $gui->{_project_name};
	$gui->{_project_name}->{name} = $h{name} if $h{name};

	if ( ! -d join_path( project_root(), $gui->{_project_name}->{name}) ){
		if ( $h{create} ){
			map{create_dir($_)} &project_dir, &this_wav_dir ;
		} else { 
			print qq(
Project "$gui->{_project_name}->{name}" does not exist. 
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

	restore_state( $h{settings} ? $h{settings} : $file->{state_store}) unless $config->{opts}->{M} ;
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


	$config->{opts}->{M} = 0; # enable 
	
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
	my @system_buses = split " ", $buses;
	map{ $config->{_is_system_bus}->{$_}++ } @system_buses;
	delete $config->{_is_system_bus}->{Main}; # because we want to display it
	map{ ::Bus->new(name => $_ ) } @system_buses;
	
	# a bus should identify it's mix track
	$bn{Main}->set( send_type => 'track', send_id => 'Master');

	$gn{Main} = $bn{Main};
}


## project templates

sub new_project_template {
	my ($template_name, $template_description) = @_;

	my @tracks = ::Track::all();

	# skip if project is empty

	say("No user tracks found, aborting.\n",
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
			qw(	effect_chain_stack      
			);
		 map{ $track->set($_ => {})  } 
			qw( cache_map 
			);
		
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
 		name     => $gui->{_project_name}->{name},
 		settings => $previous_state,
	);

	# remove temp state file
	
	unlink join_path( project_dir(), "$previous_state.yml") ;
	
}
sub use_project_template {
	my $name = shift;
	my @tracks = ::Track::all();

	# skip if project isn't empty

	say("User tracks found, aborting. Use templates in an empty project."), 
		return if scalar @tracks > 2;

	# load template
	
 	load_project(
 		name     => $gui->{_project_name}->{name},
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
		say "$name: removing template";
		$name .= ".yml" unless $name =~ /\.yml$/;
		unlink join_path( project_root(), "templates", $name);
	} @_;
	
}
1;
__END__
