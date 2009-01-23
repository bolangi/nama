@help_topic = ( undef, qw(   
                    project
                    track
                    chain_setup
                    transport
                    marks
                    effects
                    group
                    mixdown
                    prompt 

                ) ) ;

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
   project_name, pn          - show the current project name
   create_project, create    - create a new project directory tree 
   get_state, recall, retrieve, restore  - retrieve saved settings
   save_state, keep, save    - save project settings to disk
   exit, quit                - exit program, saving state 
PROJECT

chain_setup => <<SETUP,
   setup, arm                - generate and connect chain setup    
   generate, gen             - generate chain setup
   connect, con              - connect chain setup
   disconnect, dcon          - disconnect chain setup
   show_setup, show          - show status, all tracks
   show_chain_setup, chains  - print .ecs file to STDOUT
SETUP
track => <<TRACK,
   Most of the Track related commands operate on the 'current
   track'. To cut volume for a track called 'sax',  you enter
   'sax mute' or 'sax; mute'. The first part of the
   command sets a new current track. You can also specify a
   current track by number,  i.e.  '4 mute'.

   add_track, add            -  create one or more new tracks
                                example: add sax; r3 
                                    (record sax from input 3) 
                                example: add piano; r synth
                                    (record piano from JACK client "synth") 

   show_tracks, show, tracks -  show status of all tracks
                                and group settings

   show_track, sh            -  show status of current track,
                                including effects, versions, 
                                modifiers,  "sax; sh"

   solo                      -  mute all tracks but current track

   all, nosolo               -  return to pre-solo status

   stereo                    -  set track width to 2 channels

   mono                      -  set track width to 1 channel

   source, src, r            -  set track source to JACK client
                                name or to sound card track number 
                                (9 for channels 9,10 if stereo) 

                             -  with no arguments returns
                                current signal source

   send, out, aux            -  create an auxiliary send, argument 
                                can be channel number or JACK client name


 - version

   set_version, version, ver, n  -  set current track version    

 - rw_status

   rec                     -  set track to REC  
   mon                     -  set track to MON
   off, z                  -  set track OFF (omit from setup)


 - vol/pan 

   pan, p                  -  get/set pan position
   pan_back, pb            -  restore pan after pr/pl/pc  
   pan_center, pc          -  set pan center    
   pan_left, pl            -  pan track fully left    
   pan_right, pr           -  pan track fully right    
   unity                   -  unity volume    
   vol, v                  -  get/set track volume    
   mute, c, cut            -  mute volume 
   unmute, uncut, cc       -  restore muted volume

 - channel assignments

   r, record_channel       -  set input channel number, current track
   m, monitor_channel      -  set output channel number, current track

 - chain object modifiers

   mod, mods, modifiers    - show or assign select/reverse/playat modifiers
                             for current track
   nomod, nomods, 
   nomodifiers             - remove all modifiers from current track
TRACK

transport => <<TRANSPORT,
   start, t           - Start processing
   stop, s            - Stop processing
   rewind, rw         - Rewind  some number of seconds, i.e. rw 15
   forward, fw        - Forward some number of seconds, i.e. fw 75
   setpos, sp         - Set the playback head position, i.e. setpos 49.2
   getpos, gp         - Get the current head position 

   loop_enable, loop  - loop playback between two points
                        example: loop 5.0 200.0 (positions in seconds)
                        example: loop start end (mark names)
                        example: loop 3 4       (mark numbers)
   loop_disable, noloop, nl -  disable looping
   preview             - start engine with WAV recording disabled
                         (for mic check, etc.)

TRANSPORT

marks => <<MARKS,
   list_marks, lm     - list marks showing index, time, name
   next_mark, nm      - jump to next mark 
   previous_mark, pm  - jump to previous mark 
   name_mark, nom     - give a name to current mark 
   to_mark, tom       - jump to a mark by name or index
   remove_mark, rmm   - remove current mark
MARKS

effects => <<EFFECTS,
	
   ladspa-register, lrg       - list LADSPA effects
   preset-register, prg       - list Ecasound presets
   ctrl-register, crg         - list Ecasound controllers 
   add_effect,    fxa, afx    - add an effect to the current track
   insert_effect, ifx, fxi    - insert an effect before another effect
   modify_effect, fxm, mfx    - set, increment or decrement an effect parameter
   remove_effect, fxr, rfx    - remove an effect or controller
   add_controller, acl        - add an Ecasound controller
EFFECTS

group => <<GROUP,
   group_rec, grec, R         - group REC mode 
   group_mon, gmon, M         - group MON mode 
   group_off, goff, MM        - group OFF mode 
   group_version, gver, gv    - select default group version 
   bunch, bn                  - name a group of tracks
                                e.g. bunch strings violins cello bass
   for                        - execute command on several tracks 
                                or a bunch
                                example: for strings; vol +10
                                example: for drumkit congas; mute
GROUP

mixdown => <<MIXDOWN,
   mixdown, mxd                - enable mixdown 
   mixoff, mxo, normal, norm   - disable mixdown 
   mixplay, mxp                - playback a recorded mix 
MIXDOWN

prompt => <<PROMPT,
   At the command prompt, you can enter several types
   of commands:

   Type                        Example
   ------------------------------------------------------------
   Nama commands               load somesong
   Ecasound commands           cs-is-valid
   Shell expressions           ! ls
   Perl code                   eval 2*3     # no need for 'print'

PROMPT
    
);
# print values %help_topic;

$help_screen = <<HELP;

Welcome to Nama help

The help command ('help', 'h') can take several arguments.

help <command>          - show help for <command>
help <fragment>         - show help for all commands matching /<fragment>/
help <topic_number>     - list commands under topic <topic_number> below
help yml                - browse the YAML command source (authoritative)

help is available for the following topics:

1  Project
2  Track
3  Chain setup
4  Transport
5  Marks
6  Effects
7  Group control
8  Mixdown
9  Command prompt 
10 All
HELP
