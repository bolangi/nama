# variables found in namarc
#
@config_vars = qw(

# category: external resources

	%{$config->{devices}}
	$config->{alsa_playback_device}
	$config->{alsa_capture_device}	
	$config->{soundcard_channels}

# category: audio formats

	%{$config->{abbreviations}}
	$config->{formats}->{mix_to_disk}
	$config->{formats}->{raw_to_disk}
	$config->{formats}->{cache_to_disk}
	$config->{formats}->{mixer_out}
	$config->{sample_rate} 	# needed for frequency-dependent LADSPA effects

# category: engine

	$config->{engine}->{tcp_port}
	$config->{engine}->{globals_realtime}
	$config->{engine}->{globals_default}

# category: config

	$config->{root_dir} 	
	$config->{use_group_numbering}
	$config->{press_space-to-start}
	$config->{execute_on_project_load}
	$config->{initial_mode}
	$config->{autosave_interval}
	$config->{use_midish}
	$config->{quietly_remove_tracks}
	$config->{use_jack_plumbing}
	$config->{engine}->{jack_seek_delay}
	$config->{sync_mixdown_and_monitor_version_numbers} 
	$config->{volume_control_operator}
	# sync mixdown version numbers to selected track versions
	# not implemented

# category: mastering

	$mastering->{fx_eq} 
	$mastering->{fx_low_pass}
	$mastering->{fx_mid_pass}
	$mastering->{fx_high_pass}
	$mastering->{fx_compressor}
	$mastering->{fx_spatialiser}
	$mastering->{fx_limiter}
);
						
# variables that get saved to State.yml
#
@persistent_vars = qw(

	$gui->{_project_name}->{save_file_version_number} 	# copy of $VERSION saved with settings in State.yml

# category: effects

	$fx->{id_counter} 		# autoincrement counter
					# chain operator id that how we create, 
					# store find them, adjust them, and destroy them,
					# per track or per project?
	%{$fx->{applied}}			# chain operators stored here
	%{$fx->{params}}			# their parameters for effect update
	%{$fx->{params_log}}      	# for log-scaled sliders

# category: GUI

	$gui->{_seek_unit}			# jump multiplier, 1 or 60 seconds

	
# category: object serialization

	@tracks_data
	@bus_data
	@groups_data
	@marks_data
	@fade_data
	@edit_data
	@inserts_data

# category: engine, realtime operation

	@{$setup->{loop_endpoints}} # they define the loop
	$mode->{loop_enable} 	# whether we automatically loop
	$setup->{audio_length}			# maximum duration of the recording/playback if known

# category: text UI

	%{$gui->{_project_name}->{bunch}}			# user collections of tracks
	@{$text->{command_history}}

# category: routing

	$mode->{mastering}

# category: pronouns

	$this_track_name # for save/restore 
	$this_op      	# current effect
);
		 
# category: effects_cache 

@effects_static_vars = qw(

	@{$fx_cache->{registry}}		# static effects information (parameters, hints, etc.)
	%{$fx_cache->{full_label_to_index}}		# pn:preset_name -> effect number
	                # el:ladspa_label -> effect number
	
	%{$fx_cache->{partial_label_to_full}}      # preset_name -> pn:preset_name
	                # ladspa_label -> el:ladspa_label
	@{$fx_cache->{user_help}}  # one line per effect, for text search

	@{$fx_cache->{ladspa_sorted}} # ld
	%{$fx_cache->{ladspa}} # parsed data from analyseplugin 
	%{$fx_cache->{ladspa_id_to_filename}} 
					# get plugin filename from Plugin Unique ID
	%{$fx_cache->{ladspa_label_to_unique_id}} 
					# get plugin unique id from plugin label
	%{$fx_cache->{ladspa_id_to_label}}  # get plugin label from unique id
	%{$fx_cache->{ladspa_help}}   # plugin_label => analyseplugin output
	%{$fx_cache->{split}}		# GUI: for displaying hundreds of effects in groups
);
