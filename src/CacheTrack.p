# -------- CacheTrack ------
package ::;
use Modern::Perl;
use ::Globals qw(:all);

# The $args hashref passed among the subroutines in this file
# has these fields:

# track
# additional_time
# processing_time
# orig_version
# complete_caching_ref
# output_wav
# orig_volume
# orig_pan

sub cache_track { # launch subparts if conditions are met

	local $this_track;
	my $args = {}; # initialize args
	($args->{track}, $args->{additional_time}) = @_;
	$args->{additional_time} //= 0;
	
	say $args->{track}->name, ": preparing to cache.";
	
	# abort if track is a mix track for a sub-bus and the bus is OFF 
	if( my $bus = $bn{$args->{track}->name}
		and $args->{track}->rec_status eq 'REC' 
	 ){ 
		$bus->rw eq 'OFF' and say(
			$bus->name, ": status is OFF. Aborting."), return;

	# check conditions for normal track
	} else { 
		$args->{track}->rec_status eq 'MON' or say(
			$args->{track}->name, ": track caching requires MON status. Aborting."), return;
	}
	say($args->{track}->name, ": no effects to cache!  Skipping."), return 
		unless 	$args->{track}->fancy_ops 
				or $args->{track}->has_insert
				or $bn{$args->{track}->name};

	if ( prepare_to_cache($args) )
	{ 
		deactivate_vol_pan($args);
		cache_engine_run($args);
		reactivate_vol_pan($args);
		return $args->{output_wav}
	}
	else
	{ 
		say("Empty routing graph. Aborting."); 
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

sub prepare_to_cache {
	my $args = shift;
 	my $g = ::ChainSetup::initialize();
	$args->{orig_version} = $args->{track}->monitor_version;

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
	
	$g->set_vertex_attributes(
		$cooked->name, 
		{ format => signal_format($config->{cache_to_disk_format},$cooked->width),
		}
	); 
	$args->{complete_caching_ref} = \&update_cache_map;

	# Case 1: Caching a standard track
	
	if($args->{track}->rec_status eq 'MON')
	{
		# set the input path
		$g->add_path('wav_in',$args->{track}->name);
		logpkg('debug', "The graph after setting input path:\n$g");
	}

	# Case 2: Caching a sub-bus mix track

	elsif($args->{track}->rec_status eq 'REC'){

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
	if ($success) 
	{ 
		::ChainSetup::write_chains();
		::ChainSetup::remove_temporary_tracks();
	}
	$success
}
sub cache_engine_run {
	my $args = shift;
	connect_transport()
		or say("Couldn't connect engine! Aborting."), return;

	# remove fades from target track
	
	::Effects::remove_op($args->{track}->fader) if defined $args->{track}->fader;

	$args->{processing_time} = $setup->{audio_length} + $args->{additional_time};

	say $/,$args->{track}->name,": processing time: ". d2($args->{processing_time}). " seconds";
	print "Starting cache operation. Please wait.";
	
	revise_prompt(" "); 

	# we try to set processing time this way
	eval_iam("cs-set-length $args->{processing_time}"); 

	eval_iam("start");

	# ensure that engine stops at completion time
	$setup->{cache_track_args} = $args;
 	$engine->{events}->{poll_engine} = AE::timer(1, 0.5, \&poll_cache_progress);

	# complete_caching() contains the remainder of the caching code.
	# It is triggered by stop_polling_cache_progress()
}
sub complete_caching {
	my $args = shift;	
	my $name = $args->{track}->name;
	my @files = grep{/$name/} new_files_were_recorded();
	if (@files ){ 
		
		$args->{complete_caching_ref}->($args) if defined $args->{complete_caching_ref};
		post_cache_processing($args);

	} else { say "track cache operation failed!"; }
	undef $setup->{cache_track_args};
}
sub update_cache_map {
	my $args = shift;
		logpkg('debug', "updating track cache_map");
		logpkg('debug', "current track cache entries:",
			sub {
				join "\n","cache map", 
				map{($_->dump)} ::EffectChain::find(track_cache => 1)
			});
		my @inserts_list = ::Insert::get_inserts($args->{track}->name);
		my @ops_list = $args->{track}->fancy_ops;
		if ( @inserts_list or @ops_list or $args->{track}->is_region)
		{
			my %args = 
			(
				track_cache => 1,
				track_name	=> $args->{track}->name,
				track_version_original => $args->{orig_version},
				track_version_result => $args->{track}->last,
				project => 1,
				system => 1,
				ops_list => \@ops_list,
				inserts_data => \@inserts_list,
			);
			$args{region} = [ $args->{track}->region_start, $args->{track}->region_end ] 
				if $args->{track}->is_region;
			my $ec = ::EffectChain->new( %args );
			map{ remove_effect($_) } @ops_list;
			map{ $_->remove        } @inserts_list;
			$args->{track}->set(region_start => undef, region_end => undef);

		say qq(Saving effects for cached track "), $args->{track}->name, '".';
		say qq('uncache' will restore effects and set version $args->{orig_version}\n);
		}
}

sub post_cache_processing {
	my $args = shift;
		# only set to MON tracks that would otherwise remain
		# in a REC status
		#
		# track:REC bus:MON -> keep current state
		# track:REC bus:REC -> set track to MON

		$args->{track}->set(rw => 'MON') if $args->{track}->rec_status eq 'REC';

		$ui->global_version_buttons(); # recreate
		$ui->refresh();
		revise_prompt("default"); 
}
sub poll_cache_progress {
	my $args = $setup->{cache_track_args};
	print ".";
	my $status = eval_iam('engine-status'); 
	my $here   = eval_iam("getpos");
	update_clock_display();
	logpkg('debug', "engine time:   ". d2($here));
	logpkg('debug', "engine status:  $status");

	return unless 
		   $status =~ /finished|error|stopped/ 
		or $here > $args->{processing_time};

	say "Done.";
	logpkg('debug', engine_status(current_position(),2,1));
	#revise_prompt();
	stop_polling_cache_progress($args);
}
sub stop_polling_cache_progress {
	my $args = shift;
	$engine->{events}->{poll_engine} = undef; 
	$ui->reset_engine_mode_color_display();
	complete_caching($args);

}

sub uncache_track { 
	my $track = shift;
	local $this_track;
	# skip unless MON;
	throw($track->name, ": cannot uncache unless track is set to MON"), return
		unless $track->rec_status eq 'MON';
	my $version = $track->monitor_version;
	my ($ec) = is_cached($track, $version);
	defined $ec or throw($track->name, ": version $version is not cached"),
		return;

		# blast away any existing effects, TODO: warn or abort	
		say $track->name, ": removing user effects" if $track->fancy_ops;
		map{ remove_effect($_)} $track->fancy_ops;

	# CASE 1: an ordinary track, 
	#
	# * toggle to the old version
	# * load the effect chain 
	#
			$track->set(version => $ec->track_version_original);
			print $track->name, ": setting uncached version ", $track->version, 
$/;
	# CASE 2: a sub-bus mix track, set to REC for caching operation.

	if( my $bus = $bn{$track->name}){
			$track->set(rw => 'REC') ;
			say $track->name, ": setting sub-bus mix track to REC";
	}

		$ec->add($track) if defined $ec;
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
			map{ json_out($_) } @results);
	$results[-1]
}
1;
__END__
