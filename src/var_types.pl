# Nama variables by category
# This file is preprocessed to remove comments
# (which would otherwise appear in qw() quoting)

##  Config file variables

# @config_vars
# These are now defined as keys (first column) in file var_map 
					
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

