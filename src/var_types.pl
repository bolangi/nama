# @global_vars is unused
@global_vars = qw(
						$effects_cache_file
						$ladspa_sample_rate
						$state_store_file
						$chain_setup_file
						$tk_input_channels
						$use_monitor_version_for_mixdown 
						$unit								);
						
# variables found in namarc
#
@config_vars = qw(
						%abbreviations
						%devices
						$ecasound_globals
						$ecasound_globals_for_mixdown
						$ecasound_tcp_port
						$mix_to_disk_format
						$raw_to_disk_format
						$mixer_out_format
						$alsa_playback_device
						$capture_device	
						$project_root 	
						$use_group_numbering
						$press_space_to_start_transport
						$execute_on_project_load
						$initial_user_mode
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
						$loop_enable
						@loop_endpoints
						$length
						%bunch
						$mastering_mode
						@command_history
						$saved_version
						$main_out
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
					


# following is unused 
@effects_dynamic_vars = qw(

						%state_c_ops
						%cops    
						$cop_id     
						%copp   
						@marks 	
						$unit				);



# unused, but referred to
@status_vars = qw(

						%state_c
						%state_t
						%copp
						%cops
						%post_input
						%pre_output   
						%inputs
						%outputs      );

