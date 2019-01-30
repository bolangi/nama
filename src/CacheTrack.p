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
# complete_caching_ref
# output_wav
# orig_volume
# orig_pan

sub cache_track { # launch subparts if conditions are met
	logsub('&cache_track');
	my $args = {};
	(my $track, $args->{additional_time}) = @_;
	local $this_track;
	throw("Set track to MON or PLAY"), return if $track->rw eq OFF 
											and $track->is_mixer 
											and $track->targets;
	$args->{track} = $track;
	$args->{additional_time} //= 0;
	$args->{is_mixing}++ if $track->is_mixing;
	$args->{original_version} = $track->is_mixing ? 0 : $args->{track}->playback_version;
	$args->{cached_version} = $args->{track}->last + 1;
	
	$args->{track_rw} = $track->{rw};
	$args->{main_rw} = $tn{Main}->{rw};
	$tn{Main}->set( rw => OFF);
	$track->set( rw => REC);	
	pagers($track->name. ": preparing to cache ".  ($track->is_mixing ? 'a bus' : 'an ordinary track'));
	
	throw($track->name. ": nothing to cache!  Skipping."), return 
		unless $track->is_mixing 
				or $track->user_ops 
				or $track->has_insert
				or $track->is_region;

	if($track->is_mixing)
	{ generate_cache_graph_bus($args) }
	else
	{ generate_cache_graph($args) }
	
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

sub deactivate_vol_pan {
	my $args = shift;
	unity($args->{track}, 'save_old_vol');
	pan_check($args->{track}, 50);
}
sub reactivate_vol_pan {
	my $args = shift;
	pan_back($args->{track});
	vol_back($args->{track});
}
sub generate_cache_graph_bus {
	my $args = shift;
 	my $g = ::ChainSetup::initialize();
	$args->{graph} = $g;
	my $track = $args->{track};
		
	# set WAV output format
	
	$args->{complete_caching_ref} = \&update_cache_map_bus;
	
	map{ $_->apply($g) } grep{ (ref $_) =~ /SubBus/ } ::Bus::all();

	$g->set_vertex_attributes(
		$track->name, 
		{ format => signal_format($config->{cache_to_disk_format},$track->width),
			version => ($args->{track_result_version}),
		}
	); 

# 	grep { $_->name ne 'Main' } 

}

sub generate_cache_graph {
	logsub('&generate_cache_graph');
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
	$args->{complete_caching_ref} = \&update_cache_map;

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
	logsub('&process_cache_graph');
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
	logsub("&cache_engine_run");
	my $args = shift;
	connect_transport()
		or throw("Couldn't connect engine! Aborting."), return;

	$args->{processing_time} = $setup->{audio_length} + $args->{additional_time};

	pagers($args->{track}->name.": processing time: ". d2($args->{processing_time}). " seconds");
	pagers("Starting cache operation. Please wait.");
	
	revise_prompt(" "); 

	# we try to set processing time this way
	ecasound_iam("cs-set-length $args->{processing_time}"); 

	ecasound_iam("start");

	# ensure that engine stops at completion time
	$setup->{cache_track_args} = $args;
 	$project->{events}->{poll_engine} = AE::timer(1, 0.5, \&poll_cache_progress);

	# complete_caching() contains the remainder of the caching code.
	# It is triggered by stop_polling_cache_progress()
}
sub complete_caching {
	logsub('&complete_caching');
	my $args = shift;	
	my $name = $args->{track}->name;
	my @files = grep{/$name/} new_files_were_recorded();
	if (@files ){ 
		
		$args->{complete_caching_ref}->($args) if defined $args->{complete_caching_ref};
		post_cache_processing($args);

	} else { throw("track cache operation failed!") }
	undef $setup->{cache_track_args};
}
sub update_cache_map {
	logsub('&update_cache_map');
	my $args = shift;
		logpkg('debug', "updating track cache_map");
		logpkg('debug', "current track cache entries:",
			sub {
				join "\n","cache map", 
				map{($_->dump)} ::EffectChain::find(track_cache => 1)
			});
		my @inserts_list = $args->{track}->get_inserts;

		# include all ops, include vol/pan operators 
		# which serve as placeholders, won't overwrite
		# the track's current vol/pan operators

		my $track = $args->{track};
		 
		my @ops_list = @{$track->ops};
		my @ops_remove_list = $track->user_ops;
		
		if ( @inserts_list or @ops_remove_list or $track->is_region )
		{
			my %args = 
			(
				track_cache => 1,
				track_name	=> $track->name,
				track_version_original => $args->{original_version},
				track_version_result => $args->{cached_version},
				project => 1,
				system => 1,
				ops_list => \@ops_list,
				inserts_data => \@inserts_list,
			);
			#	is_mixing => $track->is_mixing,
			$args{region} = [ $track->region_start, $track->region_end ] if $track->is_region;
			$args{fade_data} = [ map  { $_->as_hash } $track->fades ];
			$args{track_target_original} = $track->target if $track->target; 
			# late, because this changes after removing target field
			map{ delete $track->{$_} } qw(target);
			# update track settings
			my $ec = ::EffectChain->new( %args );
			map{ $_->remove        } $track->fades;
			map{ remove_effect($_) } @ops_remove_list;
			map{ $_->remove        } @inserts_list;
			map{ delete $track->{$_} } qw( region_start region_end target );

		pagers(qq(Saving effects for cached track "). $track->name. '".');
		pagers(qq('uncache' will restore effects and set version $args->{original_version}\n));
		}
}
sub update_cache_map_bus {
	my $args = shift;
	my $track = $args->{track};
	my $filename = $track->targets->{$args->{cached_version}};

	# system version comment with git tag
	
	my $tagname = my $msg = join " ","bus", $track->source_id, "cached as", $filename;
	$tagname =~ s/ /-/g;
	try{ git(tag => $tagname, '-a','-m',$msg) };
	$track->add_system_version_comment($args->{cached_version}, $msg);
	pagers($msg); 
	pagers(qq(To return this track to the state prior to caching,
simply say '$track->{name} mon' The state of the project is saved 
and available through the tag $tagname));
}

sub post_cache_processing {
	my $args = shift;
		$args->{track}->{rw} = $args->{track_rw};
		$tn{Main}->{rw} = $args->{main_rw}; 
		$args->{track}->set( rw => PLAY);
		$ui->global_version_buttons(); # recreate
		$ui->refresh();
		revise_prompt("default"); 
}
sub poll_cache_progress {
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

	pagers("Done.");
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
		throw($track->name, ": cannot uncache unless track is set to PLAY"), return;
	my $version = $track->playback_version;
	my ($ec) = is_cached($track, $version);
	if (not defined $ec)
	{
		if ($track->source_type eq 'bus')
		{
			$track->set(rw => MON);
			pager("Enabling bus $track->{group} by setting mix track $track->{name} to MON");
			return
		}

		else{ throw($track->name, ": version $version is not cached"), return }
	}
	$track->user_ops and 
		throw($track->name, ": cannot uncache while user effects are present\n",
			"You must delete them before you can uncache this WAV version."), return;
	$track->is_region and 
		throw($track->name, ": cannot uncache while region is set for this track\n",
			"Remove it and try again."), return;
# 	$ec->inserts and $track->inserts and throw($track->name,
# 	": cannot uncache inserts because an insert is already set for this track\n",
# 	"Remove it and try again."), return;

	$ec->add($track);
	# replace track's effect list with ours
	$track->{ops} = dclone($ec->ops_list);
	# applying the the effect chain doesn't set the version or target
	# so we do it here
	$track->set(version => $ec->track_version_original);
    $track->set(target => $ec->track_target_original) if $ec->track_target_original;

	pager($track->name, ": setting uncached version ", $track->version, $/);
	pager($track->name, ": setting original region bounded by marks ", 
		$track->region_start, " and ", $track->region_end, $/)
		if $track->is_region;

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
