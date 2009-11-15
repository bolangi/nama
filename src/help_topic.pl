@help_topic = qw( all
                    project
                    track
                    chain_setup
                    transport
                    marks
                    effects
                    group
                    bus
                    mixdown
                    prompt 
                    diagnostics

                ) ;

%help_topic = (

help => <<HELP,
   help <command>          - show help for <command>
   help <fragment>         - show help for commands matching /<fragment>/
   help <ladspa_id>        - invoke analyseplugin for info on a LADSPA id
   help <topic_number>     - list commands under <topic_number> 
   help <topic_name>       - list commands under <topic_name> (lower case)
   help yml                - browse command source file
HELP

project => <<PROJECT,
   load_project, load        - load an existing project 
   project_name, name          - show the current project name
   create_project, create    - create a new project directory tree 
   list_projects, lp         - list all Nama projects
   get_state, recall, retrieve, restore  - retrieve saved settings
   save_state, keep, save    - save project settings to disk
   memoize                   - enable WAV directory cache (default OFF)
   unmemoize                 - disable WAV directory cache
   exit, quit                - exit program, saving state 
PROJECT

chain_setup => <<SETUP,
   arm                       - generate and connect chain setup    
   show_setup, show          - show status, all tracks
   show_chain_setup, chains  - show Ecasound Setup.ecs file
   generate, gen             - generate chainsetup for audio processing
      (usually not necessary)
   connect, con              - connect chainsetup (usually not necessary)
   disconnect, dcon          - disconnect chainsetup (usually not necessary)
SETUP

track => <<TRACK,
   Most of the Track related commands operate on the 'current
   track'. To cut volume for a track called 'sax',  you enter
   'sax mute' or 'sax; mute'. The first part of the
   command sets a new current track. You can also specify a
   current track by number,  i.e.  '4 mute'.

   add_track, add            -  create one or more new tracks
                                example: add sax; r 3 
                                    (record sax from input 3) 
                                example: add piano; r synth
                                    (record piano from JACK client "synth") 

   link_track, link          -  create a new, read-only track that uses audio
                                files from an existing track. 

                                example: link_track new_piano piano
                                example: link_track intro Mixdown my_song_intro 

   import_audio, import      - import a WAV file, resampling if necessary

   remove_track, rmt         - remove effects, parameters and GUI for current
                               track

   show_tracks, show, tracks -  show status of all tracks
                                and group settings

   show_track, sh            -  show status of current track,
                                including effects, versions, 
                                modifiers,  "sax; sh"

   stereo                    -  set track width to 2 channels

   mono                      -  set track width to 1 channel

   solo                      -  mute all tracks but current track

   all, nosolo               -  return to pre-solo status

 - channel inputs and outputs 

   source, src, r            -  set track source

                                sax r 3 (record from soundcard channel 3) 

                                organ r synth (record from JACK client "synth")

                             -  with no arguments returns current signal source

   send, out, m, aux         -  create an auxiliary send, argument 
                                can be channel number or JACK client name

                             -  currently one send allowed per track

                             -  not needed for most setups
 - version 

   set_version, version, ver, n  -  set current track version

   list_version, lver, lv        - list version numbers of current track

 - rw_status

   rec                     -  set track to REC  
   mon                     -  set track to MON
   off, z                  -  set track OFF (omit from setup)
   rec_defeat, rd          -  toggle track WAV recording on/off

 - vol/pan 

   pan, p                  -  get/set pan position
   pan_back, pb            -  restore pan after pr/pl/pc  
   pan_center, pc          -  set pan center    
   pan_left, pl            -  pan track fully left    
   pan_right, pr           -  pan track fully right    
   unity                   -  unity volume    
   vol, v                  -  get/set track volume    
                              sax vol + 20 (increase by 20)
                              sax vol - 20 (reduce by 20)
                              sax vol * 3  (multiply by 3)
                              sax vol / 2  (cut by half) 
   mute, c, cut            -  mute volume 
   unmute, uncut, cc       -  restore muted volume

 - chain object modifiers

   mod, mods, modifiers    - show or assign select/reverse/playat modifiers
                             for current track
   nomod, nomods, 
   nomodifiers             - remove all modifiers from current track

 - signal processing

   ecanormalize, normalize, norm 
                           - run ecanormalize on current track version
   ecafixdc, fixdc         - run ecafixdc on current track version
   autofix_tracks, autofix - fixdc and normalize selected versions of all MON
                             tracks

 - cutting and time shifting

   set_region,    srg      - specify a track region using times or mark names
   new_region,    nrg      - define a region creating an auxiliary track
   remove_region, rrg      - remove auxiliary track or region definition
   shift_track,   shift    - set playback delay for track/region
   unshift_track, unshift  - eliminate playback delay for track/region

 - hazardous commands for advanced users

   set_track, set          - directly set current track parameters

   destroy_current_wav     - unlink current track's selected WAV version.
                             Nama's only destructive command. USE WITH CARE!

TRACK

transport => <<TRANSPORT,
   start, t, SPACE    -  Start processing. SPACE must be at beginning of 
                         command line.
   stop, s, SPACE     -  Stop processing. SPACE must be at beginning of 
                         command line.
   rewind, rw         -  Rewind  some number of seconds, i.e. rw 15
   forward, fw        -  Forward some number of seconds, i.e. fw 75
   setpos, sp         -  Set the playback head position, i.e. setpos 49.2
   getpos, gp         -  Get the current head position 
   to_start, beg      - set playback head to start
   to_end, end        - set playback head to end

   loop_enable, loop  -  loop playback between two points
                         example: loop 5.0 200.0 (positions in seconds)
                         example: loop start end (mark names)
                         example: loop 3 4       (mark numbers)
   loop_disable, noloop, nl
                      -  disable looping

   preview            -  start engine with WAV recording disabled
                         (for mic check, etc.) Release with 'arm'.

   doodle             -  start engine with all live inputs enabled.
                         Release with 'preview' or 'arm'.
                         
   ecasound_start, T  - ecasound-only start (not usually needed)

   ecasound_stop, S   - ecasound-only stop (not usually needed)


TRANSPORT

marks => <<MARKS,
   new_mark,      mark, k     - drop mark at current position, with optional name
   list_marks,    lmk,  lm    - list marks showing index, time, name
   next_mark,     nmk,  nm    - jump to next mark 
   previous_mark, pmk,  pm    - jump to previous mark 
   name_mark,           nom   - give a name to current mark 
   to_mark,       tmk,  tom   - jump to a mark by name or index
   remove_mark,   rmk,  rom   - remove current mark
   modify_mark, move_mark, 
    mmk, mm                   - change the time setting of current mark
MARKS

effects => <<EFFECTS,
    
 - information commands

   ladspa_register, lrg       - list LADSPA effects
   preset_register, prg       - list Ecasound presets
   ctrl_register,   crg       - list Ecasound controllers 
   find_effect,     fe        - list available effects matching arguments
                                example: find_effect reverb
   help_effect, he            - full information about an effect 
                                example: help_effect 1209 
                                  (information about LADSPA plugin 1209)
                                example: help_effect valve
                                  (information about LADSPA plugin valve)

 - effect manipulation commands

   add_effect,     afx        - add an effect to the current track
   add_controller, acl        - add an Ecasound controller
   insert_effect,  ifx        - insert an effect before another effect
   modify_effect,  mfx,
     modify_controller, mcl   - set, increment or decrement effect parameter
   remove_effect, rfx         
     remove_controller, rcl   - remove an effect or controller
   append_effect              - add effect to the end of current track
                                effect list 

-  send/receive inserts

   add_insert_cooked,  ainc   - add a post-fader insert to the current track
   remove_insert,      rin    - remove current track's insert
   set_insert_wetness, wet    - set/query insert wetness 
                                example: wet 99 (99% wet, 1% dry)

-  effect chains

   new_effect_chain,   nec    - define a new effect chain
   add_effect_chain,   aec    - add an effect chain to the current track
   delete_effect_chain,dec    - delete an effect chain
   list_effect_chains, lec    - list effect chains and their parameters
   bypass_effects,     bye    - suspend current track effects except vol/pan
   replace_effects,    rep    - restore track effects

EFFECTS

group => <<GROUP,
   group_rec, grec, R         - group REC mode 
   group_mon, gmon, M         - group MON mode 
   group_off, goff, Z         - group OFF mode 
   group_version, gver, gv    - select default group version 
                              - used for switching among 
                                several multitrack recordings
   new_bunch, bunch, nb       - name a bunch of tracks
                                e.g. bunch strings violins cello bass
                                e.g. bunch 3 4 6 7 (track indexes)
   list_bunches,     lb       - list groups of tracks (bunches)
   remove_bunches,   rb       - remove bunch definitions

   for                        - execute commands on several tracks 
                                by name, or by specifying a group or bunch
                                example: for strings; vol +10
                                example: for drumkit congas; mute
                                example: for 3 5; vol * 1.5
                                example: for all; version 5;; show
                                  'show' follows ';;' so executes only once
                
GROUP

bus => <<BUS,
   add_send_bus_raw,    asbr  - create bus and slave tracks for 
                                sending pre-fader track signals
   add_send_bus_cooked, asbc  - as above, for post-fader signals
   update_send_bus,     usb   - refresh send bus track list
   remove_bus,                - remove a bus
   add_sub_bus,         asub  - create a sub-bus feeding a regular user track
                                of the same name
                                example: add_sub_bus Strings 
                                         add_tracks violin cello bass
                                         for cello violin bass; set bus Strings

BUS

mixdown => <<MIXDOWN,
   mixdown,    mxd             - enable mixdown 
   mixoff,     mxo             - disable mixdown 
   mixplay,    mxp             - playback a recorded mix 
   automix                     - normalize track vol levels, then mixdown
   master_on,  mr              - enter mastering mode
   master_off, mro             - leave mastering mode
MIXDOWN

prompt => <<PROMPT,
   At the command prompt, you can enter several types
   of commands:

   Type                        Example
   ------------------------------------------------------------
   Nama commands               load somesong
   Ecasound commands           cs-is-valid
   Shell expressions           ! ls
   Perl code                   eval 2*3     # prints '6'

PROMPT

diagnostics => <<DIAGNOSTICS,

   dump_all,   dumpall,   dumpa - dump most internal state
   dump_track, dumpt,     dump  - dump current track data
   dump_group, dumpgroup, dumpg - dump group settings for user tracks
   show_io,    showio           - show chain inputs and outputs
   engine_status, egs           - display ecasound audio processing engine
                                   status
DIAGNOSTICS
    
);
# print values %help_topic;

$help_screen = <<HELP;

Welcome to Nama help

The help command ('help', 'h') can take several arguments.

help <command>          - show help for <command>
help <fragment>         - show help for all commands matching /<fragment>/
help <topic_number>     - list commands under topic <topic_number> below
help yml                - browse the YAML command source

help is available for the following topics:

0  All
1  Project
2  Track
3  Chain setup
4  Transport
5  Marks
6  Effects
7  Group control
8  Buses
9  Mixdown
10 Command prompt 
11 Diagnostics
HELP
