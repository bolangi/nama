# Nama variables by category
# This file is preprocessed to remove comments
# (which would otherwise appear in qw() quoting)

##  Config file variables

# @config_vars is replaced by config_vars()
# now taken from keys (first column) of the file
# src/config_map 
					
# user defined and system global effect chains 
# are saved in a separate file. 

@global_effect_chain_vars  = qw(@global_effect_chain_data $::EffectChain::n );

# variables that get saved to State.json and placed under
# version control

@tracked_vars = qw(

# category: object serialization

	@tracks_data
	@bus_data
	@groups_data
	@marks_data
	@fade_data
	@edit_data
	@inserts_data

	$project->{save_file_version_number}
	
	$fx->{applied}
	$fx->{params}
	$fx->{params_log}

);

# variables saved to Aux.json, *not* under version control
# note that this includes project-specific effect
# chains

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

