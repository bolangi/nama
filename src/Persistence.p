# ---------- Persistent State Support -------------


package ::;
use File::Copy;
use Modern::Perl; no warnings 'uninitialized';

sub save_state {
	my $filename = shift;
	if ($filename)
	{
		$filename = 
				$filename =~ m{/} 	
									? $filename	# as-is if input contains slashes
									: join_path(project_dir(),$filename) 
	}
	my $path = $filename || $file->state_store();
	logsub("&save_state");
	$project->{save_file_version_number} = $VERSION;

	# some stuff get saved independently of our state file
	
	logpkg('debug', "saving palette");
	$ui->save_palette;

	# do nothing more if only Master and Mixdown
	
	if (scalar @::Track::all == 2 ){
		print "No user tracks, skipping...\n";
		return;
	}

	print "\nSaving state as ",
	save_system_state($path), "\n";
	save_global_effect_chains();

	# store alsa settings

	if ( $config->{opts}->{a} ) {
		my $filename = $filename;
		$filename =~ s/\.yml$//;
		print "storing ALSA settings\n";
		print qx(alsactl -f $filename.alsa store);
	}
}
sub initialize_marshalling_arrays {
	@tracks_data = (); # zero based, iterate over these to restore
	@bus_data = (); # 
	@marks_data = ();
	@fade_data = ();
	@inserts_data = ();
	@edit_data = ();
	@project_effect_chain_data = ();
	@global_effect_chain_data = ();
	$text->{command_history} = {};

}

sub save_system_state {

	my $path = shift;
	my $output_format = shift;

	sync_effect_parameters(); # in case a controller has made a change
	# we sync read-only parameters, too, but I think that is
	# harmless

	# remove null keys in $fx->{applied} and $fx->{params}
	# would be better to find where they come from
	
	delete $fx->{applied}->{''};
	delete $fx->{params}->{''};

	initialize_marshalling_arrays();
	
	# prepare tracks for storage
	
	$this_track_name = $this_track->name;

	logpkg('debug', "copying tracks data");

	map { push @tracks_data, $_->as_hash } ::Track::all();
	# print "found ", scalar @tracks_data, "tracks\n";

	# delete obsolete fields
	map { my $t = $_;
				map{ delete $t->{$_} } 
					qw(ch_r ch_m source_select send_select jack_source jack_send);
	} @tracks_data;


	logpkg('debug', "copying bus data");

	@bus_data = map{ $_->as_hash } ::Bus::all();

	# prepare inserts data for storage
	
	logpkg('debug', "copying inserts data");
	
	@inserts_data = map{ $_->as_hash } values %::Insert::by_index;

	# prepare marks data for storage (new Mark objects)

	logpkg('debug', "copying marks data");
	@marks_data = map{ $_->as_hash } ::Mark::all();

	@fade_data = map{ $_->as_hash } values %::Fade::by_index;

	@edit_data = map{ $_->as_hash } values %::Edit::by_index;

	@project_effect_chain_data = map { $_->as_hash } ::EffectChain::find(project => 1);

	# save history -- 50 entries, maximum

	my @history;
	@history = $text->{term}->GetHistory if $text->{term};
	my %seen;
	$text->{command_history} = [];
	map { push @{$text->{command_history}}, $_ 
			unless $seen{$_}; $seen{$_}++ } @history;
	my $max = scalar @{$text->{command_history}};
	$max = 50 if $max > 50;
	@{$text->{command_history}} = @{$text->{command_history}}[-$max..-1];
	logpkg('debug', "serializing");

	my @formats = $output_format || $config->serialize_formats;

	map{ 	my $format = $_ ;
			serialize(
				file => $path,
				format => $format,
				vars => \@new_persistent_vars,
				class => '::',
				);

	} @formats;

	serialize(
		file => $file->unversioned_state_store,
		format => 'json',
		vars => \@unversioned_state_vars,
		class => '::',
	);	

	$path
}
{
my %is_legal_suffix = ( 
		json => 'json', 
		yml => 'yaml', 
		pl 	 => 'perl',
		bin  => 'storable',
		yaml => 'yaml', # we allow formats as well
		perl => 'perl',
		storable => 'storable',
);
sub get_newest {
	
	# choose the newest
	#
	my ($path, $format) = @_;
	
	# simply return the file
	# if filename matches exactly, 
	# and we know the format
	
	return($path, $format) if -f $path and $is_legal_suffix{$format};

	my ($dir, $name) = $path =~ m!^(.*?)([^/]+)$!; 
	
	# otherwise we glob, sort and filter directory entries
	
	my @sorted = 
		sort{ $a->[1] <=> $b->[1] } 
		grep{ $is_legal_suffix{$_->[2]} }
		map 
		{ 
			my ($suffix) = m/^$path(?:\.(\w+))?$/;
			[$_, -M $_, $suffix] 
		} 
		glob("$path*");
	logpkg('debug', sub{yaml_out \@sorted});
	($sorted[0]->[0], $sorted[0]->[2]);
}
}

{ my %decode = 
	(
		json => \&json_in,
		yaml => sub 
		{ 
			my $yaml = shift;
			# remove empty key hash lines # fixes YAML::Tiny bug
			$yaml = join $/, grep{ ! /^\s*:/ } split $/, $yaml;

			# rewrite obsolete null hash/array substitution
			$yaml =~ s/~NULL_HASH/{}/g;
			$yaml =~ s/~NULL_ARRAY/[]/g;

			# rewrite $fx->{applied} 'owns' field to []
			
			# Note: this should be fixed at initialization
			# however we should leave this code 
			# for compatibility with past projects.
			
			$yaml =~ s/owns: ~/owns: []/g;

			$yaml = quote_yaml_scalars( $yaml );

			yaml_in($yaml);
		},
		perl => sub {my $perl_source = shift; eval $perl_source},
		storable => sub { my $bin = shift; thaw( $bin) },
	);
	
	# allow dispatch by either file format or suffix 
	@decode{qw(yml pl bin)} = @decode{qw(yaml perl storable)};

sub decode {

	my ($source, $suffix) = @_;
	$decode{$suffix} 
		or die qq(key $suffix: expecting one of).join q(,),keys %decode;
	$decode{$suffix}->($source);
}
}

sub restore_state {
	logsub("&restore_state");
	my $filename = shift;

	# convert it to a path w/o extension
	$filename = $file->state_store($filename);

	# get state file, newest if more than one
	# with same name, differing extensions
	# i.e. State.json and State.yml
	initialize_marshalling_arrays();

	my( $path, $suffix ) = get_newest($filename);
	
	logpkg('debug', "using file: $path");

	throw(
		$path ? "path: == $path.* ==," : "undefined path,"
			," state file not found"), return if ! -f $path;

	my $source = read_file($path);
	my $ref = decode($source, $suffix);
	logpkg('debug', "suffix: $suffix");	
	logpkg('debug', "source: $source");

	
	# restore persistent variables
	
	# first, auxiliary project state information
	# not placed under VCS
	
	( $path, $suffix ) = get_newest($file->unversioned_state_store);
	if ($path)
	{
		$source = read_file($path);

		my $ref = decode($source, $suffix);
		assign(
				data	=> $ref,	
				vars   	=> \@unversioned_state_vars,
				class 	=> '::');
		assign_singletons( { data => $ref });
	}
	
	#say "Project Effect Chain Data\n", json_out( \@project_effect_chain_data);
 	map { my $fx_chain = ::EffectChain->new(%$_) } @project_effect_chain_data;

	( $path, $suffix ) = get_newest($file->state_store);
	if ($path)
	{
		$source = read_file($path);
		$ref = decode($source, $suffix);


		# State file, old list, for backwards compatibility
		
		assign(
					data => $ref,
					vars   => \@persistent_vars,
					var_map => 1,
					class => '::');
		
		# State file new list
		
		assign(
					data => $ref,
					vars   => \@new_persistent_vars,
					class => '::');
		
		 

		# perform assignments for singleton
		# hash entries (such as $fx->{applied});
		# that that assign() misses
		
		assign_singletons({ data => $ref });

	}
	
	# remove null keyed entry from $fx->{applied},  $fx->{params}

	delete $fx->{applied}->{''};
	delete $fx->{params}->{''};


	my @keys = keys %{$fx->{applied}};

	my @spurious_keys = grep { effect_entry_is_bad($_) } @keys;

	if (@spurious_keys){

		logpkg('logwarn',"full key list is @keys"); 
		logpkg('logwarn',"spurious effect keys found @spurious_keys"); 
		logpkg('logwarn',"deleting them..."); 
		
		map{ 
			delete $fx->{applied}->{$_}; 
			delete $fx->{params}->{$_}  
		} @spurious_keys;

	}

	restore_global_effect_chains();

	##  print yaml_out \@groups_data; 
	
	# backward compatibility fixes for older projects
	
	
	my @vars = qw(
				@tracks_data
				@bus_data
				@groups_data
				@marks_data
				@fade_data
				@edit_data
				@inserts_data
	);

	# remove non HASH entries
	map {
		my $var = $_;
		my $eval_text  = qq($var  = grep{ ref =~ /HASH/ } $var );
		logpkg('debug', "want to eval: $eval_text "); 
		eval $eval_text;
	} @vars;

	if (! $project->{save_file_version_number} ){

		# Tracker group is now called 'Main'
	
		map{ $_->{name} = 'Main'} grep{ $_->{name} eq 'Tracker' } @groups_data;
		
		for my $t (@tracks_data){
			$t->{group} =~ s/Tracker/Main/;
			if( $t->{source_select} eq 'soundcard'){
				$t->{source_type} = 'soundcard' ;
				$t->{source_id} = $t->{ch_r}
			}
			elsif( $t->{source_select} eq 'jack'){
				$t->{source_type} = 'jack_client' ;
				$t->{source_id} = $t->{jack_source}
			}
			if( $t->{send_select} eq 'soundcard'){
				$t->{send_type} = 'soundcard' ;
				$t->{send_id} = $t->{ch_m}
			}
			elsif( $t->{send_select} eq 'jack'){
				$t->{send_type} = 'jack_client' ;
				$t->{send_id} = $t->{jack_send}
			}
		}
	}
	if( $project->{save_file_version_number} < 0.9986){
	
		map { 	# store insert without intermediate array

				my $t = $_;

				# use new storage format for inserts
				my $i = $t->{inserts};
				if($i =~ /ARRAY/){ 
					$t->{inserts} = scalar @$i ? $i->[0] : {}  }
				
				# initialize inserts effect_chain_stack and cache_map

				$t->{inserts} //= {};
				$t->{effect_chain_stack} //= [];
				$t->{cache_map} //= {};

				# set class for Mastering tracks

				$t->{class} = '::MasteringTrack' if $t->{group} eq 'Mastering';
				$t->{class} = '::SimpleTrack' if $t->{name} eq 'Master';

				# rename 'ch_count' field to 'width'
				
				$t->{width} = $t->{ch_count};
				delete $t->{ch_count};

				# set Mixdown track width to 2
				
				$t->{width} = 2 if $t->{name} eq 'Mixdown';
				
				# remove obsolete fields
				
				map{ delete $t->{$_} } qw( 
											delay 
											length 
											start_position 
											ch_m 
											ch_r
											source_select 
											jack_source   
											send_select
											jack_send);
		}  @tracks_data;
	}

	# jack_manual is now called jack_port
	if ( $project->{save_file_version_number} <= 1){
		map { $_->{source_type} =~ s/jack_manual/jack_port/ } @tracks_data;
	}
	if ( $project->{save_file_version_number} <= 1.053){ # convert insert data to object
		my $n = 0;
		@inserts_data = ();
		for my $t (@tracks_data){
			my $i = $t->{inserts};
			next unless keys %$i;
			$t->{postfader_insert} = ++$n;
			$i->{class} = '::PostFaderInsert';
			$i->{n} = $n;
			$i->{wet_name} = $t->{name} . "_wet";
			$i->{dry_name} = $t->{name} . "_dry";
			delete $t->{inserts};
			delete $i->{tracks};
			push @inserts_data, $i;
		} 
	}
	if ( $project->{save_file_version_number} <= 1.054){ 

		for my $t (@tracks_data){

			# source_type 'track' is now  'bus'
			$t->{source_type} =~ s/track/bus/;

			# convert 'null' bus to 'Null' (which is eliminated below)
			$t->{group} =~ s/null/Null/;
		}

	}

	if ( $project->{save_file_version_number} <= 1.055){ 

	# get rid of Null bus routing
	
		map{$_->{group}       = 'Main'; 
			$_->{source_type} = 'null';
			$_->{source_id}   = 'null';
		} grep{$_->{group} eq 'Null'} @tracks_data;

	}

	if ( $project->{save_file_version_number} <= 1.064){ 
		map{$_->{version} = $_->{active};
			delete $_->{active}}
			grep{$_->{active}}
			@tracks_data;
	}

	logpkg('debug', "inserts data", sub{yaml_out \@inserts_data});


	# make sure Master has reasonable output settings
	
	map{ if ( ! $_->{send_type}){
				$_->{send_type} = 'soundcard',
				$_->{send_id} = 1
			}
		} grep{$_->{name} eq 'Master'} @tracks_data;

	if ( $project->{save_file_version_number} <= 1.064){ 

		map{ 
			my $default_list = ::IO::default_jack_ports_list($_->{name});

			if( -e join_path(project_root(),$default_list)){
				$_->{source_type} = 'jack_ports_list';
				$_->{source_id} = $default_list;
			} else { 
				$_->{source_type} = 'jack_manual';
				$_->{source_id} = ($_->{target}||$_->{name}).'_in';
			}
		} grep{ $_->{source_type} eq 'jack_port' } @tracks_data;
	}
	
	if ( $project->{save_file_version_number} <= 1.067){ 

		map{ $_->{current_edit} or $_->{current_edit} = {} } @tracks_data;
		map{ 
			delete $_->{active};
			delete $_->{inserts};
			delete $_->{prefader_insert};
			delete $_->{postfader_insert};
			
			# eliminate field is_mix_track
			if ($_->{is_mix_track} ){
				 $_->{source_type} = 'bus';
				 $_->{source_id}   = undef;
			}
			delete $_->{is_mix_track};

 		} @tracks_data;
	}

	if ( $project->{save_file_version_number} <= 1.068){ 

		# initialize version_comment field
		map{ $_->{version_comment} or $_->{version_comment} = {} } @tracks_data;

		# convert existing comments to new format
		map{ 
			while ( my($v,$comment) = each %{$_->{version_comment}} )
			{ 
				$_->{version_comment}{$v} = { user => $comment }
			}
		} grep { $_->{version_comment} } @tracks_data;
	}

	# convert to new MixTrack class
	if ( $project->{save_file_version_number} < 1.069){ 
		map {
		 	$_->{was_class} = $_->{class};
			$_->{class} = $_->{'::MixTrack'};
		} 
		grep { 
			$_->{source_type} eq 'bus' or 
		  	$_->{source_id}   eq 'bus'
		} 
		@tracks_data;
	}

	#  destroy and recreate all buses

	::Bus::initialize();	

	create_system_buses(); 

	# restore user buses
		
	# Main exists, therefore is not created, stored values 
	# are lost.  TODO
	
	map{ my $class = $_->{class}; $class->new( %$_ ) } @bus_data;

	# restore user tracks
	
	my $did_apply = 0;

	# temporary turn on mastering mode to enable
	# recreating mastering tracksk

	my $current_master_mode = $mode->{mastering};
	$mode->{mastering} = 1;

	map{ $_->{latency_op} = delete $_->{latency} if $_->{latency} } @tracks_data;
	map{ 
		my %h = %$_; 
		my $class = $h{class} || "::Track";
		my $track = $class->new( %h );
	} @tracks_data;

	$mode->{mastering} = $current_master_mode;

	# restore inserts
	
	::Insert::initialize();
	
	map{ 
		bless $_, $_->{class}; # bless directly, bypassing constructor
		$::Insert::by_index{$_->{n}} = $_;
	} @inserts_data;

	$ui->create_master_and_mix_tracks();

	$this_track = $tn{$this_track_name} if $this_track_name;
	set_current_bus();

	
	map{ 
		my $n = $_->{n};

		# create gui
		$ui->track_gui($n) unless $n <= 2;

		# restore effects
		
		for my $id (@{$ti{$n}->ops}){
			$did_apply++  # need to show GUI effect window
				unless $id eq $ti{$n}->vol
					or $id eq $ti{$n}->pan;
			
			# does this do anything?
			add_effect({
						chain => $fx->{applied}->{$id}->{chain},
						type => $fx->{applied}->{$id}->{type},
						effect_id => $id,
						owns => $fx->{applied}->{$id}->{owns},
						parent_id => $fx->{applied}->{$id}->{belongs_to},
						});

		}
	} @tracks_data;


	#print "\n---\n", $main->dump;  
	#print "\n---\n", map{$_->dump} ::Track::all();# exit; 
	$did_apply and $ui->manifest;
	logpkg('debug', sub{ join " ", map{ ref $_, $/ } ::Track::all() });


	# restore Alsa mixer settings
	if ( $config->{opts}->{a} ) {
		my $filename = $filename; 
		$filename =~ s/\.yml$//;
		print "restoring ALSA settings\n";
		print qx(alsactl -f $filename.alsa restore);
	}

	# text mode marks 

 	map
    {
		my %h = %$_;
		my $mark = ::Mark->new( %h ) ;
    } 
    grep { (ref $_) =~ /HASH/ } @marks_data;

	$ui->restore_time_marks();
	$ui->paint_mute_buttons;

	# track fades
	
	map{ 
		my %h = %$_; 
		my $fade = ::Fade->new( %h ) ;
	} @fade_data;

	# edits 
	#
	
		# DISABLE EDIT RESTORE FOR CONVERSION XX
	map{ 
		my %h = %$_; 
#		my $edit = ::Edit->new( %h ) ;
	} @edit_data;

	# restore command history
	
	$text->{term}->SetHistory(@{$text->{command_history}})
		if (ref $text->{command_history}) =~ /ARRAY/;

;
} 
sub is_nonempty_hash {
	my $ref = shift;
	return if (ref $ref) !~ /HASH/;
	return (keys %$ref);
}
	 

{
my (@projects, @projects_completed, %state_yml, $errors_encountered);

sub conversion_completed { -e success_file() }
sub success_file { join_path(project_root(), '.conversion_completed') }
sub convert_project_format {

# nama> eval convert_project_format
# 
# That will go over your whole nama projects
# tree and convert old projects to the
# modern format. It also converts the 
# effect chains, separating global
# from project specific. 
# 
# It makes a tar backup of all .yml files
# in the nama project tree at the beginning,
# so I think it's reasonably safe.
# 
# What it's picky about is that it wants
# to actually connect the chain
# setup before saving in the new format.
# (A side benefit is that you know which projects
# have problem.)


	say("conversion previously completed.
To repeat, remove ~/nama/.conversion_completed and try again"), 
		return if conversion_completed();

	archive_state_files();
	convert_effect_chains();
	save_global_effect_chains();
    @projects = map{ /(\w+)$/ } File::Find::Rule->directory()
									->maxdepth(1)
									->mindepth(1)
									->in(project_root());
	map { say } @projects;

	# create hash $state_yml{project}[file1, file2...]
	map {     
		$state_yml{$_}=[];
		my $dir = join_path( project_root(), $_);
		say "project dir: $dir";
		 push @{ $state_yml{$_} }, map{ m{([^/]*?).yml$} } File::Find::Rule->file()
								     					  	->name('*.yml')
															->in($dir);

	} @projects;
	say yaml_out(\%state_yml);
			

	map {

		my @state_files = @{$state_yml{$_}};
		my $project = $_;
		map {

			# exercise all our backward compatibility
			# interrogations
			#my @args = (name => $project, "settings" => $_, nodig => 1);
			my @args = (name => $project, "settings" => $_);

			say "convert_project: @args";
			convert_project(@args);
				# 	- load, 
				# 	- save in new format, 
				# 	- move old state files)

			
		} @state_files;
		

	} @projects;
	return if $errors_encountered;
	open my $fh, '>', success_file();
	close $fh; # touch
	
}
sub archive_state_files {
	my $cmd = q(tar -zcf ).join_path(project_root(), "nama_state.tgz ").
					q(`find ).project_root().q( -name '*.yml'`);
	system $cmd;
}
sub convert_project {
	use autodie qw(:default);
	

	my %args = @_;
	say join " ", "load project", %args;

	load_project(%args);
	die "didn't convert project dir to $args{name}: is ",project_dir() unless project_dir() =~ /$args{name}/;
	say "saving state ", join " ", %args;
	save_state($args{settings});
	my $save_file = join_path(project_dir(),$args{settings}.".json");
	die "didn't create save file ".$save_file unless -e $save_file;
	#copy_state_files($args{name}); 
	
}

sub copy_state_files {

	use autodie qw(:default);
	my $project = shift;
	say "copy state files for $project";

	my $source_dir = join_path(project_root(),$project);
	my $target_dir = join_path($source_dir,"old_state_files_$VERSION");
	mkdir $target_dir;
	map 
	{ 
		my $file = "$_.yml";
		my $from_path = join_path(project_dir(),$file);
		my $to_path   = join_path($target_dir,$file); 

		say "ready for: copy $from_path, $to_path";
		copy $from_path, $to_path;
	} @{ $state_yml{$project} } 
}

sub log_errmsg {
		my $errmsg = shift;
		#warn $errmsg;
		my $log_cmd = join( " ", 
			"echo", qq("$errmsg"), 
			">>",join_path(project_root(),"project_conversion_errors.log")
		);
		say $log_cmd;
		system $log_cmd;
		$errors_encountered++;
}
}
sub convert_effect_chains {

	my ($resolved, $format) = get_newest($file->old_effect_chains);  
	return unless $resolved;
	my $source = read_file($resolved);
	carp("$resolved: empty file"), return unless $source;
	logpkg('debug', "format: $format, source: \n$source");
	my $ref = decode($source, $format);
	logpkg('debug', sub{Dumper $ref});

	# deal with both existing formats
	
	if ( $ref->{VERSION} >= 1.08 )
	{
		assign_singletons( { data => $ref } );
	}
	else {
		assign(
			data => $ref,
			vars => [ qw(%effect_chain)],
			var_map => 1,
			class => '::',
			);
	}

	#rename $resolved, "$resolved.obsolete";

	my @keys = keys %{$fx->{chain}} ;

	#### convert data format

	say "converting effect chains to new format";
	say "keys: @keys";

	my $converted = {};
	map
	{ 
		my $name = $_;
		$converted->{$name}->{ops_list} = $fx->{chain}->{$name}->{ops};
		map 
		{
			$converted->{$name}->{ops_data}->{$_}->{type} 
				= $fx->{chain}->{$name}->{type}->{$_};
			$converted->{$name}->{ops_data}->{$_}->{params} 
				= $fx->{chain}->{$name}->{params}->{$_};
		} @{ $converted->{$name}->{ops_list} };

	} @keys;
	#say "conveted: ",yaml_out $converted;

	#### separate key by type

	my $private_re = qr/^_/;
	my @user_keys = grep{ ! /$private_re/ } @keys;
	my @profile_keys = grep{ /_\w+:\w+/ } @keys;
	my @cache_keys   = grep{ /_\w+\/\w+/} @keys;
	say join " ", "user keys:", @user_keys;
	
	say join " ", "profile keys:", @profile_keys;
	say join " ", "track cache keys:", @cache_keys;

	map 
	{
		
		my $ec = $converted->{$_};
		::EffectChain->new(
			user 		=> 1,
			name		=> $_,
			global 		=> 1,
			ops_list	=> $ec->{ops_list},
			ops_data	=> $ec->{ops_data},	
		);
		
	} @user_keys;

	map 
	{
		my ($profile, $trackname) = /^_(\w+):(\w+)/;
		my $ec = $converted->{$_};
		::EffectChain->new(
			user 		=> 1,
			global 		=> 1,
			profile		=> $profile,
			track_name  => $trackname,
			ops_list	=> $ec->{ops_list},
			ops_data	=> $ec->{ops_data},	
		);
		
	} @profile_keys;

	map 
	{
		my ($project, $trackname, $version) = /^_(\w+)\/(\w+)_(\d+)$/;
		my $ec = $converted->{$_};
		::EffectChain->new(
			project		=> $project,
			track_cache	=> 1,
			track_name  => $trackname,
			track_version => "V$version", 
				# we use "V" prefix in order to
				# distinguish old (arbitrary) index from new
				# entry which indicates a specific track version
			ops_list	=> $ec->{ops_list},
			ops_data	=> $ec->{ops_data},	
		);
		
	} @cache_keys;
}
sub save_converted_effect_chains {
	save_global_effect_chains();
	
	my %by_project;
	my @project_effect_chains = ::EffectChain::find(project => 1);

	map {$by_project{$_->project}++ } @project_effect_chains;
	say yaml_out(\%by_project);
	map { save_project_effect_chains($_); } keys %by_project

}
	
sub save_global_effect_chains {

	@global_effect_chain_data  = map{ $_->as_hash } ::EffectChain::find(global => 1);

	# always save global effect chain data because it contains
	# incrementing counter

	map{ 	my $format = $_ ;
			serialize(
				file => $file->global_effect_chains,
				format => $format,
				vars => \@global_effect_chain_vars, 
				class => '::',
			);
	} $config->serialize_formats;

}

# unneeded after conversion - DEPRECATED
sub save_project_effect_chains {
	my $project = shift; # allow to cross multiple projects
	@project_effect_chain_data = map{ $_->as_hash } ::EffectChain::find(project => $project);
}
sub restore_global_effect_chains {

	logsub("&restore_global_effect_chains");
		my $path =  $file->global_effect_chains;
		my ($resolved, $format) = get_newest($path);  
		carp("$resolved: file not found"), return unless $resolved;
		my $source = read_file($resolved);
		carp("$resolved: empty file"), return unless $source;
		logpkg('debug', "format: $format, source: \n",$source);
		my $ref = decode($source, $format);
		logpkg('debug', sub{Dumper $ref});
		assign(
				data => $ref,
				vars   => \@global_effect_chain_vars, 
				var_map => 1,
				class => '::');
		map { my $fx_chain = ::EffectChain->new(%$_) } @global_effect_chain_data; 
}
sub git_snapshot {
	return unless $config->{use_git};
	return unless state_changed();
	my $commit_message = shift() || "no comment";
	git_commit($commit_message);
}
	
sub git_commit {
	my $commit_message = shift || "empty message";
	$project->{repo}->run( add => $file->git_state_store );
	$project->{repo}->run( commit => '--quiet', '--message', $commit_message);
}
	

sub git_tag { 
	return unless $config->{use_git};
	my ($tag_name,$msg) = @_;
	$project->{repo}->run( tag => $tag_name, '-m', $msg);
}
sub git_checkout {
	return unless $config->{use_git};
	my ($branchname, @args) = @_;
	$project->{repo}->run(checkout => $branchname, @args), 
		return if git_branch_exists($branchname);
	throw("$branchname: branch does not exist. Skipping.");
}
sub git_create_branch {
	return unless $config->{use_git};
	my $branchname = shift;
	# create new branch
	pager("Creating branch $branchname.");
	$project->{repo}->run(checkout => '-b',$branchname)
}

sub state_changed {  
	return unless $config->{use_git};
	$project->{repo}->run("diff", $file->git_state_store());
}

sub git_branch_exists { 
	return unless $config->{use_git};
	my $branchname = shift;
	grep{ $_ eq $branchname } 
		map{ s/^\s+//; s/^\* //; $_}
		$project->{repo}->run("branch");
}

sub current_branch {
	return unless $project->{repo};
	my ($b) = map{ /\* (\S+)/ } grep{ /\*/ } split "\n", $project->{repo}->run('branch');
	$b
}

sub git_branch_display {
	return unless $config->{use_git};
	return unless current_branch();
	"( ".current_branch()." ) "
}

sub autosave {
	my ($original_branch) = current_branch();
	git_checkout(qw{undo --quiet}); 
	save_state();
	git_snapshot();
	git_checkout($original_branch, '--quiet');

}


1;
__END__
