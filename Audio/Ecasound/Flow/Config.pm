package Ecasound::Flow;

$yaml = <<CONFIG;
### Ecmd configuration file
#
#   Abbreviations may be added as necessary.
#   Care must be taken to avoid circular definitions.
#
#   
---
application: ecmd
abbreviations:
    cd-stereo: s16_le,2,44100,i
    cd-mono:   s16_le,1,44100
    24-mono:   s24_le,1,frequency
    32-10:     s32_le,10,frequency
    32-12:     s32_le,12,frequency
    frequency: 44100
wave_directory:   /media/sessions
ecmd_home: /home/jroth/ecmd
ecasound_globals: -B auto
devices:
    multi: 
        ecasound_id:   alsaplugin,1,0
        input_format:  32-12
        output_format: 32-10
    stereo: 
        ecasound_id:   alsaplugin,0,0
        input_format:  cd-stereo
        output_format: cd-stereo
    jack: 
        ecasound_id:   jack_alsa
        input_format:  32-12 
        output_format: 32-10
raw-to-disk: 
    format:        cd-mono
mix-to-disk:
    format:        cd-stereo 
mixer_out: 
    format:        cd-stereo
tk_input_channels: 10  # fixed value for Tk widget
use_monitor_version_for_mixdown: 1
CONFIG
1;
