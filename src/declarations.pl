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

	$banner,
	$help_screen, 		# 
	@help_topic,    # array of help categories
	%help_topic,    # help text indexed by topic
	$use_pager,     # display lengthy output data using pager
	$use_placeholders,  # use placeholders in show_track output
	$text_wrap,          # Text::Format object

	$ui, # object providing class behavior for graphic/text functions

	@persistent_vars, # a set of variables we save
					  	# as one big config file
	@effects_static_vars,	# the list of which variables to store and retrieve
	@effects_dynamic_vars,		# same for all chain operators
	@config_vars,    # contained in config file
	%abbreviations, # for replacements in config files

	$ecasound_globals_realtime,     # .namarc field
	$ecasound_globals_default,  # .namarc field
	$ecasound_tcp_port,  # for Ecasound NetECI interface
	@ecasound_pids,      # started by Nama
	$saved_version, # copy of $VERSION saved with settings in State.yml


	$default,		# the internal default configuration file, as string
	$default_palette_yml, # default GUI colors
					
	$raw_to_disk_format,
	$mix_to_disk_format,
	$cache_to_disk_format,
	$mixer_out_format,
	$execute_on_project_load, # Nama text commands 
	$use_group_numbering, # same version number for tracks recorded together

	# .namarc mastering fields
    $mastering_effects, # apply on entering mastering mode
	$volume_control_operator,
	$eq, 
	$low_pass,
	$mid_pass,
	$high_pass,
	$compressor,
	$spatialiser,
	$limiter,

	# .namarc MIDI
	
	$midish_enable,       # using midish
	%midish_command,     # keywords listing
	$midi_input_dev,
	$midi_output_dev, 

	# .namarc jack.plumbing
	
	$use_jack_plumbing,

	$initial_user_mode, # preview, doodle, 0, undef TODO
	
	%state_c_ops, 	# intermediate copy for storage/retrieval
	$effects_cache_file, # where we keep info on Ecasound
					# and LADSPA effects, presets, etc.
	
	$ecasound, 		# the name to invoke when we want to kill ecasound

	$grammar, 		# filled by Grammar.pm
	$parser,		# for the objected created by Parse::RecDescent
	%iam_cmd,		# for identifying IAM commands in user input
	@nama_commands,# array of commands my functions provide
	%nama_commands,# as hash as well
	$project_root,	

					# Nama directory structure and files

					# ~/.namarc						# config file
					# ~/nama/untitled				# project directory
					# ~/nama/untitled/.wav			# wav directory
					# ~/nama/untitled/State.yml		# project state
					# ~/nama/untitled/Setup.ecs		# Ecasound chain setup
					# ~/nama/.effects_cache			# static effects data
					# ~/nama/effect_chains			# Nama effect presets
					# ~/nama/effect_profiles		# Nama effect profiles

	$state_store_file,	# filename for storing @persistent_vars
	$effect_chain_file, # for storing effect chains
	$effect_profile_file, # for storing effect templates
	$chain_setup_file, # Ecasound uses this 

	$soundcard_channels,# channel selection range 
	$tk_input_channels,# alias for above
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
	$this_track_name, # for save/restore 
	$old_this_track, # when we need to remember previous setting
	$this_op,      # current effect
	$this_mark,    # current mark  # for future
	$this_bus, 		# current bus

	@format_fields, # data for replies to text commands

	$project,		# variable for GUI text input
	$project_name,	# current project name
	%state_c,		# for backwards compatilility

	### for effects

	$cop_id, 		# autoincrement counter
					# chain operator id, that how we create, 
					# store, find them, adjust them, and destroy them,
					# per track or per project?
	$magical_cop_id, # cut through five levels of subroutines
	%cops,			 # chain operators stored here
	%copp,			# their parameters for effect update
	%copp_exp,      # for log-scaled sliders


	%offset,        # index by chain, offset for user-visible effects 
	@mastering_effect_ids,        # effect ids for mastering mode

	@effects,		# static effects information (parameters, hints, etc.)
	%effect_i,		# pn:preset_name -> effect number
	                # el:ladspa_label -> effect number
	
	%effect_j,      # preset_name -> pn:preset_name
	                # ladspa_label -> el:ladspa_label
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
	$run_time,		# engine processing time limit (none if undef)
 	$jack_system,   # jack soundcard device
	$jack_running,  # jackd server status 
	$jack_plumbing, # jack.plumbing daemon status
	$jack_lsp,      # jack_lsp -Ap
	$fake_jack_lsp, # for testing
	%jack,			# jack clients data from jack_lsp

	@input_chains,	# list of input chain segments 
	@output_chains, # list of output chain segments
	@post_input,	# post-input chain operators
	@pre_output, 	# pre-output chain operators

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
	$commands_yml, # the string form of commands.yml
	$cop_hints_yml, # ecasound effects hinting

	$save_id, # text variable
	$sn_save_text,# text entry widget
	$sn_save,	# button to save settings
	$sn_recall,	# button to recall settings

	# new object core
	
	$main_bus, 
	$main, # main group
	$null_bus,
    $null, # null group

	%ti, # track by index (alias to %::Track::by_index)
	%tn, # track by name  (alias to %::Track::by_name)
	%bn, # bus   by name  (alias to %bn)

	# for serialization (save/restore)
	
	@tracks_data,
	@marks_data,
	@inserts_data,
	@bus_data,
	@fade_data,
	@edit_data,
	@groups_data, # for backward compatibility only

	@system_buses, # 
	%is_system_bus, # 

	$alsa_playback_device,
	$alsa_capture_device,

	$main_out, # boolean: route audio output to soundcard?

	# mastering mode status

	$mastering_mode,

   # marks and playback looping
   
	$clock_id,		# used in GUI for the Tk event system
					# ->cancel method not reliable
					# for 'repeat' events, so converted to
					# 'after' events
	%event_id,    # events will store themselves with a key
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
	$seek_delay,    # delay to allow engine to seek 
					# under JACK before restart
	$jack_seek_delay, # user override for default $seek_delay logic
					
    $prompt,        # for text mode
	$preview,       # am running engine with rec_file disabled
	%duplicate_inputs, # named tracks will be OFF in doodle mode
	%already_used,  #  source => used_by
	$memoize,       # do I cache this_wav_dir?
	$hires,        # do I have Timer::HiRes?
	$fade_time, 	# duration for fadein(), fadeout()
	$old_snapshot,  # previous status_snapshot() output
					# to check if I need to reconfigure engine
	$old_group_rw, # previous $main->rw setting
	%old_rw,       # previous track rw settings (indexed by track name)
	
	@mastering_track_names, # reserved for mastering mode
	@command_history,
	$disable_auto_reconfigure, # for debugging

	$g, 			# Graph var, for chain setup
	%cooked_record_pending, # an intermediate mixdown for tracks
	$press_space_to_start_transport, #  in text mode
	%effect_chain, # named effect sequences
	%effect_profile, # effect chains for multiple tracks
	$sock, 			# socket for Net-ECI mode
	%versions,		# store active versions for use after engine run
	@io, 			# accumulate IO objects for generating setup
	$track_snapshots, # to save recalculating for each IO object
	$chain_setup,	# current chain setup
	%mute_level,	# 0 for ea as vol control, -127 for eadb
	%fade_out_level, # 0 for ea, -40 for eadb
	$fade_resolution, # steps per second
	%unity_level,	# 100 for ea, 0 for eadb
	
	$default_fade_length, 
	$regenerate_setup, # force us to generate new chain setup
	%is_ecasound_chain,   # suitable for c-select
	
	%wav_info,			# caches path/length/format/modify-time
	
	$autosave_interval, # how frequently to save
	$quietly_remove_tracks, 

	
	# Edits

	$edit_mode,
	@edit_points, 
	$this_edit, 	# current edit
	$edit_playback_end_margin, # play a little more after edit recording finishes
	$edit_crossfade_time, 	#
	$last_edit_name,  	# for save/restore

	$format_top,    # show_tracks listing
	$format_divider,

	$user_customization_file, 
	$custom_pl,    # default customization file
	%user_command,
	%user_alias,
	
	$offset_run_start_time,
	$offset_run_end_time,
	$offset_mark,

);
