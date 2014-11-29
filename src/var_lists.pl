@global_effect_chain_vars  = qw(

	@global_effect_chain_data 
	$::EffectChain::n 
	$fx->{alias}
);
@tracked_vars = qw(

	@tracks_data
	@bus_data
	@groups_data
	@marks_data
	@fade_data
	@edit_data
	@inserts_data
	@effects_data

	$project->{save_file_version_number}
	
	$fx->{applied}
	$fx->{params}
	$fx->{params_log}

);
@persistent_vars = qw(

	$project->{save_file_version_number}
	$project->{timebase}
	$project->{command_buffer}
	$project->{track_version_comments}
	$project->{track_comments}
	$project->{bunch}
	$project->{current_op}
	$project->{current_param}
	$project->{current_stepsize}
	$project->{playback_position}
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

