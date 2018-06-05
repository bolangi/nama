@{$help->{arr_topic}} = qw( all
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
                    edits
                    fades
                    command_line_options
                ) ;

%{$help->{topic}} = (

help => <<HELP,
   help <command>          - show help for <command>
   help <fragment>         - show help for commands matching /<fragment>/
   help <ladspa_id>        - invoke analyseplugin for info on a LADSPA id
   help <topic_number>     - list commands under <topic_number> 
   help <topic_name>       - list commands under <topic_name> (lower case)
HELP

project => <<PROJECT,
   load-project, load        - load an existing project 
   project-name, name        - show the current project name
   create-project, create    - create a new project directory tree 
   list-projects, lp         - list all Nama projects
   get-state, get            - retrieve named file or tag
   save-state, keep, save    - save state as file or tag
   exit, quit                - exit program, saving state 

 (Version control)

   save                      - save, commit and tag with <tagname>
   get                       - checkout tag <tagname> 
                               or associated branch and load
   branch, br                - switch to designated branch and load
   list-branches, lbr        - list branches and tags (without arguments)
   new-branch, nbr           - create a new branch starting at the current 
                               commit or a specified commit 
   tag                       - tag current commit with a name and optional 
                               message
   
PROJECT

chain_setup => <<SETUP,
   show-setup, show          - show status, all tracks
   show-chain-setup, chains  - show Ecasound Setup.ecs file
   arm                       - generate and connect chain setup (not usually necessary)

SETUP

track => <<TRACK,

   add-track, add            -  create one or more new tracks
                                example: add sax; r 3 
                                    (record sax from input 3) 
                                example: add piano; r synth
                                    (record piano from JACK client "synth") 

 - track status

   rec                     -  set track to REC (record and monitor live signal source)
   mon                     -  set track to MON (monitor live signal source)
   play                    -  set track to PLAY (WAV file playback)
   off                     -  set track OFF (omit from setup)

 - vol/pan 

   pan, p                  -  get/set pan position
   pan-back, pb            -  restore pan after pr/pl/pc  
   pan-center, pc          -  set pan center    
   pan-left, pl            -  pan track fully left    
   pan-right, pr           -  pan track fully right    
   unity                   -  unity volume    
   vol, v                  -  get/set track volume    
                              sax vol + 20 (increase by 20)
                              sax vol - 20 (reduce by 20)
                              sax vol * 3  (multiply by 3)
                              sax vol / 2  (cut by half) 
   mute, c, cut            -  mute volume 
   unmute, nomute, uncut, C -  restore muted volume

   import-audio, import      - import a WAV file, resampling if necessary

   remove-track              - remove effects, parameters and GUI for current
                               track

   show-tracks, show, tracks -  show status of all tracks

   show-track, sh            -  show status of current track,
                                including effects, versions, 
                                modifiers,  "sax sh"

   show-bus-tracks, shb      -  show tracks of current bus

   show-tracks-all showa sha - show all tracks, including hidden

   link-track, link          -  create a new, read-only track that uses audio
                                files from an existing track. 

                                example: link-track new-piano piano
                                example: link-track intro Mixdown my-song-intro 



   stereo                    -  set track width to 2 channels

   mono                      -  set track width to 1 channel

   solo                      -  mute all tracks but current track

   all, nosolo               -  return to pre-solo status

 - track inputs and outputs 

   source, src, r            -  set track source
                             -  with no arguments returns current signal source

    ----------------------------------------------------------
    for this input              use this command
    ----------------------------------------------------------

     * soundcard channel 3      source 3 

     * JACK client              source fluidsynth
     
     * JACK port                source fluidsynth:left
  
     * JACK port with spaces    source "MPlayer [20120]:out_0"
 
     * unconnected JACK port    source manual (or 'man')
     
       note: the port for mono track 'piano' would be ecasound:piano_in_1

     * JACK ports list          source drum.ports (ports list from drums.ports)
                                source ports  (ports list from trackname.ports)

     * from track (after effects processing)
                                source track sax

     * from bus                 source bus Strings
     
    -----------------------------------------------------------

   send, out, m, aux         -  create an auxiliary send
                             -  same arguments as 'source'
                             -  currently one send allowed per track
 - version 

   set_version, version, ver, n  -  set current track version

   list_version, lver, lv        - list version numbers of current track

 - chain object modifiers

   mod, mods, modifiers    - show or assign select/reverse/playat modifiers
                             for current track
   nomod, nomods, 
   nomodifiers             - remove all modifiers from current track

 - signal processing

   ecanormalize, normalize, norm 
                           - run ecanormalize on current track version
   ecafixdc, fixdc         - run ecafixdc on current track version
   autofix-tracks, autofix - fixdc and normalize selected versions of all PLAY
                             tracks

 - cutting and time shifting

   set-region,    srg      - specify a track region using times or mark names
   add-region,    arg      - define a region creating an auxiliary track
   remove-region, rrg      - remove auxiliary track or region definition
   shift-track,   shift    - set playback delay for track/region
   unshift-track, unshift  - eliminate playback delay for track/region

- track caching (freezing)

   cache-track,   cache,   ct  - store effects-processed track signal as new version
   uncache-track, uncache, unc - select uncached track version, replace effects

 - hazardous or destructive commands for advanced users

   set-track               - directly set current track parameters

   destroy-current-wav     - unlink current track's selected WAV version.

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
   to-start, beg      - set playback head to start
   to-end, end        - set playback head to end

   loop-enable, loop  -  loop playback between two points
                         example: loop 5.0 200.0 (positions in seconds)
                         example: loop start end (mark names or numbers)
   loop-disable, noloop, nl
                      -  disable looping

   preview            -  start engine with WAV recording disabled
                         (for mic check, etc.) Release with 'arm'.

   doodle             -  Like preview, with WAV playback also disabled
                         Release with 'arm'.
                         
TRANSPORT

marks => <<MARKS,
   new-mark,      mark, k     - drop mark at current position, with optional name
   list-marks,    lmk,  lm    - list marks showing index, time, name
   next-mark,     nmk,  nm    - jump to next mark 
   previous-mark, pmk,  pm    - jump to previous mark 
   name-mark,           nom   - give a name to current mark 
   to-mark,       tmk,  tom   - jump to a mark by name or index
   remove-mark,   rmk,  rom   - remove current mark
   modify-mark, move-mark, 
    mmk, mm                   - change the time setting of current mark
MARKS

effects => <<EFFECTS,
    
 - information commands

   ladspa-register, lrg       - list LADSPA effects
   preset-register, prg       - list Ecasound presets
   ctrl-register,   crg       - list Ecasound controllers 
   find-effect,     fe        - list available effects matching arguments
                                example: find-effect reverb
   help-effect, he            - full information about an effect 
                                example: help-effect 1209 
                                  (information about LADSPA plugin 1209)
                                example: help-effect valve
                                  (information about LADSPA plugin valve)

 - effect manipulation commands

   add-effect,     afx        - add an effect to the current track
   add-controller, acl        - add an Ecasound controller
   insert-effect,  ifx        - insert an effect before another effect
   modify-effect,  mfx        - set, increment or decrement effect parameter
   remove-effect,  rfx        - remove an effect or controller
   append-effect, apfx        - add effect to the end of current track effect list 
   bypass-effects, bypass, bye   - suspend current track effects except vol/pan
   restore-effects, restore, ref - restore track effects

-  send/receive inserts

   add-insert,         ain    - add an insert to current track
   remove-insert,      rin    - remove an insert from current track
   set-insert-wetness, wet    - set/query insert wetness 
                                example: wet 99 (99% wet, 1% dry)

-  effect chains (presets, each consisting of multiple effects)

   find-effect-chains,     fec   - find all effect chains (filtering on key/value pairs, if supplied)
   find-user-effect-chains,fuec  - find all user-defined effect chains, filtering as above
   new-effect-chain,       nec   - define a new effect chain
   overwrite-effect-chain, oec   - as above, but overwite existing definition
   add-effect-chain,       aec   - add an effect chain to the current track
   delete-effect-chain,    dec   - delete an effect chain definition

-  effect profiles (effect chains for a group of tracks)

   new-effect-profile, nep       - define a new effect profile
   apply-effect-profile, aep     - apply an effect profile
                                   (current effects are bypassed)
   overlay-effect-profile, oep   - apply an effect profile,
                                   adding to current effects
   delete-effect-profile, dep    - delete an effect profile definition

EFFECTS

group => <<GROUP,
   new-bunch, bunch, nb       - name a bunch of tracks
                                e.g. bunch strings violins cello bass
                                e.g. bunch 3 4 6 7 (track indexes)
   list-bunches,     lb       - list groups of tracks (bunches)
   remove-bunches,   rb       - remove bunch definitions

   for                   - execute commands on several tracks 
                           by name, or by specifying a group or bunch
                           example: for strings; vol +10
                           example: for drumkit congas; mute
                           example: for 3 5; vol * 1.5
                           example: for Main; version 5;; show
                            (operates on all tracks in bus Main,
                            commands following ';;' execute only once)
                           example: for bus; version 5
                            (operates on tracks in current bus)
                           example: for rec; off
                            (operates on tracks in current bus set to 'rec')
                           example: for OFF; off
                            (operates on tracks in current bus w/status OFF)
GROUP

bus => <<BUS,
   add-bus,             abs   - create a sub-bus feeding a regular user track
                                of the same name
                                example: add-bus Strings 
                                         add-tracks violin cello bass
                                         for cello violin bass; move-to-bus Strings
   list-buses,          lbs   - list bus data
   remove-bus                 - remove a bus
   bus-version                - select default version for all tracks on bus

   add-submix-raw,      asr   - create bus and slave tracks for 
                                sending pre-fader track signals
   add-submix-cooked,   asc   - as above, for post-fader signals
   update-submix,       usm   - refresh send bus track list
BUS

mixdown => <<MIXDOWN,
   mixdown,    mxd             - enable mixdown 
   mixoff,     mxo             - disable mixdown 
   mixplay,    mxp             - playback a recorded mix 
   automix                     - normalize track vol levels, then mixdown
   master-on,  mr              - enter mastering mode
   master-off, mro             - leave mastering mode
MIXDOWN

prompt => <<PROMPT,
   The prompt displays the name of the project and currently selected track and
   bus (if other than Main.)

   nama allegro violin / Strings > 

   At the command prompt, you can enter several types
   of commands:

   Type                        Example
   ------------------------------------------------------------
   Nama commands               load somesong
   Ecasound commands           cs-is-valid
   Shell expressions           ! ls
   Perl code                   eval 2*3     # prints '6'

   Many commands in Nama operate on the currently selected track or 'current track'. 
   track name or number to a command sets the current track before the command
   executes.  For example, to mute the volume for a track called 'sax', you could
   say 'sax mute', or even something like '4 mute'. Using the track number
   can be convenient when executing commands on multiple tracks as 'for 4 5 6; unmute'

PROMPT

diagnostics => <<DIAGNOSTICS,

   dump-all,   dumpall,   dumpa - dump most internal state
   dump-track, dumpt,     dump  - dump current track data
   dump-group, dumpgroup, dumpg - dump group settings for user tracks
   show-io,    showio           - show chain inputs and outputs
   engine-status, egs           - display ecasound audio processing engine
                                   status
DIAGNOSTICS

edits => <<EDITS,

-  general

   list-edits,       led        - list edits
   new-edit,         ned        - create new edit for current track and version
   select-edit,      sed        - choose an edit to modify, becomes current edit
   end-edit-mode,    eem        - track plays full length
   disable-edits,    ded        - disable edits for current track
   destroy-edit                 - remove all WAV files and data for current edit
   
-  edit marks

   set-edit-points,  sep        - mark play start, rec start and rec end 

   play-start-mark,  psm        - select and move to play start mark
   rec-start-mark,   rsm        - select and move to rec start mark
   red-end-mark,     rem        - select and move to rec end mark

   set-play-start-mark, spsm    - set mark to current position
   set-rec-start-mark,  srsm    - set mark to current position
   set-rec-end-mark,    srem    - set mark to current position

-  preview edit segment

   preview-edit-in   pei        - preview track with edit segment removed
   preview-edit-out  peo        - preview edit segment to be removed

-  record/play edit

   record-edit       red        - record a WAV file for current edit
   play-edit         ped        - play a completed edit

-  select edit related tracks

   edit-track,       et         - set edit track as current track
   edit-track,       et         - set edit track as current track
   host-track,       ht         - set host track alias as current track
   host-track-alias, hta        - set host track alias as current track
   version-mix-track,vmt        - set version mix track as current track 
EDITS

fades => <<FADES,
   add-fade,         afd, fade  - add fade (in or out) to current track
                                  examples: 
                                      fade in song-start 0.2
                                  (fades in at mark 'song-start' over 0.2 s)
                                      fade out 0.5 song-start
                                  (fades out over 0.5 s ending at 'song-start')
                                  
   remove-fade,      rfd        - remove fade (by index)
   list-fade         lfd        - list all fades
FADES
   
);
# print values %{$help->{topic}};

$help->{screen} = <<HELP;

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
12 Edits
13 Fades
14 Command line options

HELP
