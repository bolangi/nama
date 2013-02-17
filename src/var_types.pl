# Nama variables by category
# This file is preprocessed to remove comments
# (which would otherwise appear in qw() quoting)

##  Config file variables
##  These are converted to entries in $config->{ }

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
	$sample_rate

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
	$serialize_formats
	$use_git
	$autosave
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

# list of variables that get saved to State.json

@persistent_vars = qw(

# category: object serialization

	@tracks_data
	@bus_data
	@groups_data
	@marks_data
	@fade_data
	@edit_data
	@inserts_data

# category: pronouns

	$this_track_name # for save/restore 
	$this_op      	# current effect

	$project->{save_file_version_number}
	
	$fx->{applied}
	$fx->{params}
	$fx->{params_log}

);

# these variables get saved to Aux.json

@unversioned_state_vars = qw(

	$project->{save_file_version_number}
	$project->{timebase}
	$project->{cache_map}
	$project->{undo_buffer}
	$project->{track_version_comments}
	$project->{track_comments}
	$project->{bunch}
	@project_effect_chain_data
	$fx->{id_counter}
	$setup->{loop_endpoints}
	$mode->{loop_enable}
	$mode->{mastering}
	$mode->{preview}
	$mode->{midish_terminal}
	$mode->{midish_transport_sync}
	$gui->{_seek_unit}
	$text->{command_history}
	$this_track_name
	$this_op
);

