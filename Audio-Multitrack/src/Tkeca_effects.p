package ::;
our $VERSION = 1.0;
$tkeca_effects_data = <<'EFFECTS';
ea|Volume|1|Level %|0|600|100|0
epp|Pan|1|Level %|0|100|50|0
set effect(1) "eal|Limiter|1|Limit %|0|100|100|0"
set effect(2) "ec|Compressor|2|Compression Rate (Db)|0|1|1|0|Threshold %|0|100|50|0"
set effect(3) "eca|Advanced Compressor|4|Peak Level %|0|100|69|0|Release Time (Seconds)|0|5|2|0|Fast Compressor Rate|0|1|0.5|0|Compressor Rate (Db)|0|1|1|0"
set effect(4) "enm|Noise Gate|5|Threshold Level %|0|100|100|0|Pre Hold Time (ms)|0|2000|200|0|Attack Time (ms)|0|2000|200|0|Post Hold Time (ms)|0|2000|200|0|Release Time (ms)|0|2000|200|0"
set effect(5) "ef1|Resonant Bandpass Filter|2|Center Frequency (Hz)|0|20000|0|0|Width (Hz)|0|2000|0|0"
set effect(6) "ef3|Resonant Lowpass Filter|3|Cutoff Frequency (Hz)|0|5000|0|0|Resonance|0|2|0|0|Gain|0|1|0|0"
set effect(7) "efa|Allpass Filter|2|Delay Samples|0|10000|0|0|Feedback %|0|100|50|0"
set effect(8) "efb|Bandpass Filter|2|Center Frequency (Hz)|0|11000|11000|0|Width (Hz)|0|22000|22000|0"
set effect(9) "efh|Highpass Filter|1|Cutoff Frequency (Hz)|10000|22000|10000|0"
set effect(10) "efl|Lowpass Filter|1|Cutoff Frequency (Hz)|0|10000|0|0"
set effect(11) "efr|Bandreject Filter|2|Center Frequency (Hz)|0|11000|11000|0|Width (Hz)|0|22000|22000|0"
set effect(12) "efs|Resonator Filter|2|Center Frequency (Hz)|0|11000|11000|0|Width (Hz)|0|22000|22000|0"
set effect(13) "etd|Delay|4|Delay Time (ms)|0|2000|200|0|Surround Mode (Normal, Surround St., Spread)|0|2|0|1|Number of Delays|0|100|50|0|Mix %|0|100|50|0"
set effect(14) "etc|Chorus|4|Delay Time (ms)|0|2000|200|0|Variance Time Samples|0|10000|500|0|Feedback %|0|100|50|0|LFO Frequency (Hz)|0|100|50|0"
set effect(15) "etr|Reverb|3|Delay Time (ms)|0|2000|200|0|Surround Mode (0=Normal, 1=Surround)|0|1|0|1|Feedback %|0|100|50|0"
set effect(16) "ete|Advanced Reverb|3|Room Size (Meters)|0|100|10|0|Feedback %|0|100|50|0|Wet %|0|100|50|0"
set effect(17) "etf|Fake Stereo|1|Delay Time (ms)|0|500|40|0"
set effect(18) "etl|Flanger|4|Delay Time (ms)|0|1000|200|0|Variance Time Samples|0|10000|200|0|Feedback %|0|100|50|0|LFO Frequency (Hz)|0|100|50|0"
set effect(19) "etm|Multitap Delay|3|Delay Time (ms)|0|2000|200|0|Number of Delays|0|100|20|0|Mix %|0|100|50|0"
set effect(20) "etp|Phaser|4|Delay Time (ms)|0|2000|200|0|Variance Time Samples|0|10000|100|0|Feedback %|0|100|50|0|LFO Frequency (Hz)|0|100|50|0"
set effect(21) "pn:metronome|Metronome|1|BPM|30|300|120|1"
EFFECTS
