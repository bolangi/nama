# ---------- Persistent State Support -------------


package ::;
use Modern::Perl; no warnings 'uninitialized';
use File::Slurp;
use ::Assign qw(quote_yaml_scalars);

use ::Globals qw(:all);

sub save_state {
	my $filename = shift;
	my $path = $file->state_store($filename);
	$debug2 and print "&save_state\n";
	$project->{save_file_version_number} = $VERSION;

	# some stuff get saved independently of our state file
	
	$debug and print "saving palette\n";
	$ui->save_palette;

	# do nothing more if only Master and Mixdown
	
	if (scalar @::Track::all == 2 ){
		print "No user tracks, skipping...\n";
		return;
	}

	print "\nSaving state as ",
	save_system_state($path), "\n";
	save_effect_chains();

	# store alsa settings

	if ( $config->{opts}->{a} ) {
		my $filename = $filename;
		$filename =~ s/\.yml$//;
		print "storing ALSA settings\n";
		print qx(alsactl -f $filename.alsa store);
	}
}
sub initialize_serialization_arrays {
	@tracks_data = (); # zero based, iterate over these to restore
	@bus_data = (); # 
	@marks_data = ();
	@fade_data = ();
	@inserts_data = ();
	@edit_data = ();
	$text->{command_history} = {};
}

sub save_system_state {

	my $path = shift;

	sync_effect_parameters(); # in case a controller has made a change

	# remove null keys in $fx->{applied} and $fx->{params}
	# would be better to find where they come from
	
	delete $fx->{applied}->{''};
	delete $fx->{params}->{''};

	initialize_serialization_arrays();
	
	# prepare tracks for storage
	
	$this_track_name = $this_track->name;

	$debug and print "copying tracks data\n";

	map { push @tracks_data, $_->hashref } ::Track::all();
	# print "found ", scalar @tracks_data, "tracks\n";

	# delete obsolete fields
	map { my $t = $_;
				map{ delete $t->{$_} } 
					qw(ch_r ch_m source_select send_select jack_source jack_send);
	} @tracks_data;

	$debug and print "copying bus data\n";

	map{ push @bus_data, $_->hashref } ::Bus::all();

	# prepare inserts data for storage
	
	$debug and print "copying inserts data\n";
	
	while (my $k = each %::Insert::by_index ){ 
		push @inserts_data, $::Insert::by_index{$k}->hashref;
	}

	# prepare marks data for storage (new Mark objects)

	$debug and print "copying marks data\n";
	push @marks_data, map{ $_->hashref } ::Mark::all();

	push @fade_data,  map{ $_->hashref } values %::Fade::by_index;

	push @edit_data,  map{ $_->hashref } values %::Edit::by_index;

	# save history -- 50 entries, maximum

	my @history = $text->{term}->GetHistory;
	my %seen;
	$text->{command_history} = [];
	map { push @{$text->{command_history}}, $_ 
			unless $seen{$_}; $seen{$_}++ } @history;
	my $max = scalar @{$text->{command_history}};
	$max = 50 if $max > 50;
	@{$text->{command_history}} = @{$text->{command_history}}[-$max..-1];
	$debug and print "serializing\n";

	my @formats = $path =~ /dump_all/ ? 'yaml' : @{$config->{serialize_formats}};

	map{ 	my $format = $_ ;
			serialize(
				file => $path,
				format => $format,
				vars => \@new_persistent_vars,
				class => '::',
				);

	} @formats;

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
=comment
my $re_eval = q{qr/\.(};
$re_eval .= (join '|', keys %is_legal_suffix)
$re_eval .= q{)$/};
my $suffix_re = eval $re_eval;
=cut

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
	$debug and say yaml_out \@sorted;
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
	$debug2 and print "&restore_state\n";
	my $filename = shift;
	$filename = $file->state_store($filename);

	my( $path, $suffix ) = get_newest($filename);
	
	$debug and print "using file: $path\n";

	carp("$path: file not found"), return if ! -f $path;
	my $source = read_file($path);

	$debug and say "suffix: $suffix";	
	$debug and say "source: $source";
	my $ref = decode($source, $suffix);

	# start marshalling with clean slate	
	
	initialize_serialization_arrays();

	# restore persistent variables

	# get union of old and new lists 
	#my %seen;
	#my @persist_vars = grep{ ! $seen{$_}++ } @persistent_vars, @new_persistent_vars; 
	# handle old-style State files
	# handle serialization arrays (used by new-style State files as well)
	# handle some extra vars (ditto)
	
	assign(
				data => $ref,
				vars   => \@persistent_vars,
				var_map => 1,
				class => '::');
	
	# correctly restore singletons
	
	if ( exists $ref->{project}->{save_file_version_number})
	{
		my $args = { data => $ref };
		assign_singletons( $args );
	#	assign_serialization_arrays( $args );
	#	assign_pronouns( $args);
	}

	# remove null keyed entry from $fx->{applied},  $fx->{params}

	delete $fx->{applied}->{''};
	delete $fx->{params}->{''};

	restore_effect_chains();

	##  print yaml_out \@groups_data; 
	
	# backward compatibility fixes for older projects

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

	$debug and print "inserts data", yaml_out \@inserts_data;


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

	map{ 
		my %h = %$_; 
		my $class = $h{class} || "::Track";
		my $track = $class->new( %h );
	} @tracks_data;

	$mode->{mastering} = $current_master_mode;

	# restore inserts
	
	::Insert::initialize();
	
	map{ 
		bless $_, $_->{class};
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
			
			add_effect({
						chain => $fx->{applied}->{$id}->{chain},
						type => $fx->{applied}->{$id}->{type},
						cop_id => $id,
						parent_id => $fx->{applied}->{$id}->{belongs_to},
						});

		}
	} @tracks_data;


	#print "\n---\n", $main->dump;  
	#print "\n---\n", map{$_->dump} ::Track::all();# exit; 
	$did_apply and $ui->manifest;
	$debug and print join " ", 
		(map{ ref $_, $/ } ::Track::all()), $/;


	# restore Alsa mixer settings
	if ( $config->{opts}->{a} ) {
		my $filename = $filename; 
		$filename =~ s/\.yml$//;
		print "restoring ALSA settings\n";
		print qx(alsactl -f $filename.alsa restore);
	}

	# text mode marks 
		
	map{ 
		my %h = %$_; 
		my $mark = ::Mark->new( %h ) ;
	} @marks_data;


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
	
	$text->{term}->SetHistory(@{$text->{command_history}});
} 

# Effect Chains
#
# we have two type of effect chains
# + global effect chains - usually user defined, available to all projects
# + system generated effect chains, per project

our @effect_chains_data;
our @global_effect_chain_vars  = qw(@effect_chains_data $::EffectChain::n );
our @project_effect_chain_vars = qw(@effect_chains_data);


sub convert_effect_chains {

	my ($resolved, $format) = get_newest($file->old_effect_chains);  
	return unless $resolved;
	my $source = read_file($resolved);
	carp("$resolved: empty file"), return unless $source;
	$debug and say "format: $format, source: \n",$source;
	my $ref = decode($source, $format);
	$debug and print Dumper $ref;

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

	rename $resolved, "$resolved.obsolete";

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
	say "conveted: ",yaml_out $converted;

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
	
sub save_effect_chains { 
	save_global_effect_chains();
	save_project_effect_chains(project_dir());
}
sub save_global_effect_chains {

	@effect_chains_data  = map{ $_->hashref } ::EffectChain::find(global => 1);

	# always save global effect chain data because it contains
	# incrementing counter
	
	serialize(
		file => $file->global_effect_chains,
		format => 'yaml',
		vars => \@global_effect_chain_vars,
		class => '::',
	);
}

sub save_project_effect_chains {
	my $project = shift; # allow to cross multiple projects
	@effect_chains_data = map{ $_->hashref } ::EffectChain::find(project => $project);

	if (@effect_chains_data)
	{
		serialize(
			file => join_path(
				project_root(), 
				$project, 
				$file->{project_effect_chains}->[0], # grab filename only
			),
			format => 'yaml',
			vars => \@project_effect_chain_vars,
			class => '::',
		);
	}
	
}

sub restore_effect_chains {

	$debug2 and say "&restore_effect_chains";
	map{ 
		my $path = $_;
		my ($resolved, $format) = get_newest($path);  
		carp("$resolved: file not found"), return unless $resolved;
		my $source = read_file($resolved);
		carp("$resolved: empty file"), return unless $source;
		$debug and say "format: $format, source: \n",$source;
		my $ref = decode($source, $format);
		$debug and print Dumper $ref;
		assign(
				data => $ref,
				vars   => \@global_effect_chain_vars, # for project, too
				var_map => 1,
				class => '::');
		map { my $fx_chain = ::EffectChain->new(%$_) } @effect_chains_data; 
		
	} ($file->global_effect_chains, $file->project_effect_chains);
}

sub autosave_files {
	sort File::Find::Rule  ->file()
						->name('State-autosave-*')
							->maxdepth(1)
						 	->in( project_dir());
}
sub files_are_identical {
	my ($filenamea,$filenameb) = @_;
	my $a = read_file($filenamea);
	my $b = read_file($filenameb);
	$a eq $b
}

1;
__END__
