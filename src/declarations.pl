our (

    # 'our' means these variables will be accessible, without
	# package qualifiers, to all packages inhabiting 
	# the same file.
	#
	# this allows us to bring our variables from 
    # procedural core into ::Graphical and ::Text
	# packages. 
	
	# it didn't work out to be as helpful as i'd like
	# because the grammar requires package path anyway

	$help_screen, 		# 
	@help_topic,    # array of help categories
	%help_topic,    # help text indexed by topic
	$use_pager,     # display lengthy output data using pager
	$use_placeholders,  # use placeholders in show_track output
	$text,          # Text::Format object

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
	$default_palette_yml, # not horriffic is about all I can say
					
	$raw_to_disk_format,
	$mix_to_disk_format,
	$mixer_out_format,
	$execute_on_project_load, # Nama text commands 
	$use_group_numbering, # same version number for tracks recorded together

	# .namarc mastering fields
    $mastering_effects, # apply on entering mastering mode
	$eq, 
	$low_pass,
	$mid_pass,
	$high_pass,
	$compressor,
	$spatialiser,
	$limiter,

	$initial_user_mode, # preview, doodle, 0, undef TODO
	
	$yw,			# yaml writer object
	$yr,			# yaml reader object
	%state_c_ops, 	# intermediate copy for storage/retrieval
	$effects_cache_file, # where we keep info on Ecasound
					# and LADSPA effects, presets, etc.
	
	$ecasound, 		# the name to invoke when we want to kill ecasound

	$grammar, 		# filled by Grammar.pm
	$parser,		# for the objected created by Parse::RecDescent
	%iam_cmd,		# for identifying IAM commands in user input
	@nama_commands,# array of commands my functions provide
	%nama_commands,# as hash as well
	$project_root,	# each project will get a directory here
	                # and one .nama directory, also with 
	
					#
					# $ENV{HOME}/.namarc
					# $ENV{HOME}/nama/paul_brocante
					# $ENV{HOME}/nama/paul_brocante/.wav/vocal_1.wav
					# $ENV{HOME}/nama/paul_brocante/Store.yml
					# $ENV{HOME}/nama/.effects_cache
					# $ENV{HOME}/nama/paul_brocante/.namarc 

					 #this_wav_dir = 
	$state_store_file,	# filename for storing @persistent_vars
	$chain_setup_file, # Ecasound uses this 

	$tk_input_channels,# this many radiobuttons appear
	                # on the menubutton
	%cfg,        # 'config' information as hash
	%devices, 		# alias to data in %cfg
	%opts,          # command line options
	%oid_status,    # state information for the chain templates
	$use_monitor_version_for_mixdown, # sync mixdown version numbers
	              	# to selected track versions , not
					# implemented
	$this_track,	 # the currently active track -- 
					 # used by Text UI only at present
	$this_op,      # currently selected effect # future
	$this_mark,    # current mark  # for future

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

# auxiliary track information - saving not required

	%offset,        # index by chain, offset for user-visible effects 
	@mastering_effect_ids,        # effect ids for mastering mode

	@effects,		# static effects information (parameters, hints, etc.)
	%effect_i,		# an index , pn:amp -> effect number
	%effect_j,      # an index , amp -> effect number
	@effects_help,  # one line per effect, for text search

	@ladspa_sorted, # ld
	%effects_ladspa, # parsed data from analyseplugin 
	%effects_ladspa_file, 
					# get plugin filename from Plugin Unique ID
	%ladspa_unique_id, 
					# get plugin unique id from plugin label
	%ladspa_label,  # get plugin label from unique id
	%ladspa_help,   # plugin_label => analyseplugin output
	$e,				# the name of the variable holding
					# the Ecasound engine object.
					
	%e_bound,		# for displaying hundreds of effects in groups
	$unit,			# jump multiplier, 1 or 60 seconds
	%old_vol,		# a copy of volume settings, for muting
	$length,		# maximum duration of the recording/playback if known
 	$jack_system,   # jack soundcard device
	$jack_running,  # jackd status (pid)
	$jack_lsp,      # jack_lsp -Ap

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
	$group_frame,
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

	%parent, # ->{mw} = $mw; # main window
			 # ->{ew} = $ew; # effects window
			 # eventually will contain all major frames
	$group_label, 
	$group_rw, # 
	$group_version, # 
	%track_widget, # for chains (tracks)
	%track_widget_remove, # what to destroy by remove_track
	%effects_widget, # for effects
	@widget_o, # for templates (oids) 
	%widget_o, # 
	%mark_widget, # marks

	@global_version_buttons, # to set the same version for
						  	#	all tracks
	%marks, 		# the actual times # TODO REMOVE
	$markers_armed, # set true to enable removing a mark
	$mark_remove,   # a button that sets $markers_armed
	$time_step,     # widget shows jump multiplier unit (seconds or minutes)
	$clock, 		# displays clock
	$setup_length,  # displays setup running time

	$project_label,	# project name

	$sn_label,		# project load/save/quit	
	$sn_text,
	$sn_load,
	$sn_new,
	$sn_quit,
	$sn_palette, # configure default master window colors
	$sn_namapalette, # configure nama-specific master-window colors
	$sn_effects_palette, # configure effects window colors
	@palettefields, # set by setPalette method
	@namafields,    # field names for color palette used by nama
	%namapalette,     # nama's indicator colors
	%palette,  # overall color scheme
	$rec,      # background color
	$mon,      # background color
	$off,      # background color
	$palette_file, # where to save selections

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
	$build_track_add_mono,
	$build_track_add_stereo,
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
	$old_abg, # initial active background color


	$loopa,  # loopback nodes 
	$loopb,  
	$loop_crossover,
	$loop_boost,

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
	%track_names,   # belongs in Track.pm
	$ch_r,			# recording channel assignment
	$ch_m,			# monitoring channel assignment


	%L,	# for effects
	%M,
	$debug,				# debug level flags for diagnostics
	$debug2,			# for subroutine names as execute
	$debug3,			# deprecated
						
	$OUT,				# filehandle for Text mode print
	#$commands,	# ref created from commands.yml
	%commands,	# created from commands.yml
	%dispatch,  # replacement for existing parser
	$commands_yml, # the string form of commands.yml
	$cop_hints_yml, # ecasound effects hinting

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
	$null_bus,
    $null, # group

	# mastering buses
	
	# we will try to simplify buses... just rules
	# tracks will be supplied to apply() method.
	
	$bypass_bus,
	$mastering_stage1_bus,
	$mastering_stage2_bus,
	$mastering_stage3_bus,
	
	%ti, # track by index (alias %::Track::by_index)
	%tn, # track by name  (alias %::Track::by_name)

	@tracks_data, # staging for saving
	@groups_data, # 
	@marks_data, # 

	$playback_device,       # where to send stereo output
	$playback_device_jack,  # JACK target for stereo output
	$capture_device,    # where to get our inputs
	$capture_device_jack,    # where to get our inputs


	# rules
	
	$mixer_out,
	$mix_down,
	$mix_down_ev,
	$mix_link,
	$mix_setup,
	$mix_setup_mon,
	$mon_setup,
	$rec_file,
	$rec_file_soundcard_jack,
	$rec_setup,
	$rec_setup_soundcard_jack,
	$aux_send,
	$aux_send_soundcard_jack,
	$null_setup,
	
	# rules for mastering
	
	$stage1,
	$stage2,
	$stage3, 

	# mastering mode status

	$mastering_mode,

   # marks and playback looping
   
	$clock_id,		# used in GUI for the Tk event system
					# ->cancel method not reliable
					# for 'repeat' events, so converted to
					# 'after' events
	%event_id,    # events will store themselves with a key
	$set_event,   # the Tk dummy widget used to set events
	@loop_endpoints, # they define the loop
	$loop_enable, # whether we automatically loop

   $previous_text_command, # i want to know if i'm repeating
	$term, 			# Term::ReadLine object
	$controller_ports, # where we listen for MIDI messages
    $midi_inputs,  # on/off/capture

	@already_muted, # for soloing list of Track objects that are 
                    # muted before we begin
    $soloing,       # one user track is on, all others are muted

	%bunch,			# user collections of tracks
	@keywords,      # for autocompletion
	$attribs,       # Term::Readline::Gnu object
	$seek_delay,    # allow microseconds for transport seek
                    # (used with JACK only)
    $prompt,        # for text mode
	$preview,       # am running engine with rec_file disabled
	$unique_inputs_only,  # exclude tracks sharing same source


	%excluded,      # tracks sharing source with other tracks,
	                # after the first
	$memoize,       # do I cache this_wav_dir?
	$hires,        # do I have Timer::HiRes?
	$fade_time, 	# duration for fadein(), fadeout()
	$old_snapshot,  # previous status_snapshot() output
					# to check if I need to reconfigure engine
	$old_group_rw, # previous $tracker->rw setting
	%old_rw,       # previous track rw settings (indexed by track name)
	
	@mastering_track_names, # reserved for mastering mode

);
