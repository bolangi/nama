# category: singletons

	# see file ./src/singletons.pl


# category: fixed

	$banner,
	$debug,				# debug level flags for diagnostics
	$debug2,			# for subroutine names as execute
	$debug3,			# deprecated

# category: help

	$help_screen, 		 
	@help_topic,    # array of help categories
	%help_topic,    # help text indexed by topic

# category: text UI

	$use_pager,     # display lengthy output data using pager
	$use_placeholders,  # use placeholders in show_track output

	$grammar, 		# filled by Grammar.pm
	$parser,		# for the objected created by Parse::RecDescent
	$text_wrap,		# Text::Format object
	@format_fields, # data for replies to text commands
	
	$commands_yml,	# commands.yml as string
	%commands,		# created from commands.yml
	%iam_cmd,		# dictionary of Ecasound IAM commands
	@nama_commands,
	%nama_commands,	# as hash

	$term, 			# Term::ReadLine object
	$previous_text_command, # to check for repetition
	@keywords,      # for autocompletion
    $prompt,
	$attribs,       # Term::Readline::Gnu object
	$format_top,    # show_tracks listing
	$format_divider,

	$custom_pl,    # default customization file
	%user_command,
	%user_alias,

# category: UI

	$ui, # object providing class behavior for graphic/text functions

# category: serialization

	@persistent_vars, # a set of variables we save
	@effects_static_vars,# the list of which variables to store and retrieve
	@config_vars,    # contained in config file

# category: config
	
	%opts,          # command line options
	$default,		# the internal default configuration file, as string

# category: routing

	$preview,       # for preview and doodle modes
	
# category: engine, realtime operation

	@ecasound_pids,	# processes started by Nama
	$e,				# the name of the variable holding
					# the Ecasound engine object.
	$run_time,		# engine processing time limit (none if undef)
	$seek_delay,    # delay to allow engine to seek 
					# under JACK before restart
	$fade_time, 	# duration for fadein(), fadeout()

# category: MIDI
					
	%midish_command,	# keywords listing
	$midi_input_dev,
	$midi_output_dev, 
	$controller_ports,	# where we listen for MIDI messages
    $midi_inputs,		# on/off/capture

# category: view waveform

    $waveform_viewer,   # mhwaveedit at present

# category: filenames

	$effects_cache_file, # where we keep info on Ecasound
					# and LADSPA effects, presets, etc.
	$state_store_file,	# filename for storing @persistent_vars
	$effect_chain_file, # for storing effect chains
	$effect_profile_file, # for storing effect templates
	$chain_setup_file, 	# Ecasound uses this 
	$user_customization_file, 


# category: pronouns

	$this_track,	# the currently active track -- 
					# used by Text UI only at present
	$this_mark,    	# current mark  # for future
	$this_bus, 		# current bus
	$this_edit,		# current edit

# category: project

	$project_name,	# current project name

	# buses
	
	$main_bus, 
	$main, # main group
	$null_bus,
    $null, # null group
	@system_buses, 
	%is_system_bus, 

	# aliases
	
	%ti, # track by index (alias to %::Track::by_index)
	%tn, # track by name  (alias to %::Track::by_name)
	%bn, # bus   by name  (alias to %::Bus::by_name)
	%gn, # group by name  (alias to %::Group::by_name)

# category: effects

	$magical_cop_id, # cut through five levels of subroutines
	$cop_hints_yml,  # ecasound effects hints

	%offset,        # index by chain, offset for user-visible effects 
					# pertains to engine

	@mastering_effect_ids,        # effect ids for mastering mode
	$tkeca_effects_data,	# original tcl code, actually
	%L,
	%M,

	@already_muted, # for soloing, a list of Track objects that are 
					# muted before we begin
    $soloing,       # one user track is on, all others are muted

	%effect_chain, # named effect sequences
	%effect_profile, # effect chains for multiple tracks

	%mute_level,	# 0 for ea as vol control, -127 for eadb
	%fade_out_level, # 0 for ea, -40 for eadb
	$fade_resolution, # steps per second
	%unity_level,	# 100 for ea, 0 for eadb
	
	$default_fade_length, 

# category: external resources (ALSA, JACK, etc.)

	$jack_running,  # jackd server status 
	$jack_plumbing, 
	$jack_lsp,      # jack_lsp -Ap
	$fake_jack_lsp, # for testing
	%jack,			# jack clients data from jack_lsp
	$sampling_frequency, # of souncard

# category: events

	%event_id,    # events will store themselves with a key

	%duplicate_inputs, # named tracks will be OFF in doodle mode
	%already_used,  #  source => used_by

	$memoize,       # do I cache this_wav_dir?
	$hires,        # do I have Timer::HiRes?

	$old_snapshot,  # previous status_snapshot() output
					# to check if I need to reconfigure engine
	%old_rw,       # previous track rw settings (indexed by track name)
	
	@mastering_track_names, # reserved for mastering mode

	$disable_auto_reconfigure, # for debugging

	%cooked_record_pending, # an intermediate mixdown for tracks
	$sock, 			# socket for Net-ECI mode
	%versions,		# store active versions for use after engine run
	$track_snapshots, # to save recalculating for each IO object
	$regenerate_setup, # force us to generate new chain setup
	
	%wav_info,			# caches path/length/format/modify-time
	
# category: edits

	$offset_run_flag, # indicates edit or offset_run mode
	$offset_run_start_time,
	$offset_run_end_time,
	$offset_mark,

	@edit_points, 
	$edit_playback_end_margin, # play a little more after edit recording finishes
	$edit_crossfade_time,

# category: Graphical UI, GUI

	$tk_input_channels,# for menubutton
	
	# variables for GUI text input widgets

	$project,		
	$track_name,
	$ch_r,			# recording channel assignment
	$ch_m,			# monitoring channel assignment
	$save_id,		# name for save file

	$default_palette_yml, # default GUI colors

	# Widgets
	
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

	$sn_save_text,# text entry widget
	$sn_save,	# button to save settings
	$sn_recall,	# button to recall settings

# end
