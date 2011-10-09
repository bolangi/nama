# category: singletons

	# see file ./src/singletons.pl


# category: fixed

	$debug,				# debug level flags for diagnostics
	$debug2,			# for subroutine names as execute
	$debug3,			# deprecated

# category: help

# 	$help->{screen}, 		 
# 	@{$help->{arr_topic}},    # array of help categories
# 	%{$help->{topic}},    # help text indexed by topic

# category: text UI

# 	$config->{use_pager},     # display lengthy output data using pager
# 	$config->{use_placeholders},  # use placeholders in show_track output

# 	$text->{grammar}, 		# filled by Grammar.pm
# 	$text->{parser},		# for the objected created by Parse::RecDescent
# 	$text->{wrap},		# Text::Format object
# 	@{$text->{format_fields}}, # data for replies to text commands
	
# 	$text->{commands_yml},	# commands.yml as string
# 	%{$text->{commands}},		# created from commands.yml
# 	%{$text->{iam}},		# dictionary of Ecasound IAM commands
# 	@{$text->{arr_nama_cmds}},
# 	%{$text->{nama_commands}},	# as hash

# 	$text->{term}, 			# Term::ReadLine object
# 	$text->{previous_cmd}, # to check for repetition
# 	@{$text->{keywords}},      # for autocompletion
#     $text->{prompt},
$prompt,
# 	$text->{term_attribs},       # Term::Readline::Gnu object
# 	$text->{format_top},    # show_tracks listing
# 	$text->{format_divider},

# 	$file->{custom_pl},    # default customization file
# 	%{$text->{user_command}},
# 	%{$text->{user_alias}},

# category: UI

	$ui, # object providing class behavior for graphic/text functions

# category: serialization

	@persistent_vars, # a set of global variables we save
	@new_persistent_vars, # variables and hash entries
	@effects_static_vars,# the list of which variables to store and retrieve
	@config_vars,    # contained in config file

# category: config
	
# 	%{$config->{opts}},          # command line options
# 	$config->{default},		# the internal default configuration file, as string

# category: routing

# 	$mode->{preview},       # for preview and doodle modes
	
# category: engine, realtime operation

# 	@{$engine->{pids}},	# processes started by Nama
# 	$engine->{ecasound},				# the name of the variable holding
					# the Ecasound engine object.
# 	$setup->{runtime_limit},		# engine processing time limit (none if undef)
# 	$config->{engine_jack_seek_delay},    # delay to allow engine to seek 
					# under JACK before restart
# 	$config->{engine_fade_length_on_start_stop}, 	# duration for fadein(), fadeout()

# category: MIDI
					
# 	%{$midi->{keywords}},	# keywords listing
# 	$midi->{input_dev},
# 	$midi->{output_dev}, 
# 	$midi->{controller_ports},	# where we listen for MIDI messages
#     $midi->{inputs},		# on/off/capture

# category: filenames

# 	$file->{effects_cache}, # where we keep info on Ecasound
					# and LADSPA effects, presets, etc.
# 	$file->{state_store},	# filename for storing @persistent_vars
# 	$file->{effect_chain}, # for storing effect chains
# 	$file->{effect_profile}, # for storing effect templates
# 	$file->{chain_setup}, 	# Ecasound uses this 
# 	$file->{user_customization}, 


# category: pronouns

	$this_track,	# the currently active track -- 
					# used by Text UI only at present
	$this_mark,    	# current mark  # for future
	$this_bus, 		# current bus
	$this_edit,		# current edit

# category: project

# 	$gui->{_project_name}->{name},	# current project name

	# buses
	
# 	$bn{Main}, 
# 	$gn{Main}, # main group
# 	$bn{null},
# 	%{$config->{_is_system_bus}}, 

	# aliases
	
	%ti, # track by index (alias to %::Track::by_index)
	%tn, # track by name  (alias to %::Track::by_name)
	%bn, # bus   by name  (alias to %::Bus::by_name)
	%gn, # group by name  (alias to %::Group::by_name)

# category: effects

# 	$fx->{magical_cop_id}, # cut through five levels of subroutines
# 	$fx->{ecasound_effect_hints},  # ecasound effects hints

# 	%{$fx->{offset}},        # index by chain, offset for user-visible effects 
					# pertains to engine

# 	@{$mastering->{fx_ids}},        # effect ids for mastering mode
# 	@{$fx->{muted}}, # for soloing, a list of Track objects that are 
					# muted before we begin
#     $mode->{soloing},       # one user track is on, all others are muted

# 	%{$fx->{chain}}, # named effect sequences
# 	%{$fx->{profile}}, # effect chains for multiple tracks

# 	%{$fx->{mute_level}},	# 0 for ea as vol control, -127 for eadb
# 	%{$fx->{fade_out_level}}, # 0 for ea, -40 for eadb
# 	$fx->{fade_resolution}, # steps per second
# 	%{$fx->{unity_level}},	# 100 for ea, 0 for eadb
	
# 	$config->{engine_fade_default_length}, 

# category: external resources (ALSA, JACK, etc.)

# 	$jack->{jackd_running},  # jackd server status 
# 	$jack->{ports_list_text},      # jack_lsp -Ap
# 	$jack->{fake_ports_list}, # for testing
# 	%{$jack->{clients}},			# jack clients data from jack_lsp
# 	$config->{sampling_freq}, # of souncard

# category: events

# 	%{$engine->{events}},    # events will store themselves with a key

# 	%{$setup->{tracks_with_duplicate_inputs}}, # named tracks will be OFF in doodle mode
# 	%{$setup->{inputs_used}},  #  source => used_by

# 	$config->{memoize},       # do I cache this_wav_dir?
# 	$config->{hires_timer},        # do I have Timer::HiRes?

# 	$setup->{_old_snapshot},  # previous status_snapshot() output
					# to check if I need to reconfigure engine
# 	%{$setup->{_old_track_rw_status}},       # previous track rw settings (indexed by track name)
	
# 	@{$mastering->{track_names}}, # reserved for mastering mode

# 	$config->{disable_auto_reconfigure}, # for debugging

# 	%{$setup->{cooked_record_pending}}, # an intermediate mixdown for tracks
# 	$engine->{socket}, 			# socket for Net-ECI mode
# 	$setup->{track_snapshots}, # to save recalculating for each IO object
# 	$setup->{changed}, # force us to generate new chain setup
	
# 	%{$setup->{wav_info}},			# caches path/length/format/modify-time
	
# category: edits

# 	$mode->{offset_run}, # indicates edit or offset_run mode
# 	$setup->{offset_run}->{start_time},
# 	$setup->{offset_run}->{end_time},
# 	$setup->{offset_run}->{mark},

# 	@{$setup->{edit_points}}, 
# 	$config->{edit_playback_end_margin}, # play a little more after edit recording finishes
# 	$config->{edit_crossfade_time},

# category: Graphical UI, GUI

# 	$config->{soundcard_channels},# for menubutton
	
	# variables for GUI text input widgets

# 	$gui->{_project_name},		
# 	$gui->{_track_name},
# 	$gui->{_chr},			# recording channel assignment
# 	$gui->{_chm},			# monitoring channel assignment
# 	$gui->{_save_id},		# name for save file

	# Widgets
	
# 	$gui->{mw}, 			# main window
# 	$gui->{ew}, 			# effects window
# 	$gui->{canvas}, 		# to lay out the effects window

	# each part of the main window gets its own frame
	# to control the layout better

# 	$gui->{load_frame},
# 	$gui->{add_frame},
# 	$gui->{group_frame},
# 	$gui->{time_frame},
# 	$gui->{clock_frame},
	$oid_frame,
# 	$gui->{track_frame},
# 	$gui->{fx_frame},
# 	$gui->{iam_frame},
# 	$gui->{perl_frame},
# 	$gui->{transport_frame},
# 	$gui->{mark_frame},
# 	$gui->{seek_frame}, # forward, rewind, etc.

	## collected widgets (i may need to destroy them)

# 	%{$gui->{parents}}, # ->{mw} = $gui->{mw}; # main window
# 			 # ->{ew} = $gui->{ew}; # effects window
			 # eventually will contain all major frames
# 	$gui->{group_label}, 
# 	$gui->{group_rw}, # 
# 	$gui->{group_version}, # 
# 	%{$gui->{tracks}}, # for chains (tracks)
# 	%{$gui->{tracks_remove}}, # what to destroy by remove_track
# 	%{$gui->{fx}}, # for effects
	@widget_o, # for templates (oids) 
	%widget_o, # 
# 	%{$gui->{marks}}, # marks

# 	@{$gui->{global_version_buttons}}, # to set the same version for
						  	#	all tracks
# 	$gui->{_markers_armed}, # set true to enable removing a mark
# 	$gui->{mark_remove},   # a button that sets $gui->{_markers_armed}
# 	$gui->{seek_unit},     # widget shows jump multiplier unit (seconds or minutes)
# 	$gui->{clock}, 		# displays clock
# 	$gui->{setup_length},  # displays setup running time

# 	$gui->{project_head},	# project name

# 	$gui->{project_label},		# project load/save/quit	
# 	$gui->{project_entry},
# 	$gui->{load_project},
# 	$gui->{new_project},
# 	$gui->{quit},
# 	$gui->{_palette}, # configure default master window colors
# 	$gui->{_nama_palette}, # configure nama-specific master-window colors
# 	$gui->{_fx_palette}, # configure effects window colors
# 	@{$gui->{_palette_fields}}, # set by setPalette method
# 	@{$gui->{_nama_fields}},    # field names for color palette used by nama
# 	%{$gui->{_nama_palette}},     # nama's indicator colors
# 	%{$gui->{_palette}},  # overall color scheme
# 	$gui->{rec_bg},      # background color
# 	$gui->{mon_bg},      # background color
# 	$gui->{off_bg},      # background color
# 	$file->{gui_palette}, # where to save selections

	# add track gui
	
# 	$gui->{add_track}->{label},
# 	$gui->{add_track}->{text_entry},
# 	$gui->{add_track}->{add_mono},
# 	$gui->{add_track}->{add_stereo},
# 	$gui->{add_track}->{rec_label},
# 	$gui->{add_track}->{rec_text},
# 	$gui->{add_track}->{mon_label},
# 	$gui->{add_track}->{mon_text},

	# transport controls
	
# 	$gui->{engine_label},
# 	$gui->{engine_arm},
	$transport_setup, # unused
	$transport_connect, # unused
# 	$gui->{engine_disconnect},
	$transport_new,
# 	$gui->{engine_start},
# 	$gui->{engine_stop},

# 	$gui->{_old_bg}, # initial background color.
# 	$gui->{_old_abg}, # initial active background color

# 	$gui->{savefile_entry},# text entry widget
# 	$gui->{save_project},	# button to save settings
# 	$gui->{load_savefile},	# button to recall settings

# end
=comment
# category: effects_cache 
@effects_static_vars = qw(

	@effects		# static effects information (parameters, hints, etc.)
	%effect_i		# pn:preset_name -> effect number
	                # el:ladspa_label -> effect number
	
	%effect_j      # preset_name -> pn:preset_name
	                # ladspa_label -> el:ladspa_label
	@effects_help  # one line per effect, for text search

	@ladspa_sorted # ld
	%effects_ladspa # parsed data from analyseplugin 
	%effects_ladspa_file 
					# get plugin filename from Plugin Unique ID
	%ladspa_unique_id 
					# get plugin unique id from plugin label
	%ladspa_label  # get plugin label from unique id
	%ladspa_help   # plugin_label => analyseplugin output
	%e_bound		# GUI: for displaying hundreds of effects in groups
);
=cut
