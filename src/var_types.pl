# variables found in namarc
#
@config_vars = qw(
						%abbreviations
						%devices
					
						$ecasound_globals_realtime
						$ecasound_globals_default
						$ecasound_tcp_port

						$mix_to_disk_format
						$raw_to_disk_format
						$cache_to_disk_format
						$mixer_out_format

						$alsa_playback_device
						$alsa_capture_device	
						$soundcard_channels

						$project_root 	
						$use_group_numbering
						$press_space_to_start_transport
						$execute_on_project_load
						$initial_user_mode

						$volume_control_operator
						$mastering_effects
						$eq 
						$low_pass
						$mid_pass
						$high_pass
						$compressor
						$spatialiser
						$limiter

						$autosave_interval
						$midish_enable
						$quietly_remove_tracks
						$use_jack_plumbing
						$jack_seek_delay
						);

						
						
# used for saving to State.yml
#
@persistent_vars = qw(

	$cop_id 		# autoincrement counter
					# chain operator id that how we create, 
					# store find them, adjust them, and destroy them,
					# per track or per project?
	%cops			# chain operators stored here
	%copp			# their parameters for effect update
	%copp_exp      	# for log-scaled sliders
	$unit			# jump multiplier, 1 or 60 seconds
	%oid_status    	# state information for the chain templates
	%old_vol		# a copy of volume settings, for muting
	$this_track_name # for save/restore 
	$this_op      # current effect
	
	@tracks_data
	@bus_data
	@groups_data
	@marks_data
	@fade_data
	@edit_data
	@inserts_data

	@loop_endpoints # they define the loop
	$loop_enable 	# whether we automatically loop
						
	$length			# maximum duration of the recording/playback if known
	%bunch			# user collections of tracks
	$mastering_mode
	@command_history
	$saved_version 	# copy of $VERSION saved with settings in State.yml
	$main_out 		# boolean: route audio output to soundcard?
						);
					 
# used for effects_cache 
#
@effects_static_vars = qw(

	@effects		# static effects information (parameters, hints, etc.)
	%effect_i		# pn:preset_name -> effect number
	                # el:ladspa_label -> effect number
	
	%effect_j      # preset_name -> pn:preset_name
	                # ladspa_label -> el:ladspa_label
	@effects_help  # one line per effect, for text search

	@ladspa_sorted # ld
	%effects_ladspa # parsed data from analyseplugin 
	%effects_ladspa_file 
					# get plugin filename from Plugin Unique ID
	%ladspa_unique_id 
					# get plugin unique id from plugin label
	%ladspa_label  # get plugin label from unique id
	%ladspa_help   # plugin_label => analyseplugin output
	%e_bound		# for displaying hundreds of effects in groups
);
