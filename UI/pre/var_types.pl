
@global_vars = qw(
						$mixname
						$effects_cache_file
						$ladspa_sample_rate
						$state_store_file
						$chain_setup_file
						%alias 			   
						$tk_input_channels
						$use_monitor_version_for_mixdown );
						
@config_vars = qw(
						%abbreviations
						%devices
						$ecasound_globals
						$mix_to_disk_format
						$raw_to_disk_format
						$mixer_out_format
						$wav_dir 				);
						
						

@persistent_vars = qw(

						$monitor_version
						$last_version 
						%track_names 	
						%state_c 		
						%state_t 		
						%cops 			
						$cop_id 		
						%copp 			
						@all_chains 	
						$i 				
						$t 				
						%take 			
						@takes 			
						%chain 			
						@marks			
						$unit			
						%oid_status		
						%old_vol		
						$jack_on 			);
					 
@effects_static_vars = qw(

						@effects		
						%effect_i	
						@ladspa_sorted
						%effects_ladspa		 );

@effects_dynamic_vars = qw(

						%state_c_ops
						%cops    
						$cop_id     
						%copp   
						@marks 	
						$unit				);



