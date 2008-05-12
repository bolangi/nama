our (
	### 
	$ui, # object providing class behavior for graphic/text functions

	@persistent_vars, # a set of variables we save
					  	# as one big config file
	@effects_static_vars,	# the list of which variables to store and retrieve
	@effects_dynamic_vars,		# same for all chain operators
	@global_vars,    # contained in config file
	@config_vars,    # contained in config file
	@status_vars,    # we will dump them for diagnostic use
	%abbreviations, # for replacements in config files

	$globals,		# yaml assignments for @global_vars
					# for appending to config file
	
	$ecasound_globals, #  Command line switches XX check

	$default,		# the internal default configuration file, as string
					
	$raw_to_disk_format,
	$mix_to_disk_format,
	$mixer_out_format,
	
	$yw,			# yaml writer object
	$yr,			# yaml reader object
	%state_c_ops, 	# intermediate copy for storage/retrieval
	$effects_cache_file, # where we keep info on Ecasound
					# and LADSPA effects, presets, etc.
	
	$ecasound, 		# the name to invoke when we want to kill ecasound

	$grammar, 		# filled by Grammar.pm
	$parser,		# for the objected created by Parse::RecDescent
	%iam_cmd,		# for identifying IAM commands in user input
	@ecmd_commands,# array of commands my functions provide
	%ecmd_commands,# as hash as well
	$wav_dir,	# each project will get a directory here
	                # and one .ecmd directory, also with 
	
					#
					# $ENV{HOME}/.ecmdrc
					# $ENV{HOME}/ecmd/paul_brocante
					# $ENV{HOME}/ecmd/paul_brocante/.wav/vocal_1.wav
					# $ENV{HOME}/ecmd/paul_brocante/Store.yml
					# $ENV{HOME}/ecmd/.effects_cache
					# $ENV{HOME}/ecmd/paul_brocante/.ecmdrc 

					 #this_wav_dir = 
	$state_store_file,	# filename for storing @persistent_vars
	$chain_setup_file, # Ecasound uses this 

	$tk_input_channels,# this many radiobuttons appear
	                # on the menubutton
	%cfg,        # 'config' information as hash
	%devices, 		# alias to data in %cfg
	%opts,          # command line options
	%oid_status,    # state information for the chain templates
	$clock_id,		# used in GUI for the Tk event system
					# ->cancel method not reliable
					# for 'repeat' events, so converted to
					# 'after' events
	$use_monitor_version_for_mixdown, # sync mixdown version numbers
	              	# to selected track versions , not
					# implemented
	$select_track,	 # the currently active track -- 
					 # used by Text UI only at present
	@format_fields, # data for replies to text commands

	$project,		# variable for GUI text input
	$project_name,	# current project name
	%state_c,		# for backwards compatilility

	### for effects

	$cop_id, 		# chain operator id, that how we create, 
					# store, find them, adjust them, and destroy them,
					# per track or per project?
	%cops,			 # chain operators stored here
	%copp,			# their parameters for effect update
	@effects,		# static effects information (parameters, hints, etc.)
	%effect_i,		# an index
	@ladspa_sorted, # ld
	%effects_ladspa,# an index
	$e,				# the name of the variable holding
					# the Ecasound engine object.
					
	%e_bound,		# for displaying hundreds of effects in groups
	$unit,			# jump multiplier, 1 or 60 seconds
	%old_vol,		# a copy of volume settings, for muting
	$length,		# maximum duration of the recording/playback if known
	$jack_on,		# whether we use device jack_alsa, currently unused 
					# signals to replace regular output device with
					# jack_alsa

	@input_chains,	# list of input chain segments 
	@output_chains, # list of output chain segments

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
	$mark_frame,
	$fast_frame, # forward, rewind, etc.

	## collected widgets (i may need to destroy them)

	@widget_t, # widgets for displaying track groups, unused
	$tracker_group_widget, # widget for tracker group, replaces @widget_t
	%widget_c, # for chains (tracks)
	%widget_e, # for effects
	@widget_o, # for templates (oids) 
	%widget_o, # 
	%widget_m, # marks

	@global_version_buttons, # to set the same version for
						  	#	all tracks
	%marks, 		# the actual times
	$markers_armed, # set true to enable removing a mark
	$mark_remove,   # a button that sets $markers_armed
	$time_step,     # widget shows jump multiplier unit (seconds or minutes)
	$clock, 		# displays clock
	$setup_length,  # displays setup running time

	$project_label,	# project name
	$take_label,	# bus name

	$sn_label,		# project load/save/quit	
	$sn_text,
	$sn_load,
	$sn_new,
	$sn_quit,

	### A separate box for entering IAM (and other) commands
	$iam_label,
	$iam_text,
	$iam, # variable for text entry
	$iam_execute,
	$iam_error, # unused

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
	$transport_setup, # unused
	$transport_connect, # unused
	$transport_disconnect,
	$transport_new,
	$transport_start,
	$transport_stop,

	$old_bg, # initial background color.


	$loopa,  # loopback nodes 
	$loopb,  

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
	$ch_m,			# monitoring channel assignment, unused


	%L,	# for effects
	%M,
	$debug,				# debug level flags for diagnostics
	$debug2,			# for subroutine names as execute
	$debug3,			# deprecated
						
	$OUT,				# filehandle for Text mode print
	$commands,	# ref created from commands.yml

	$save_id, # text variable
	$sn_save_text,# text entry widget
	$sn_save,	# button to save settings
	$sn_recall,	# button to recall settings
	$sn_dump,  # button to dump status

	# new object core
	
	$tracker_bus, 
	$tracker, # tracker_group
	$master_bus, 
	$master, # master_group
	$master_track,
	$mixdown_bus,
	$mixdown,  # group
	$mixdown_track,

	@ti, # track by index (alias @::Track::by_index)
	%tn, # track by name  (alias %::Track::by_name)

	@tracks_data, # staging for saving
	@groups_data, # 

	$mixer_out_device, # where to send stereo output
	$record_device,    # where to get our inputs

);
