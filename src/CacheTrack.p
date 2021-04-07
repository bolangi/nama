# -------- CacheTrack ------
package ::;
use Modern::Perl;
use Storable 'dclone';
use Try::Tiny;
use ::Globals qw(:all);

# The $args hashref passed among the subroutines in this file
# has these fields:

# track
# additional_time
# processing_time
# original_version
# output_wav
# orig_volume
# orig_pan
# bus - we are caching a bus

sub cache_track { # launch subparts if conditions are met
	logsub((caller(0))[3]);
	my $args = {}; # to pass params to routines involved in caching
	(my $track, $args->{additional_time}) = @_;

	my $bus = $track->is_mixing;
	my $obj; # track or bus
	my $name = $track->name;
	if( $track->off ){
		my $bus = $track->is_mixer && ! $track->playback_version;
		my $status = $bus ? MON : PLAY;
		throw(qq(Cannot cache track "$name" with status OFF. Set to $status and try again)); 
		return;
	}
	
	local $this_track;

	$args->{track} = $track;
	$args->{bus} = $bus;
	$args->{additional_time} //= 0;
	$args->{original_version} = $bus ? 0 : $track->playback_version;
	$args->{cached_version} = $track->last + 1;
	$args->{track_rw} = $track->rw;
	$args->{main_rw} = $tn{Main}->rw;

	$tn{Main}->set( rw => OFF);
	$track->set( rw => REC);	

	my @to_cache = cachable($track) or throw("Nothing to cache, skipping."), return;

	$obj = $bus ? 'bus' : 'track';
	pager("$name: Preparing to cache $obj with ",join ', ',@to_cache);
	if($bus)
	{ generate_cache_bus_graph($args) }
	else
	{ generate_cache_track_graph($args) }
	
	my $result = process_cache_graph($g);
	if ( $result )
	{ 
		pager("generated graph");
		deactivate_vol_pan($args);
		cache_engine_run($args);
		reactivate_vol_pan($args);
		return $args->{output_wav}
	}
	else
	{ 
		throw("Empty routing graph. Aborting."); 
		return;
	}

}
sub cachable {
	my $track = shift;
	my @cached;
	push @cached, 'bus' if $track->is_mixer;
	push @cached, 'region' if $track->is_region;
	push @cached, 'effects' if $track->user_ops;
	push @cached, 'insert' if $track->has_insert;
	push @cached, 'fades' if $track->fades;
	# push @cached, 'edits' if $track->edits; # TODO
	@cached;
}

sub deactivate_vol_pan {
	my $args = shift;
	unity($args->{track}, 'save_old_vol');
	pan_set($args->{track}, 50);
}
sub reactivate_vol_pan {
	my $args = shift;
	pan_back($args->{track});
	vol_back($args->{track});
}
sub generate_cache_bus_graph {
	my $args = shift;
 	my $g = ::ChainSetup::initialize();
	$args->{graph} = $g;
	my $track = $args->{track};
		
	map{ $_->apply($g) } grep{ (ref $_) =~ /SubBus/ } ::Bus::all();

	# set WAV output format
	$g->set_vertex_attributes(
		$track->name, 
		{ format => signal_format($config->{cache_to_disk_format},$track->width),
			version => ($args->{track_result_version}),
		}
	); 
}

sub generate_cache_track_graph {
	logsub((caller(0))[3]);
	my $args = shift;
 	my $g = ::ChainSetup::initialize();
	$args->{graph} = $g;
	
	#   We route the signal thusly:
	#
	#   Target track --> CacheRecTrack --> wav_out
	#
	#   CacheRecTrack slaves to target target
	#     - same name
	#     - increments track version by one
	
	my $cooked = ::CacheRecTrack->new(
		name   => $args->{track}->name . '_cooked',
		group  => 'Temp',
		target => $args->{track}->name,
		hide   => 1,
	);

	$g->add_path($args->{track}->name, $cooked->name, 'wav_out');

	# save the output file name to return later
	
	$args->{output_wav} = $cooked->current_wav;

	# set WAV output format
	
	my $to_name = $args->{track}->name .  '_' .  $args->{cached_version} . '.wav';
	my $to_path = join_path($args->{track}->dir, $to_name);
	$g->set_vertex_attributes(
		$cooked->name, 
		{ format => signal_format($config->{cache_to_disk_format},$cooked->width),
			full_version => $to_path,
		}
	); 
		# set the input path
		$g->add_path('wav_in',$args->{track}->name);
		logpkg('debug', "The graph after setting input path:\n$g");
	
	my $from_name = $args->{track}->name .  '_' . $args->{original_version} . '.wav';
	my $from_path = join_path($args->{track}->dir, $from_name);

	$g->set_vertex_attributes(
		$args->{track}->name,
		{ full_path => $from_path }
	);

}

sub process_cache_graph {
	logsub((caller(0))[3]);
	my $g = shift;
	logpkg('debug', "The graph after bus routing:\n$g");
	::ChainSetup::prune_graph();
	logpkg('debug', "The graph after pruning:\n$g");
	::Graph::expand_graph($g); 
	logpkg('debug', "The graph after adding loop devices:\n$g");
	::Graph::add_inserts($g);
	logpkg('debug', "The graph with inserts:\n$g");
	my $success = ::ChainSetup::process_routing_graph();
	if ($success) 
	{ 
		::ChainSetup::write_chains();
		::ChainSetup::remove_temporary_tracks();
	}
	$success
}

sub cache_engine_run {
	logsub((caller(0))[3]);
	my $args = shift;
	connect_transport()
		or throw("Couldn't connect engine! Aborting."), return;

	$args->{processing_time} = $setup->{audio_length} + $args->{additional_time};

	pager($args->{track}->name.": processing time: ". d2($args->{processing_time}). " seconds");
	pager("Starting cache operation. Please wait.");
	
	revise_prompt(" "); 

	# we try to set processing time this way
	ecasound_iam("cs-set-length $args->{processing_time}"); 

	ecasound_iam("start");

	# ensure that engine stops at completion time
	$setup->{cache_track_args} = $args;
 	$project->{events}->{poll_engine} = AE::timer(1, 0.5, \&poll_progress);
}
sub complete_caching {
	logsub((caller(0))[3]);
	my $args = shift;	
	my $name = $args->{track}->name;
	my @files = grep{/$name/} new_files_were_recorded();
	if (@files ){ 
		
		update_cache_map($args);	
		caching_cleanup($args);

	} else { throw("track cache operation failed!") }
	undef $setup->{cache_track_args};
}
sub update_cache_map {
	logsub((caller(0))[3]);
	my $args = shift;
	logpkg('debug', "updating track cache_map");
	logpkg('debug', "current track cache entries:",
		sub {
			join "\n","cache map", 
			map{($_->dump)} ::EffectChain::find(track_cache => 1)
		});

	my $track = $args->{track};

	my @inserts = $track->get_inserts;
	my @all_ops = @{$track->ops};
	my @ops_to_remove = $track->user_ops;
	
	my %constructor_args = 
	(
		track_cache => 1,
		track_name	=> $track->name,
		track_version_original => $args->{original_version},
		track_version_result => $args->{cached_version},
		project => 1,
		system => 1,
		ops_list => \@all_ops,
		inserts_data => \@inserts,
	);
	$constructor_args{region} = [ $track->region_start, $track->region_end ] if $track->is_region;
	$constructor_args{fade_data} = [ map  { $_->as_hash } $track->fades ]
		if $track->fades;
	$constructor_args{track_target_original} = $track->target if $track->target; 
	#say "constructor args: ",Dumper \%constructor_args;
	my $ec = ::EffectChain->new( %constructor_args );

	# update track settings
	map{ delete $track->{$_} } qw(target);
	map{ $_->remove        } $track->fades;
	map{ remove_effect($_) } @ops_to_remove;
	map{ $_->remove        } @inserts;
	map{ delete $track->{$_} } qw( region_start region_end target );
	my $obj = $args->{bus} ? 'bus' : 'track';

	my $act = $args->{bus} ? 'reactivate bus' 
								: "restore version $args->{original_version}";
	pager(qq(Saving attributes for cached $obj "$track->name"));

	pager(qq(The 'uncache' command on this track will $act, 
and restore any effects, fades, inserts or region definition.));

	my $filename = $track->targets->{$args->{cached_version}};

	# system version comment with git tag
	
	my $tagname = my $msg = join " ","bus", $track->source_id, "cached as", $filename;
	$tagname =~ s/ /-/g;
	try{ git(tag => $tagname, '-a','-m',$msg) };
	$track->add_system_version_comment($args->{cached_version}, $msg);
	pager($msg); 
}

sub caching_cleanup {
	my $args = shift;
		$args->{track}->set( rw => $args->{track_rw});
		$tn{Main}->set(rw => MON);
		$args->{track}->set( rw => PLAY);
		$ui->global_version_buttons(); # recreate
		$ui->refresh();
		revise_prompt("default"); 
}
sub poll_progress {
	my $args = $setup->{cache_track_args};
	print ".";
	my $status = ecasound_iam('engine-status'); 
	my $here   = ecasound_iam("getpos");
	update_clock_display();
	logpkg('debug', "engine time:   ". d2($here));
	logpkg('debug', "engine status:  $status");

	return unless 
		   $status =~ /finished|error|stopped/ 
		or $here > $args->{processing_time};

	pager("Done.");
	logpkg('debug', engine_status(current_position(),2,1));
	#revise_prompt();
	stop_polling_cache_progress($args);
}
sub stop_polling_cache_progress {
	my $args = shift;
	$project->{events}->{poll_engine} = undef; 
	$ui->reset_engine_mode_color_display();
	complete_caching($args);

}

sub uncache_track { 
	my $track = shift;
	local $this_track;
	$track->play or 
		throw($track->name, ": cannot uncache unless track is set to PLAY, skipping."), return;
	my $version = $track->playback_version;
	my ($ec) = is_cached($track, $version);
	defined $ec or throw($track->name, ": version $version is not cached, skipping"), return;
	my @in_the_way = grep {$_ !~ 'bus'} cachable($track);
	@in_the_way and
		throw("track $track->{name}, has @in_the_way.
You must remove them before you can uncache this version."), return;
		
	$ec->add($track);
	if ($track->is_mixer and not $ec->track_version_original) {
		$track->set(rw => MON);
		pager("Enabling bus $track->{group} by setting mix track $track->{name} to MON");
	} else {
		my $v = $ec->original_version;
		$track->set( version => $v);
		pager("Selecting track $track->{name} version $v");
	}
}
sub is_cached {
	my ($track, $version) = @_;
	my @results = ::EffectChain::find(
		project 				=> 1, 
		track_cache 			=> 1,
		track_name 				=> $track->name, 
		track_version_result 	=> $version,
	);
	scalar @results > 1 
		and warn ("more than one EffectChain matching query!, found", 
			map{ json_out($_->as_hash) } @results);
	$results[-1]
}
1;
__END__
