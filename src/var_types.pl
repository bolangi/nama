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

						);

						
						
# used for saving to State.yml
#
@persistent_vars = qw(

						%cops 			
						$cop_id 		
						%copp 			
						%copp_exp
						$unit			
						%oid_status		
						%old_vol		
						$this_op
						@tracks_data
						@bus_data
						@groups_data
						@marks_data
						@fade_data
						@inserts_data
						$loop_enable
						@loop_endpoints
						$length
						%bunch
						$mastering_mode
						@command_history
						$saved_version
						$main_out
						$this_track_name
						);
					 
# used for effects_cache 
#
@effects_static_vars = qw(

						@effects		
						%effect_i	
						%effect_j	
						%e_bound
						@ladspa_sorted
						%effects_ladspa	
						%effects_ladspa_file
						%ladspa_unique_id
						%ladspa_label
						%ladspa_help
						@effects_help
						);
