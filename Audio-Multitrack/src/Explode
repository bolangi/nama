=comment
Each project is currently represented by a pair of directories.
in wav_dir/my_gig and in wav_dir/.ecmd/my_gig

Wav gets its directories from subs in UI,
why inherit all that other stuff? It doesn't matter, 
Wav is fairly simple

Project also inherits from UI, to get these
key subs. 

Project, in contrast with Wav, needs all those procedures,
so that $my_gig->start_transport would be possible.

$paul_brocante->start_transport;

We set $project name for the 
Once we have set $project_name, everything starts
happening.


my $ui = UI::Graphical->new;

my $project = $ui->project(name => "paul_brocante");
my $project = $ui->project(name => "paul_brocante", create => 1);
$project->retain("my slider activity");
$project->perform("my slider activity");
$project->start;
$project->everything_that_UI_does

consequence: have to rewrite all the UI (especially GUI) 
procedural code to do $project->start instead of &start,
for what? To be able to pass around project objects??

Definitely not necessary.

=cut


## The following methods belong to the Project class

#my $s = Project->new(name => 'paul_brocante');
# print $s->project_dir;

package ::Project;
our @ISA='::';
use Carp;
use Object::Tiny qw(name);
sub hello {"i'm a project"}
sub project { 
	my $ui = shift; 
	my %vals = @_;
	$vals{name} or carp "invoked without values" and return;
	my $name = remove_spaces( $vals{name} );
	$vals{name} = $name;
	if (-d join_path(&wav_dir, $name)
			or $vals{create_dir} ){

		$project_name=$name; # dependence on global variable $project_name
	}
	if ($vals{create_dir}){
		map{create_dir($_)} &this_wav_dir, &project_dir;
		delete $vals{create_dir};
	}
	return bless { %vals }, $class;
}
sub load_project { $ui->project(@_) }

sub project { # object method
	my $ui = shift; 
	my %h = @_;
	$debug2 and print "&new (load_project)\n";
	$debug and print "project name: $h{-name} create: $h{-create}\n";
	carp ("project name required\n"), return unless $h{-name};
	my $old_project = $project_name;
	$project_name = $h{-name};
	if ( ! -d project_dir) {
		$debug and print "directory: ", project_dir, "not found\n";
		if ( $h{-create} ){ 
			$debug and print join " ", 
				"Creating directories:", this_wav_dir, project_dir, $/;
			create_dir(this_wav_dir, project_dir);
		} else { 
			print "non existent directory: ", project_dir, $/;
			$project_name = $old_project_name;
			return;
		}
	}

	
=comment 
	# OPEN EDITOR TODO
	my $new_file = join_path ($ecmd_home, $project_name, $parameters);
	open PARAMS, ">$new_file" or carp "couldn't open $new_file for write: $!\n";
	print PARAMS $configuration;
	close PARAMS;
	system "$ENV{EDITOR} $new_file" if $ENV{EDITOR};
=cut
	read_config;
	initialize_project_data;
	remove_small_wavs; 
	print "reached here!!!\n";
	retrieve_state( $h{-settings} ? $h{-settings} : $state_store_file) unless $opts{m} ;
	$debug and print "found ", scalar @all_chains, "chains\n";
	add_mix_track, dig_ruins unless scalar @all_chains;
	$ui->global_version_buttons;

}
#The mix track will always be track index 1 i.e. $state_c{$n}
# for $n = 1, And take index 1.

sub initialize_project_data {
	$debug2 and print "&initialize_project_data\n";

	return if transport_running();
	$ui->project_label_configure(
		-text => uc $project_name, 
		-background => 'lightyellow',
		); 

	# assign_var($project_init_file, @project_vars);

	$last_version = 0;
	%track_names = ();
	%state_c        = ();   #  chain related state
	%state_t        = ();   # take related state
	%cops        = ();   
	$cop_id           = "A"; # autoincrement
	%copp           = ();    # chain operator parameters, dynamic
	                        # indexed by {$id}->[$param_no]
							# and others
	%old_vol = ();

	%take        = (); # the group a chain belongs to # by chain_id
	%chain       = (); # the chain_id corresponding to a track name
	#%alias      = ();  # a way of naming takes

	@takes       = ();  
	@record		= ();
	@monitor	= ();
	@mute = (); 
	@all_chains  = (); # indices of all chains
	@input_chains = ();
	@output_chains = ();

	$i           = 0;  # chain counter
	$t           = 0;  # take counter

	%widget_c = ();
	@widget_t = ();
	%widget_e = ();
	

	# time related
	
	$markers_armed = 0;
	@marks = ();

	
	# volume settings
	
	%old_vol = ();

	# $is_armed = 0;

$ui->destroy_widgets();

increment_take();  # to 1

$ui->take_gui;

}

sub project_dir { 
	my $project = shift;
	join_path( ecmd_dir, $project->name);
}
sub this_wav_dir {
	my $project = shift;
	join_path( wav_dir, $project->name);
}


sub explode {  
# will not work for unversioned  vocal.wav
	my $wav = shift;
	map{  UI::Wav->new(head => $_) 

		} map{ s/.wav$//i; $_} 

			@{ [ values %{ $wav->targets } ] }
}

# package Track
# usage: Track->new( WAV = [$vocal->explode] );
# usage: Track->new( WAV = $vocal );
# $vocal is a Wav,

# following for objects to polymorph in taking 
# arrays or array refs.
sub deref_ {
	my $ref = shift;
	@_ = @{ $ref } if ref $_[0] =~ /ARRAY/;
}


