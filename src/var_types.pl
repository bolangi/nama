# list of variables found in namarc
# these are converted to entries in $config->{ }

@config_vars = qw(

# category: external resources

	%devices
	$alsa_playback_device
	$alsa_capture_device	
	$soundcard_channels

# category: audio formats

	%abbreviations
	$mix_to_disk_format
	$raw_to_disk_format
	$cache_to_disk_format
	$mixer_out_format

# category: engine

	$ecasound_tcp_port
	$ecasound_globals_general
	$ecasound_globals_realtime
	$ecasound_globals_nonrealtime
	$ecasound_buffersize_realtime
	$ecasound_buffersize_nonrealtime

# category: config

	$project_root 	
	$use_group_numbering
	$press_space_to_start_transport
	$execute_on_project_load
	$initial_user_mode
	$midish_enable
	$quietly_remove_tracks
	$use_jack_plumbing
	$jack_seek_delay
	$use_monitor_version_for_mixdown 
	$volume_control_operator
	$eager_mode
	$serialize_formats
	$use_git
	$beep_command
	# sync mixdown version numbers to selected track versions
	# not implemented

# category: mastering

	$eq 
	$low_pass
	$mid_pass
	$high_pass
	$compressor
	$spatialiser
	$limiter
);
					
# user defined or other globally accessible effect chains 
# are saved in a separate file to suit version control
# requirements. 

@global_effect_chain_vars  = qw(@global_effect_chain_data $::EffectChain::n );

# list of variables that get saved to State.yml

@new_persistent_vars = qw(

	$project->{save_file_version_number}
	$project->{config}
	$fx->{id_counter}
	$fx->{applied}
	$fx->{params}
	$fx->{params_log}}
	$gui->{_seek_unit}
	@tracks_data
	@bus_data
	@groups_data
	@marks_data
	@fade_data
	@edit_data
	@inserts_data
	@project_effect_chain_data
	$setup->{loop_endpoints}
	$mode->{loop_enable}
	$setup->{audio_length}
	$project->{bunch}
	$text->{command_history}
	$mode->{mastering}
	$this_track_name
	$this_op
);

# this list of variables is 
# retained for backward compatibility
# with State.yml file version 1.078 and earlier

@persistent_vars = qw(

	$saved_version 	# copy of $VERSION saved with settings in State.yml

# category: effects

	$cop_id 		# autoincrement counter
					# chain operator id that how we create, 
					# store find them, adjust them, and destroy them,
					# per track or per project?
	%cops			# chain operators stored here
	%copp			# their parameters for effect update
	%copp_exp      	# for log-scaled sliders

# category: GUI

	$unit			# jump multiplier, 1 or 60 seconds

	
# category: object serialization

	@tracks_data
	@bus_data
	@groups_data
	@marks_data
	@fade_data
	@edit_data
	@inserts_data

# category: engine, realtime operation

	@loop_endpoints # they define the loop
	$loop_enable 	# whether we automatically loop
	$length			# maximum duration of the recording/playback if known

# category: text UI

	%bunch			# user collections of tracks
	@command_history

# category: routing

	$mastering_mode

# category: pronouns

	$this_track_name # for save/restore 
	$this_op      	# current effect
);
		 
