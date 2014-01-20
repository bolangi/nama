# ---------- Persistent State Support -------------


package ::;
use File::Copy;
use Modern::Perl; no warnings 'uninitialized';

sub save_state {
	logsub("&save_state");
	my $filename = shift;
	if ($filename)
	{

		# remove extension if present
		
		$filename =~ s/\.json//;

		# append filename if warranted
		
		$filename = 
				$filename =~ m{/} 	
									? $filename	# as-is if input contains slashes
									: join_path(project_dir(),$filename) 
	}
	my $path = $filename || $file->state_store();
	$project->{save_file_version_number} = $VERSION;

	# store playback position, if possible
	$project->{playback_position} = eval_iam("getpos") if valid_engine_setup();

	# some stuff get saved independently of our state file
	
	logpkg('debug', "saving palette");
	$ui->save_palette;

	# do nothing more if only Master and Mixdown
	
	if (scalar @::Track::all == 2 ){
		throw("No user tracks, skipping...");
		return;
	}
	logpkg('debug',"Saving state as ", $path);
	save_system_state($path);
	save_global_effect_chains();

	# store alsa settings

	if ( $config->{opts}->{a} ) {
		my $filename = $filename;
		$filename =~ s/\.yml$//;
		pager("storing ALSA settings\n");
		pager(qx(alsactl -f $filename.alsa store))
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
	
	$this_track_name = $this_track->name if $this_track;

	logpkg('debug', "copying tracks data");

	map { push @tracks_data, $_->as_hash } ::Track::all();

	# print "found ", scalar @tracks_data, "tracks\n";

	# delete obsolete fields
	map { my $t = $_;
				map{ delete $t->{$_} } 
					qw(ch_r ch_m source_select send_select jack_source jack_send);
	} @tracks_data;

	logpkg('debug', "copying bus data");

	@bus_data = map{ $_->as_hash } sort { $a->name cmp $b->name} ::Bus::all();


	my $by_n = sub { $a->{n} <=> $b->{n} };

	# prepare inserts data for storage
	
	logpkg('debug', "copying inserts data");
	
	@inserts_data = sort $by_n map{ $_->as_hash } values %::Insert::by_index;

	# prepare marks data for storage (new Mark objects)

	logpkg('debug', "copying marks data");


	@marks_data = sort {$a->{time} <=> $b->{time} } map{ $_->as_hash } ::Mark::all();

	@fade_data = sort $by_n map{ $_->as_hash } values %::Fade::by_index;

	@edit_data = sort $by_n map{ $_->as_hash } values %::Edit::by_index;

	@project_effect_chain_data = sort $by_n map { $_->as_hash } 
		::EffectChain::find(project => 1);

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
				vars => \@tracked_vars,
				class => '::',
				);

	} @formats;

	serialize(
		file => $file->untracked_state_store,
		format => 'json',
		vars => \@persistent_vars,
		class => '::',
	);	

	"$path.json";
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
	logpkg('debug', sub{json_out \@sorted});
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

sub restore_state_from_file {
	logsub("&restore_state_from_file");
	my $filename = shift;
	$filename =~ s/\.json$//;
	$filename = join_path(project_dir(), $filename) 
		if $filename and not $filename =~ m(/);
	$filename ||= $file->state_store();

	my ($ref, $path, $source, $suffix); 

	# get state file, newest if more than one
	# with same name, differing extensions
	# i.e. State.json and State.yml
	initialize_marshalling_arrays();

	# restore from default filenames	
	
	( $path, $suffix ) = get_newest($file->untracked_state_store);
	if ($path)
	{
		$source = read_file($path);

		$ref = decode($source, $suffix);
		assign(
				data	=> $ref,	
				vars   	=> \@persistent_vars,
				class 	=> '::');
		assign_singletons( { data => $ref });
	}
	
	( $path, $suffix ) = get_newest($filename);
	if ($path)
	{
		$source = read_file($path);
		$ref = decode($source, $suffix);

		assign(
					data => $ref,
					vars   => \@tracked_vars,
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


	####### Backward Compatibility ########

	if ( $project->{save_file_version_number} lt "1.100"){ 
		map{ ::EffectChain::move_attributes($_) } 
			(@project_effect_chain_data, @global_effect_chain_data)
	}
	if ( $project->{save_file_version_number} lt 1.105){ 
		map{ $_->{class} = 'Audio::Nama::BoostTrack' } 
		grep{ $_->{name} eq 'Boost' } @tracks_data;
	}
	if ( $project->{save_file_version_number} lt "1.109"){ 
		map
		{ 	if ($_->{class} eq '::MixTrack') { 
				$_->{is_mix_track}++;
				$_->{class} = $_->{was_class};
				$_->{class} = '::Track';
		  	}
		  	delete $_->{was_class};
		} @tracks_data;
		map
		{    if($_->{class} eq '::MasterBus') {
				$_->{class} = '::SubBus';
			 }
		} @bus_data;

	}
	if ( $project->{save_file_version_number} lt "1.111"){ 
		map
		{
			convert_rw($_);
			delete $_->{effect_chain_stack} ;
            delete $_->{rec_defeat};
            delete $_->{was_class};
			delete $_->{is_mix_track};
			$_->{rw} = 'MON' if $_->{name} eq 'Master';
		} @tracks_data;
		map
		{
			$_->{rw} = 'MON' if $_->{rw} eq 'REC'
		} @bus_data;
	}
	#######################################
sub convert_rw {
	my $h = shift;
	$h->{rw} = 'MON', return if $h->{rw} eq 'REC' and ($h->{rec_defeat} or $h->{is_mix_track});
	$h->{rw} = 'PLAY', return if $h->{rw} eq 'MON';
}
	#  destroy and recreate all buses

	::Bus::initialize();	

	# restore user buses
		
	map{ my $class = $_->{class}; $class->new( %$_ ) } @bus_data;

	create_system_buses();  # any that are missing

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

	$ui->create_master_and_mix_tracks();

	$this_track = $tn{$this_track_name}, set_current_bus() if $this_track_name;
	
	#print "\n---\n", $main->dump;  
	#print "\n---\n", map{$_->dump} ::Track::all();# exit; 
	$did_apply and $ui->manifest;
	logpkg('debug', sub{ join " ", map{ ref $_, $/ } ::Track::all() });


	# restore Alsa mixer settings
	if ( $config->{opts}->{a} ) {
		my $filename = $filename; 
		$filename =~ s/\.yml$//;
		pager("restoring ALSA settings\n");
		pager(qx(alsactl -f $filename.alsa restore));
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
	
	map{ 
		my %h = %$_; 
		my $edit = ::Edit->new( %h ) ;
	} @edit_data;

	# restore command history
	
	$text->{term}->SetHistory(@{$text->{command_history}})
		if (ref $text->{command_history}) =~ /ARRAY/;

;
	# restore effect chains and profiles
	
	%::EffectChain::by_index = ();
	#say "Project Effect Chain Data\n", json_out( \@project_effect_chain_data);
 	map { my $fx_chain = ::EffectChain->new(%$_) } 
		(@project_effect_chain_data, @global_effect_chain_data)
} 
sub is_nonempty_hash {
	my $ref = shift;
	return if (ref $ref) !~ /HASH/;
	return (keys %$ref);
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
sub restore_global_effect_chains {

	logsub("&restore_global_effect_chains");
		my $path =  $file->global_effect_chains;
		my ($resolved, $format) = get_newest($path);  
		throw("$resolved: file not found"), return unless $resolved;
		my $source = read_file($resolved);
		throw("$resolved: empty file"), return unless $source;
		logpkg('debug', "format: $format, source: \n",$source);
		my $ref = decode($source, $format);
		logpkg('debug', sub{Dumper $ref});
		assign(
				data => $ref,
				vars   => \@global_effect_chain_vars, 
				class => '::');
		assign_singletons({ data => $ref });
}
1;

__END__
