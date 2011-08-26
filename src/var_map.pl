	$project_name				$project->{name}
	$saved_version 				$project->{save_file_version_number}
	%bunch						$project->{bunch}
	
	$main_bus 					$bn{Main}
	$main						$gn{Main} 
	$null_bus					$bn{null}

	%abbreviations				$config->{abbreviations}

	$mix_to_disk_format 		$config->{formats}->{mix_to_disk}
	$raw_to_disk_format 		$config->{formats}->{raw_to_disk}
	$cache_to_disk_format 		$config->{formats}->{cache_to_disk}
	$mixer_out_format 			$config->{formats}->{mixer_out}
	$ladspa_sample_rate 	 	$config->{sample_rate}
	$use_pager     				$config->{use_pager}
	$use_placeholders  			$config->{use_placeholders}
	%is_system_bus 				$config->{_is_system_bus}
	$sampling_frequency			$config->{sampling_freq}
	
	# aliases
	
	%ti
	%tn
	%bn
	%gn
	
	$debug
	$debug2
	$debug3

	$jack_running  				$jack->{jackd_running}
	$jack_lsp      				$jack->{ports_list_text}
	$fake_jack_lsp 				$jack->{fake_ports_list}
	%jack						$jack->{clients}
	
	$old_snapshot  				$setup->{_old_snapshot}
	%old_rw       				$setup->{_old_track_rw_status}
	%already_used 				$setup->{inputs_used}
	%duplicate_inputs 			$setup->{tracks_with_duplicate_inputs}
	%cooked_record_pending 		$setup->{cooked_record_pending}
	$track_snapshots 			$setup->{track_snapshots}
	$regenerate_setup 			$setup->{changed}
	%wav_info					$setup->{wav_info}	
	$run_time					$setup->{runtime_limit}
	@loop_endpoints 			$setup->{loop_endpoints}
	$length						$setup->{audio_length}

    $offset_run_start_time 		$setup->{offset_run}->{start_time}
    $offset_run_end_time   		$setup->{offset_run}->{end_time}
    $offset_mark           		$setup->{offset_run}->{mark}
    @edit_points           		$setup->{edit_points}

    @effects        			$fx_cache->{registry}
    %effect_i       			$fx_cache->{full_label_to_index}
    %effect_j       			$fx_cache->{partial_label_to_full}
    @effects_help   			$fx_cache->{user_help}
    @ladspa_sorted  			$fx_cache->{ladspa_sorted}
    %effects_ladspa 			$fx_cache->{ladspa}
    %effects_ladspa_file 		$fx_cache->{ladspa_id_to_filename}
    %ladspa_unique_id  			$fx_cache->{ladspa_label_to_unique_id}
    %ladspa_label  				$fx_cache->{ladspa_id_to_label}
    %ladspa_help    			$fx_cache->{ladspa_help}
    %e_bound        			$fx_cache->{split}

	$help_screen  				$help->{screen}
	@help_topic   				$help->{arr_topic}
	%help_topic   				$help->{topic}
 
	$preview      				$mode->{preview}
    $offset_run_flag 			$mode->{offset_run}
    $soloing       				$mode->{soloing}
	$loop_enable 				$mode->{loop_enable}
	$mastering_mode				$mode->{mastering}
	
	%event_id    				$engine->{events}
	$sock 						$engine->{socket}
	@ecasound_pids				$engine->{pids}
	$e							$engine->{ecasound}

	$magical_cop_id				$fx->{magical_cop_id}
	$cop_hints_yml 				$fx->{ecasound_effect_hints}
	%offset        				$fx->{offset}
	@already_muted  			$fx->{muted}
	%effect_chain 				$fx->{chain}
	%effect_profile 			$fx->{profile}
	%mute_level					$fx->{mute_level}
	%fade_out_level 			$fx->{fade_out_level}
	$fade_resolution 			$fx->{fade_resolution}
	%unity_level				$fx->{unity_level}
	$cop_id 					$fx->{id_counter}
	%cops		 				$fx->{applied}
	%copp						$fx->{params}
	%copp_exp   				$fx->{params_log}

	%midish_command				$midi->{keywords}
	$midi_input_dev    			$midi->{input_dev}
	$midi_output_dev   			$midi->{output_dev}
	$controller_ports			$midi->{controller_ports}
    $midi_inputs				$midi->{inputs}

	$grammar					$text->{grammar}
	$parser						$text->{parser}
	$text_wrap					$text->{wrap}
	@format_fields 				$text->{format_fields}
	
	$commands_yml				$text->{commands_yml}
	%commands					$text->{commands}
	%iam_cmd					$text->{iam}
	@nama_commands 				$text->{arr_nama_cmds}
	%nama_commands				$text->{nama_commands}

	$term 						$text->{term}
	$previous_text_command 		$text->{previous_cmd}
	@keywords      				$text->{keywords}
    $prompt						$text->{prompt}
	$attribs       				$text->{term_attribs}
	$format_top    				$text->{format_top}
	$format_divider				$text->{format_divider}
	%user_command 				$text->{user_command}
	%user_alias   				$text->{user_alias}
	@command_history 			$text->{command_history}

# category: pronouns

	$this_track
	$this_mark
	$this_bus
	$this_edit
	$this_track_name 
	$this_op
 
# category: object serialization

	@tracks_data
	@bus_data
	@groups_data
	@marks_data
	@fade_data
	@edit_data
	@inserts_data
	@persistent_vars
	@config_vars
	@effects_static_vars

# category: config

	%devices 						$config->{devices}
	$alsa_playback_device 			$config->{alsa_playback_device}
	$alsa_capture_device			$config->{alsa_capture_device}
	$soundcard_channels				$config->{soundcard_channels}
	$memoize       					$config->{memoize}
	$hires        					$config->{hires_timer}
	%opts          					$config->{opts}
	$default						$config->{default}	
	$project_root 	 				$config->{root_dir}
	$use_group_numbering 			$config->{use_group_numbering}
	$press_space_to_start_transport $config->{press_space-to-start}
	$execute_on_project_load 		$config->{execute_on_project_load}
	$initial_user_mode 				$config->{initial_mode}
	$autosave_interval 				$config->{autosave_interval}
	$midish_enable 					$config->{use_midish}
	$use_jack_plumbing 				$config->{use_jack_plumbing}
	$quietly_remove_tracks 			$config->{quietly_remove_tracks}
	$use_monitor_version_for_mixdown $config->{sync_mixdown_and_monitor_version_numbers} 
	$volume_control_operator 		$config->{volume_control_operator}
	$default_palette_yml 			$config->{gui_default_palette_yml}
	$tk_input_channels 				$config->{soundcard_channels}
	$banner 						$config->{banner}
	$disable_auto_reconfigure 		$config->{disable_auto_reconfigure}

    $edit_playback_end_margin  		$config->{edit}->{playback_past_last_mark}
    $edit_crossfade_time  			$config->{edit}->{crossfade_time}
	$default_fade_length 			$config->{engine}->{fade_default_length}
	$fade_time 						$config->{engine}->{fade_length_on_start_stop}
	$seek_delay    					$config->{engine}->{jack_seek_delay}
	$jack_seek_delay  				$config->{engine}->{jack_seek_delay}

	$ecasound_tcp_port 				$config->{engine}->{tcp_port}
	$ecasound_globals_realtime 		$config->{engine}->{globals_realtime}
	$ecasound_globals_default		$config->{engine}->{globals_default}
 
	$effects_cache_file 			$file->{effects_cache}
	$state_store_file				$file->{state_store}
	$effect_chain_file 				$file->{effect_chain}
	$effect_profile_file 			$file->{effect_profile}
	$chain_setup_file 				$file->{chain_setup}
	$user_customization_file 		$file->{user_customization}
	$palette_file  					$file->{gui_palette}
	$custom_pl    					$file->{custom_pl}

	@mastering_track_names			$mastering->{track_names}
	@mastering_effect_ids			$mastering->{fx_ids}
	$eq 							$mastering->{fx_eq}
	$low_pass 						$mastering->{fx_low_pass}
	$mid_pass						$mastering->{fx_mid_pass}
	$high_pass						$mastering->{fx_high_pass}
	$compressor						$mastering->{fx_compressor}
	$spatialiser					$mastering->{fx_spatialiser}
	$limiter						$mastering->{fx_limiter}

	$unit							$gui->{_seek_unit}
	$project						$gui->{_project_name}
	$track_name						$gui->{_track_name}
	$ch_r							$gui->{_chr}
	$ch_m							$gui->{_chm}
	$save_id						$gui->{_save_id}
	$mw 							$gui->{mw}
	$ew 							$gui->{ew}
	$canvas 						$gui->{canvas}

	$load_frame    					$gui->{load_frame}
	$add_frame     					$gui->{add_frame}
	$group_frame   					$gui->{group_frame}
	$time_frame						$gui->{time_frame}
	$clock_frame   					$gui->{clock_frame}
	$track_frame   					$gui->{track_frame}
	$effect_frame  					$gui->{fx_frame}
	$iam_frame						$gui->{iam_frame}
	$perl_eval_frame 				$gui->{perl_frame}
	$transport_frame 				$gui->{transport_frame}
	$mark_frame						$gui->{mark_frame}
	$fast_frame 					$gui->{seek_frame}

	%parent  						$gui->{parents}
	$group_label  					$gui->{group_label}
	$group_rw 						$gui->{group_rw}
	$group_version 					$gui->{group_version} 
	%track_widget 					$gui->{tracks}
	%track_widget_remove 			$gui->{tracks_remove}
	%effects_widget 				$gui->{fx}
	%mark_widget  					$gui->{marks}
	@global_version_buttons 		$gui->{global_version_buttons}
	$mark_remove   					$gui->{mark_remove}
	$markers_armed 					$gui->{_markers_armed}
	$time_step     					$gui->{seek_unit}
	$clock 							$gui->{clock}
	$setup_length  					$gui->{setup_length}
	$project_label					$gui->{project_head}
	$sn_label						$gui->{project_label}
	$sn_text       					$gui->{project_entry}
	$sn_load						$gui->{load_project}
	$sn_new							$gui->{new_project}
	$sn_quit						$gui->{quit}
	$sn_palette 					$gui->{_palette}
	$sn_namapalette 				$gui->{_nama_palette}
	$sn_effects_palette 			$gui->{_fx_palette}
	$sn_save_text  					$gui->{savefile_entry}
	$sn_save						$gui->{save_project}	
	$sn_recall						$gui->{load_savefile}

	@palettefields 					$gui->{_palette_fields}
	@namafields    					$gui->{_nama_fields}
	%namapalette   					$gui->{_nama_palette}
	%palette 						$gui->{_palette} 
	$rec      						$gui->{rec_bg}
	$mon     						$gui->{mon_bg} 
	$off     						$gui->{off_bg} 

	$build_track_label 				$gui->{add_track}->{label}
	$build_track_text 				$gui->{add_track}->{text_entry}
	$build_track_add_mono 			$gui->{add_track}->{add_mono}
	$build_track_add_stereo 		$gui->{add_track}->{add_stereo}
	$build_track_rec_label 			$gui->{add_track}->{rec_label}
	$build_track_rec_text 			$gui->{add_track}->{rec_text}
	$build_track_mon_label 			$gui->{add_track}->{mon_label}
	$build_track_mon_text  			$gui->{add_track}->{mon_text}

	$transport_label 				$gui->{engine}->{label}
	$transport_setup_and_connect 	$gui->{engine}->{arm}
	$transport_disconnect 			$gui->{engine}->{disconnect}
	$transport_start 				$gui->{engine}->{start}
	$transport_stop  				$gui->{engine}->{stop}
	$old_bg 						$gui->{_old_bg}
	$old_abg 						$gui->{_old_abg}

# end
