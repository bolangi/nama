
@global_vars = qw(
						$mixname
						$effects_cache_file
						$ladspa_sample_rate
						$state_store_file
						$chain_setup_file
						%alias 			   
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
						$wav_dir 	
						$record_device			);
						
						

@persistent_vars = qw(

						%cops 			
						$cop_id 		
						%copp 			
						@marks			
						$unit			
						%oid_status		
						%old_vol		
						$jack_on 
						@tracks_data
						@groups_data

						);
					 
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


