
use constant (REC => 'rec',
			  MON => 'mon',
			  MUTE => 'mute');


our (
	### 
	$ui, # object providing class behavior for graphic/text functions

	@persistent_vars, # a set of variables we save
					  	# as one big config file
	@effects_static_vars,	# the list of which variables to store and retrieve
	@effects_dynamic_vars,		# same for all chain operators
	@global_vars,    # contained in config file
	@config_vars,    # contained in config file
	%abbreviations, # for replacements in config files

	$globals,		# yaml assignments for @global_vars
					# for appending to config file
	
	$ecasound_globals, #  Command line switches XX check

	$default,		# the default configuration file
					# as distinct from custom file
					# in a project directory, or a 
					# master in .ecmd root.
					
	$oids,			# serialized (YAML) form of @oids
	$gui,			# still here!

	$raw_to_disk_format,
	$mix_to_disk_format,
	$mixer_out_format,
	
	$mixname, 		# 'mix' for the mixer track display
	$yw,			# yaml writer object
	$yr,			# yaml writer object
	%state_c_ops, 	# intermediate copy for storage/retrieval
	$effects_cache_file, # where we keep info on Ecasound
					# and LADSPA effects, presets, etc.
	
	$ecasound, 		# the name to invoke, but I don't think
					# we invoke by name, that's why i have these
					# libraries

	$grammar, 		# filled by Grammar.pm
	@ecmd_commands,# array of commands my functions provide
	%ecmd_commands,# as hash as well
	$wav_dir,	# each project will get a directory here
	                # and one .ecmd directory, also with 
	
					# /wav_dir/project_dir/vocal_1.wav
					# /wav_dir/.flow/project_dir
	$state_store_file,	# filename for storing @persistent_vars
	$chain_setup_file, # Ecasound uses this 

	$tk_input_channels,# this many radiobuttons appear
	                # on the menubutton
	%cfg,        # 'config' information as hash
					# or Config.pm
	%devices, 		# alias to data in %cfg
	%opts,          # command line options (set by command stub)
	%oid_status,    # state information for the chain templates
	$clock_id,		# for the Tk event system
	$use_monitor_version_for_mixdown, # sync mixdown version numbers
	              	# to selected track versions 
	$select_track,	 # the currently active track -- for Text UI
	@format_fields, # data for replies to text commands

	$project,		# Tk types project name here
	$project_name,	# Official project name
	$i, 			# index for incrementing track numbers
	$t,				# index for incrementing track groups
	%state_c,		# data for Track object, except effects
	%state_t,		# data for track groups (takes)
	%take,			# which group a track number belongs to 
	@takes,			# we collect them here
	%alias,			# key: name value: take number
	%chain,


	### for effects

	$cop_id, 		# chain operator id, that how we create, 
					# store, find them, adjust them, and destroy them,
					# per track or per project?
	%cops,			 # chain operators stored here
	%copp,			# their parameters for effect update
	%track_names,	# to know if they are taken
	@effects,		# static effects information (parameters, hints, etc.)
	%effect_i,		# an index
	@ladspa_sorted, # ld
	%effects_ladspa,# an index
	$e,				# the name of the variable holding
					# the Ecasound engine object.
					
	$last_version,  # to know where the next recording should start
	$monitor_version,# which global version we are currently using
	%e_bound,		# for displaying hundreds of effects in groups
	@marks,			# where we want to come back tto
	$unit,			# multiples of seconds or minutes
	$markers_armed, # two states forth the markers
	%old_vol,		# a copy of volume settings, for muting
	$length,		# maximum duration of the recording/playback if known
	$jack_on,		# whether we use device jack_alsa

## for &make_io_lists
#
	@monitor,		# tracks that will playback
	@record,		# tracks thatwill record
	@mute,			# tracks we'll exclude from chain setup
	@all_chains,	# all that will be a part of our setup
	@input_chains,	# we sort them in input chains and output chains
	@output_chains,

	%subst,			# alias, substitutions for the config file
	$tkeca_effects_data,	# original tcl code, actually

	### Widgets
	
	$mw, 			# main window
	$ew, 			# effects window
	$canvas, 		# to lay out the effects window

	# each part of the main window gets its own frame
	# to control the layout better

	$load_frame,
	$add_frame,
	$take_frame,
	$time_frame,
	$clock_frame,
	$oid_frame,
	$track_frame,
	$effect_frame,
	$iam_frame,
	$perl_eval_frame,
	$transport_frame,

	## collected widgets (i may need to destroy them)

	@widget_t, # widgets for displaying track groups (busses!)
	%widget_c, # for chains (tracks)
	%widget_e, # for effects
	@widget_o, # for templates (oids) 
	%widget_o, # 

	@global_version_buttons, # to set the same version for
						  	#	all tracks
	@time_marks,	# how different from @marks?
					# one is widgets one is the data
	$time_step,
	$clock, 		# displays clock
	$setup_length,  # displays runing time

	$project_label,	# project name
	$take_label,	# bus name

	$sn_label,		# project load/save/quit	
	$sn_text,
	$sn_load,
	$sn_load_nostate,
	$sn_new,
	$sn_quit,

	### A separate box for entering IAM (and other) commands
	$iam_label,
	$iam_text,
	$iam_execute,
	$iam_error,

	# add track gui
	#
	$build_track_label,
	$build_track_text,
	$build_track_add,
	$build_track_rec_label,
	$build_track_rec_text,
	$build_track_mon_label,
	$build_track_mon_text,

	$build_new_take,

	# transport controls
	
	$transport_label,
	$transport_setup_and_connect,
	$transport_setup,
	$transport_connect,
	$transport_disconnect,
	$transport_new,
	$transport_start,
	$transport_stop,

	$iam,    # unused
	$old_bg, # initial background color.


	$loopa,  # loopback nodes 
	$loopb,  
	$mixchain, # name of my mix track: 'mix'
	$mixchain_aux, # an extra node due to name conflict

	@oids,	# output templates, are applied to the
			# chains collected previously
			# the results are grouped as
			# input, output and intermediate sections

	%inputs,
	%outputs,
	%post_input,
	%pre_output,

	$ladspa_sample_rate,	# used as LADSPA effect parameter fixed at 44100

	$track_name,	# received from Tk text input form
	$ch_r,			# this too, recording channel assignment
	$ch_m,			# monitoring channel assignment


	%L,	# for effects
	%M,
	$debug,				# debug level flags for diagnostics
	$debug2,			# for subroutine names as execute
	$debug3,			# for reference passing diagnostics
	 					#    where the &see_ref() call is
						#    used
						
	$OUT,				# filehandle for Text mode print
	$commands,	# ref created from commands.plus

);
