$help->{arr_topic}->@* = qw(
project
track_basics
track_status
wav_versions
transport
track_fader
effect_info
effect_manipulation
marks
defining_and_positioning_clips
track_io
inserts
fades
group
bus
mixdown
prompt
normalization
track_caching
effect_chains
effect_profiles
advanced_transport
version_control
diagnostics
edits
advanced
sequences
                ) ;
my $i;
my @display_index = map{ $help->{index}->{++$i} = $_;  # integer => topic key
                            s/_/ /g; 
                            my $name = ucfirst $_; 
                            $help->{title}->[$i] = $name;
                            $name = join " ",$i, $name;
                            $help->{display}->[$i] = $name;
                            } $help->{arr_topic}->@*;
sub pad ($text, $len) {
    my $padding = $len - length $text;
    $padding = 1 if $padding < 1;
    my $pad = ' ' x $padding;
    $text.$pad
}
my $column_length = int((@display_index + 1) / 2);
my @twocolumn = map {
    pad($display_index[$_], 35).($display_index[$_ + $column_length] // '').$/
} 0..$column_length - 1;


$help->{topic}->%*  = (

help => <<HELP,
   help <command>             - show help for <command>
   help <fragment>            - show help for commands matching <fragment>
   help <topic_number>        - list commands under <topic_number> 
   find-midi, fm <keywords>   - search MIDI command names and descriptions
   help-midi, hm <name>       - show help for MIDI command
   find-effect, fe <keywords> - search effects registry
   help-effect, he <name>     - show help for effect by name or LADSPA ID

HELP

project => <<'PROJECT',
   load-project, load      - load an existing project, e.g 'load <project-name>'
   new-project, create     - create a new project (usually under $HOME/nama/project-name/)
   list-projects, lp       - list all projects
   undo                    - go back to the previous project state, undoing the last command
                             that changed project state
   redo                    - reapply changes rolled back by undo, one commit at a time
   exit, quit              - exit program, saving state 
   Ctrl-C                  - exit program without saving state

PROJECT

track_basics => <<'TRACKBASICS',
   add-track, add          - Create a new track

      Example: add sax     - Add a new track 'sax', mono by default.
                           - Track 'sax' is selected, and receives subsequent commands.
               source 3    - Use soundcard channel 3 as input
               rec         - Arm track for recording an audio file (e.g. sax_1.wav)
               start       - Start engine, begin recording
               stop        - Stop engine, close file and queue for playback
     
               <SPACE> can be used at the prompt to start and stop engine
   
      Example: add piano; source synth; stereo; rec
   
      This line of commands prepares to record track 'piano' in stereo 
      width from JACK client 'synth'. Use of semicolons allow several 
      commands in one line of input.

   import-audio, import    - Import an audio file, resampling if necessary
   remove-track            - Remove current track (all WAV files remain)
TRACKBASICS

track_status => <<'TRACKSTATUS',

Prepare conditions for next engine run

   rec               -  REC: record and monitor audio source
   mon               -  MON: monitor audio source
   play              -  PLAY: queue WAV file for playback
   off               -  OFF: omit track from audio network
   show-tracks, show - show status, all tracks
   show-track, sh    - show status of current track, including effects, versions, etc.
   chains            - show the audio network configuration
TRACKSTATUS


wav_versions => <<'WAV_VERSIONS',
   list-versions, lver      - list version numbers of audio files in the current track
                            - (this information also appears in the show-track listing)
   set-version, version, ver - select a version number for the current track

A track can record multiple audio files ('takes'). The audio filenames
follow the trackname so that recording a track named 'piano' will
produce files with names like piano_1.wav, piano_2.wav.
Recorded audio files are stored outside of version control; editing
normally leaves them unchanged.

One version can be selected as the stream source when the track is
set to PLAY. The version number is zero by default, which means
select the most recent (highest numbered) take. The bus-version command
sets the version selection for each track belonging to the current bus.
WAV_VERSIONS

transport => <<TRANSPORT,
   start, t, SPACE      - Start processing. SPACE must be at beginning of command line.
   stop, s, SPACE       - Stop processing. SPACE must be at beginning of command line.
   rewind, rw           - Rewind  some number of seconds, i.e. rw 15
   forward, fw          - Forward some number of seconds, i.e. fw 75
   setpos, sp           - Set the playback head position, i.e. setpos 49.2
   getpos, gp           - Get the current head position 
   jump-to-start, beg   - set playback head to beginning of audio file(s)
   jump-to-end, end     - set playback head to end

   Commands that take time positions in seconds can also
   take mark names and H:M:S, M:S. Seconds can be decimal
   values. With a tempo map, you can use bar/beat or
   bar/beat/tick notations.

TRANSPORT

track_fader => <<'TRACKFADER',
   Track volume/pan fader can be used to change settings for the current track.

   pan, p                   -  get/set pan position
   pan-back, pb             -  restore pan after pr/pl/pc  
   pan-center, pc           -  set pan center    
   pan-left, pl             -  pan track fully left    
   pan-right, pr            -  pan track fully right    
   vol, v                   -  set or adjust volume (percent with ea; dB with eadb)
       Examples with the default ea volume operator:
       vol 100 (set unity gain)
       vol 50  (set half amplitude)
       vol - 3 (reduce volume by 3 percentage points)
                                      
   unity                    -  set volume gain to unity
   mute, c, cut             -  mute track volume 
   unmute, nomute, uncut, C -  restore muted volume
   solo                     -  mute all tracks but current track
   nosolo                   -  end solo, preserving previously muted tracks
   all                      -  end solo and unmute all user tracks
TRACKFADER
effect_info => <<'EFFECT_INFO',
   ladspa-register, lrg     - list LADSPA effects
   preset-register, prg     - list Ecasound presets
   ctrl-register, crg       - list Ecasound controllers 
   find-effect, fe          - list available effects matching arguments
                              example: find-effect reverb
   help-effect, he          - full information about an effect 
                              example: help-effect 1209 
                                (information about LADSPA plugin 1209)
                              example: help-effect valve
                                (information about LADSPA plugin valve)
EFFECT_INFO
effect_manipulation => <<'EFFECT_DO',
   add-effect,     afx           - add an effect to the current track
                                   Example: afx ea 50 (amplify to 50%, halving signal)
   add-controller, acl           - add an Ecasound controller to the parameter
                                   of an effect  
   insert-effect,  ifx           - insert an effect before another effect
   modify-effect,  mfx           - set, increment or decrement effect parameter
   remove-effect,  rfx           - remove an effect or controller
   add-effect-last, afxl         - add effect to the end of current track effect list
   bypass-effects, bypass, bfx   - suspend selected effects (current effect by default)
   restore-effects, bbfx         - restore selected effects (current effect by default)

   Use 'bypass all' or 'restore-effects all' for all user effects except vol/pan.
EFFECT_DO

marks => <<MARKS,
   add-mark,      mark, k     - drop mark at current position, with optional name
   list-marks,    lmk,  lm    - list marks showing index, time, name
   next-mark,     nmk         - jump to next mark
   previous-mark, pmk         - jump to previous mark
   name-mark                 - give a name to current mark
   to-mark,       tmk,  tom   - jump to a mark by name or index
   remove-mark,   rmk         - remove current mark
   modify-mark, move-mark, mmk - change the time setting of current mark

Marks belong to the overall timeline, not to a particular
track. They do not move when a track is repositioned on the
timeline. 
MARKS

defining_and_positioning_clips => <<'DEFINING_AND_POSITIONING_CLIPS',
   Defining and positioning clips

   set-region,    srg      - reduce current track to a playable region, a clip
   new-clip,      ncl      - create a track alias for a region of the current track
   remove-region, rrg      - remove region definition or clip
   shift-track,   shift    - set timeline position for track or region to play
   unshift-track, unshift  - set timeline position to zero for a track or region
DEFINING_AND_POSITIONING_CLIPS

track_io => <<'TRACKIO',
   Track inputs and outputs are set by source and send commands, 
   which take similar arguments. 

   source, src, r            -  set track source
                             -  with no arguments returns current signal source

    ----------------------------------------------------------
    for this input              use this command
    ----------------------------------------------------------

     * soundcard channel 3      source 3 

     * soundcard channels 3,4   source 3; stereo

     * JACK client              source fluidsynth
     
     * JACK port                source fluidsynth:left
  
     * JACK port with spaces    source "MPlayer [20120]:out_0"
 
     * unconnected JACK port    source manual
     
       note: with the default JACK client name, a mono track 'piano'
             exposes nama:piano_in_1

     * A list of JACK ports     source drums.ports (ports list from file drums.ports)

     * from another track (after effects processing)
                                source track Strings
     * from a bus (member tracks' outputs)
                                source bus Strings

    -----------------------------------------------------------

   send, aux                -  Create an auxiliary send to a soundcard channel,
                                JACK destination or another track.
                                One send is allowed per track.

   Sends are not necessary to set up as most tracks are part
   of a bus that routes the audio output. 
TRACKIO
inserts => <<'INSERTS',

Use inserts to pass an audio stream through an external effect
such as a JACK client or an analog fx box hooked to
your soundcard. 

   add-insert, ain            - add an insert to current track
   remove-insert, rin         - remove an insert from current track
   set-insert-wetness, wet    - set/query insert wetness 
                                example: wet 99 (99% wet, 1% dry)
INSERTS
fades => <<FADES,
   add-fade, afd, fade        - add fade (in or out) to current track
                                  examples: 
                                      fade in song-start 0.2
                                  (fades in at mark 'song-start' over 0.2 s)
                                      fade out 0.5 song-start
                                  (fades out over 0.5 s ending at 'song-start')
                                  
   remove-fade, rfd           - remove fade (by index)
   list-fade, lfd             - list all fades
FADES

group => <<GROUP,
Group control
   add-bunch, abn       - name a bunch of tracks
                            e.g. add-bunch strings violins cello bass
                            e.g. add-bunch strings 3 4 6 7 (track indexes)
   list-bunches, lbn     - list groups of tracks (bunches)
   remove-bunch, rbn     - remove bunch definitions

   for                   - execute commands on several tracks 
                           by name, or by specifying a bus or bunch
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
   add-bus, abs         - create a sub-bus feeding a track of the same name
                          example: add-bus Strings 
                                   add-tracks violin cello bass
                                   for cello violin bass; move-to-bus Strings
   list-buses, lbs      - list bus data
   remove-bus           - remove a bus
   bus-version          - select default audiofile version for all tracks on bus

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

normalization => <<'NORMAL',
Normalization

   ecanormalize, normalize
                           - run ecanormalize on current track version
   ecafixdc, fixdc         - run ecafixdc on current track version
   autofix-tracks, autofix - fixdc and normalize selected versions of all PLAY tracks

These commands modify the selected WAV files on disk.
NORMAL

track_caching => <<'CACHING',
Track caching (freezing) - render effects to a new .wav file to fix a result and save cpu

   cache                       - cache the output of a track or bus as a .wav file
   uncache                     - restore the uncached version and effects (not inserts)
CACHING

effect_chains => <<'EFFECT_CHAINS',

Effect chains are presets that can consist of multiple effects. They are a
convenient way to save by name sequences of effects with the parameters that
you commonly use. You make an effect chain by saving effects from the current
track. 

   find-effect-chains,     fec   - find all effect chains (filtering on key/value pairs, if supplied)
   find-user-effect-chains,fuec  - find all user-defined effect chains, filtering as above
   new-effect-chain,       nec   - define a new effect chain
   overwrite-effect-chain, oec   - as above, but overwrite existing definition
   add-effect,             afx   - add a named effect chain to the current track
   delete-effect-chain,    dec   - delete an effect chain definition
EFFECT_CHAINS

effect_profiles => <<'EFFECT_PROFILES',
Effect profiles (effect chains for a group of tracks)

An effect profile is a group of effect chains, saved with the tracks that
configure them. It is a convenient way to share parts of a project among other
projects. 

   new-effect-profile, nep       - define a new effect profile
   apply-effect-profile, aep     - add the profile's effects to its named tracks
   destroy-effect-profile       - delete an effect profile definition
EFFECT_PROFILES

advanced_transport => <<'ADVANCED_TRANSPORT',
   loop, l            -  loop playback between two points
                         example: loop 5.0 200.0 (positions in seconds)
                         example: loop start end (mark names or numbers)
   noloop, nl         -  disable looping

   preview            -  enter a mode with WAV recording disabled
                         (for mic check, etc.). Use 'start' to run and 'arm' to leave.

   doodle             -  like preview, with WAV playback also disabled
                         Use 'start' to run and 'arm' to leave.
ADVANCED_TRANSPORT

version_control => <<'VCS',
** Version control 

Nama uses git to save project state as a series of commits when commands
change project state. Tags label particular states for later retrieval.

   save <tagname>            - label current snapshot as <tagname>
   get <tagname>             - checkout project state tagged with <tagname>
   branch <branchname>       - switch to branch and load state
   list-branches, lbr        - list branches and tags
   new-branch, nbr           - create a new branch starting at the current 
                               commit or another Git revision
   tag                       - tag current commit with a name and optional message

   'get' accepts a tag or branch name, or a saved .json settings filename.
VCS
diagnostics => <<DIAGNOSTICS,

   dump-all,   dumpa            - dump most internal state
   dump-track, dump             - dump current track data
   dump-group, dumpg            - dump group settings for user tracks
   dump-io                      - show chain inputs and outputs
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
   rec-end-mark,     rem        - select and move to rec end mark

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
   host-track,       ht         - set host mix track as current track
   host-track-alias, hta        - set host track alias as current track
   version-mix-track,vmt        - set version mix track as current track 
EDITS


advanced => <<'ADVANCED',

   set-track               - directly set current track parameters

   destroy-current-wav     - unlink current track's selected WAV version.
ADVANCED

sequences => <<'SEQUENCES',
   new-sequence, nsq          - create a sequence from tracks or clips
   select-sequence, slsq      - select the current sequence
   list-sequences, lsq        - list all sequences
   show-sequence, ssq         - show the items in the current sequence
   append-to-sequence, asq    - append items to the current sequence
   insert-in-sequence, isq    - insert items before a sequence position
   remove-from-sequence, rsq  - remove items from the current sequence
   add-spacer, asp            - add silence to the current sequence
   delete-sequence, dsq       - delete a sequence
   convert-to-sequence, csq   - convert the current track to a sequence
   merge-sequence, msq        - render the current sequence to a WAV file

A sequence plays its items consecutively. An item may be a track, which
plays its entire WAV file, or a clip, which plays only its defined region.
SEQUENCES

   
);
# print values $help->{topic}->%*;

$help->{screen} = <<HELP.

Welcome to Nama help

The help command ('help', 'h') can take several arguments.

help <command>          - show help for <command>
help <fragment>         - show help for all commands matching /<fragment>/
help <topic_number>     - list commands under topic <topic_number> below

Other help commands:

find-effect, fe        - search for effect matching keywords
help-effect, he        - help on specific effect or LADSPA ID


help is available for the following topics:

HELP
join '',@twocolumn;
