# -------- TrackCache ------

package ::;
use Modern::Perl;
use ::Globals qw(:all);

# some common variables for cache_track and merge_track
# related routines

{ # begin shared lexicals for cache_track and merge_edits

	my ($track, 
		$additional_time, 
		$processing_time, 
		$orig_version, 
		$complete_caching_ref,
		$output_wav);

sub cache_track { # launch subparts if conditions are met
	($track, $additional_time) = @_;
	say $track->name, ": preparing to cache.";
	
	# abort if sub-bus mix track and bus is OFF 
	if( my $bus = $bn{$track->name}
		and $track->rec_status eq 'REC' 
	 ){ 
		$bus->rw eq 'OFF' and say(
			$bus->name, ": status is OFF. Aborting."), return;

	# check conditions for normal track
	} else { 
		$track->rec_status eq 'MON' or say(
			$track->name, ": track caching requires MON status. Aborting."), return;
	}
	say($track->name, ": no effects to cache!  Skipping."), return 
		unless 	$track->fancy_ops 
				or $track->has_insert
				or $bn{$track->name};

	prepare_to_cache()
		or say("Empty routing graph. Aborting."), return;
	cache_engine_run();
	$output_wav

}

sub prepare_to_cache {
	# uses shared lexicals
	
 	my $g = ::ChainSetup::initialize();
	$orig_version = $track->monitor_version;

	# create a temporary track to represent the output file
	
	my $cooked_name = $track->name . '_cooked';
	my $cooked = ::CacheRecTrack->new(
		name => $cooked_name,
		group => 'Temp',
		target => $track->name,
		hide => 1,
	);
	$output_wav = $cooked->current_wav;

	# connect the temporary track's output path
	
	$g->add_path($track->name, $cooked->name, 'wav_out');

	# set the correct output parameters in the graph
	
	$g->set_vertex_attributes(
		$cooked->name, 
		{ format => signal_format($config->{cache_to_disk_format},$cooked->width),
		}
	); 

	# Case 1: Caching a standard track
	
	if($track->rec_status eq 'MON')
	{
		# set the input path
		$g->add_path('wav_in',$track->name);
		logpkg('debug', "The graph after setting input path:\n$g");

		# update cache map to enable 'uncache' command TODO:
		# new design
		$complete_caching_ref = \&update_cache_map;
	}

	# Case 2: Caching a sub-bus mix track

	elsif($track->rec_status eq 'REC'){

		# apply all sub-buses (unneeded ones will be pruned)
		map{ $_->apply($g) } grep{ (ref $_) =~ /Sub/ } ::Bus::all()
	}

	logpkg('debug', "The graph after bus routing:\n$g");
	::ChainSetup::prune_graph();
	logpkg('debug', "The graph after pruning:\n$g");
	::Graph::expand_graph($g); 
	logpkg('debug', "The graph after adding loop devices:\n$g");
	::Graph::add_inserts($g);
	logpkg('debug', "The graph with inserts:\n$g");
	my $success = ::ChainSetup::process_routing_graph();
	::ChainSetup::write_chains();
	::ChainSetup::remove_temporary_tracks();
	$success
}
sub cache_engine_run { # uses shared lexicals

	connect_transport('quiet')
		or say("Couldn't connect engine! Aborting."), return;
	$processing_time = $setup->{audio_length} + $additional_time;

	say $/,$track->name,": processing time: ". d2($processing_time). " seconds";
	print "Starting cache operation. Please wait.";
	
	revise_prompt(" "); 

	# we try to set processing time this way
	eval_iam("cs-set-length $processing_time"); 

	eval_iam("start");

	# ensure that engine stops at completion time
 	$engine->{events}->{poll_engine} = AE::timer(1, 0.5, \&poll_cache_progress);

	# complete_caching() contains the remainder of the caching code.
	# It is triggered by stop_polling_cache_progress()
}
sub complete_caching {
	# uses shared lexicals
	
	my $name = $track->name;
	my @files = grep{/$name/} new_files_were_recorded();
	if (@files ){ 
		
		# update cache map 
		&$complete_caching_ref if defined $complete_caching_ref;
		post_cache_processing();

	} else { say "track cache operation failed!"; }
}
sub update_cache_map {

		logpkg('debug', "updating track cache_map");
		#logpkg('debug',sub{"cache map\n".yaml_out($track->cache_map)});
		my $cache_map = $track->cache_map;
		my @inserts_list = ::Insert::get_inserts($track->name);
		my @ops_list = $track->fancy_ops;
		if ( @inserts_list or @ops_list )
		{
			my $ec = ::EffectChain->new(
				track_cache => 1,
				track_name	=> $track->name,
				track_version_original => $orig_version,
				track_version_result => $track->last,
				project => 1,
				system => 1,
				ops_list => \@ops_list,
				inserts_data => \@inserts_list,
			);
			map{ remove_effect($_) } @ops_list;
			map{ $_->remove        } @inserts_list;

			$cache_map->{$track->last} = { 
				original 			=> $orig_version,
				effect_chain	=> $ec->n
			};
		}
		#say "cache map",yaml_out($track->cache_map);
		say qq(Saving effects for cached track "), $track->name, '".';
		say qq('uncache' will restore effects and set version $orig_version\n);
}

sub post_cache_processing {

		# only set to MON tracks that would otherwise remain
		# in a REC status
		#
		# track:REC bus:MON -> keep current state
		# track:REC bus:REC -> set track to MON

		$track->set(rw => 'MON') if $track->rec_status eq 'REC';

		$ui->global_version_buttons(); # recreate
		$ui->refresh();
		reconfigure_engine();
		$this_track = $track; # why do we need this?
		revise_prompt("default"); 
}
sub poll_cache_progress {

	print ".";
	my $status = eval_iam('engine-status'); 
	my $here   = eval_iam("getpos");
	update_clock_display();
	logpkg('debug', "engine time:   ". d2($here));
	logpkg('debug', "engine status:  $status");

	return unless 
		   $status =~ /finished|error|stopped/ 
		or $here > $processing_time;

	say "Done.";
	logpkg('debug', engine_status(current_position(),2,1));
	#revise_prompt();
	stop_polling_cache_progress();
}
sub stop_polling_cache_progress {
	$engine->{events}->{poll_engine} = undef; 
	$ui->reset_engine_mode_color_display();
	complete_caching();

}
} # end shared lexicals for cache_track and merge_edits

sub uncache_track { 
	my $track = shift;
	# skip unless MON;
	my $cache_map = $track->cache_map;
	my $version = $track->monitor_version;
	if(is_cached($track)){
		# blast away any existing effects, TODO: warn or abort	
		say $track->name, ": removing user effects" if $track->fancy_ops;
		map{ remove_effect($_)} $track->fancy_ops;

		# original WAV -> WAV case: reset version 
		if ( $cache_map->{$version}{original} ){ 
			$track->set(version => $cache_map->{$version}{original});
			print $track->name, ": setting uncached version ", $track->version, $/;

		# assume a sub-bus mix track, i.e. REC -> WAV: set to REC
		} else { 
			$track->set(rw => 'REC') ;
			say $track->name, ": setting sub-bus mix track to REC";
		} 

		my $v = $cache_map->{$version}{effect_chain};

		# get effect change by index if ID is all digits
		my $ec;
		if ($v !~ /\D/) 
		{ 
			$ec = ::EffectChain::find(n => $v);
		}
		else
		{   # get version number from name (_waltz/piano_3)
			# not really version number, actually just an index
			($v) = $v =~ /_(\d+)$/; 
			$ec = ::EffectChain::find(
				track_track => 1, # XXXX track_track
				track_name	=> $track->name,
				track_version => "V$v",
				unique		=> 1,
			);
		}
		$ec->add($track) if defined $ec;
		
	} 
	else { print $track->name, ": version $version is not cached\n"}
}
sub is_cached {
	my $track = shift;
	my $cache_map = $track->cache_map;
	$cache_map->{$track->monitor_version}
}
1;
__END__
