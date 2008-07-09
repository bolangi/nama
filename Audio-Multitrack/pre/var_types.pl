
@global_vars = qw(
						$effects_cache_file
						$ladspa_sample_rate
						$state_store_file
						$chain_setup_file
						$tk_input_channels
						$use_monitor_version_for_mixdown 
						$unit								);
						
@config_vars = qw(
						%abbreviations
						%devices
						$ecasound_globals
						$mix_to_disk_format
						$raw_to_disk_format
						$mixer_out_format
						$mixer_out_device
						$project_root 	
						$record_device			);
						
						

@persistent_vars = qw(

						%cops 			
						$cop_id 		
						%copp 			
						%marks			
						$unit			
						%oid_status		
						%old_vol		
						$this_op
						$jack_on 
						@tracks_data
						@groups_data
						@marks_data
						$loop_enable
						@loop_endpoints
						$length

						);
						# $this_track
					 
@effects_static_vars = qw(

						@effects		
						%effect_i	
						%e_bound
						@ladspa_sorted
						%effects_ladspa		 );


@effects_dynamic_vars = qw(

						%state_c_ops
						%cops    
						$cop_id     
						%copp   
						@marks 	
						$unit				);



@status_vars = qw(

						%state_c
						%state_t
						%copp
						%cops
						%post_input
						%pre_output   
						%inputs
						%outputs      );


