# Nama - digital audio workstation

## Description

Nama is a digital audio workstation. It is suitable for
multitrack recording, effects-processing, editing, mixing,
and other audio tasks. Nama uses Ecasound, developed by Kai
Vehmanen, for audio processing. Nama hosts LADSPA and LV2
plugins, Ecasound effects and controllers. It runs with
either JACK and ALSA. 

Version 2 has features to easily extract or join portions of
a longer audio file.

Nama is integrated with klick, a metronome, and two MIDI
sequencers, midish and RtMidi. When the metronome, timeline
positions can be addressed by bar/beat/tick notation.

New projects begin with a mixer, and may include tracks with
multiple takes, buses, effects, sends, inserts, marks,
regions, fades, edits, sequences and submixes.  Mixdowns can
be rendered as wav, ogg, mp3, aac, flac, etc.

Nama has a full-featured command interpreter with TAB
completion, keyword help and command history. It provides
key bindings for repositioning the playback head, adjusting
mark positions and tweaking effect parameters.
 
The help system provides searchable access to documentation
for all Nama commands and shortcuts, and for LADSPA, LV2 and
Ecasound effects. In addition to executing its own commands,
Nama will pass commands to Ecasound, the MIDI sequencers,
the perl interpreter and the shell. 

Nama has several templating options for project reuse:
Effect chains are presets for one or more effects. Effect
profiles (used to set up Nama's mastering network) are
templates for placing effects on multiple tracks. User
scripting provides another way to reuse functionality.

Project state is serialized as JSON files and the entire
project history is managed by Git. Projects can be branched,
tagged, and easily restored to earlier states. 

## Installation 

### Debian and Debian-based distributions

You'll need Debian version 13 (Trixie) or later.
This is the current 'stable' release.

The easiest will to install the Debian package. However it
will take time for Debian Perl Team to update to Nama
version 2. When available it will install with:

    apt install nama

Till then follow these steps:

1. Install dependencies

1.1 Terminal mode

    sudo apt install libdata-dumper-concise-perl libdata-section-simple-perl libfile-copy-link-perl libfile-find-rule-perl libfile-homedir-perl libgit-repository-perl libgraph-perl libimage-size-perl libio-async-perl libjson-xs-perl liblist-moreutils-perl libobject-pad-perl libparse-recdescent-perl libpath-tiny-perl librole-tiny-perl libsuper-perl libtext-diff-perl libtext-format-perl libtickit-perl libtickit-async-perl libtickit-widgets-perl libtickit-widget-scroller-perl libtry-tiny-perl libyaml-tiny-perl cpanminus ecasound ladspa-sdk lilv-utils git ffmpeg midish klick

1.2 GUI mode

    sudo apt install perl-tk

1.3 Install Nama

You can install Nama either as root, for system-wide use,
or under your home directory.

1.3.1 As root

    sudo cpanm Audio::Nama

1.3.2 As a non-privileged user, under $HOME/perl5

Set up local::lib

	cpanm --local-lib ~/perl5 local::lib
	eval "$(perl -I"$HOME/perl5/lib/perl5" -Mlocal::lib)"

Install nama

	cpanm Audio::Nama
￼
Update environment (most shells; fish and zsh need a slightly different command)

	echo 'eval "$(perl -I"$HOME/perl5/lib/perl5" -Mlocal::lib)"' >> ~/.bashrc

1.3.3 To use RtMidi

    sudo apt install librtmidi-dev pkg-config
    cpanm MIDI::RtController MIDI::RtMidi::Util

## Copyright

Unless specified otherwise, this code is 2008 - 2026,
copyright Joel Roth

Nama is free software; you can redistribute it and/or modify
it under the terms of the Artistic License 2.0, included in
COPYING.

The bundled modified Tickit-derived modules retain their
original Perl licensing terms. See THIRD_PARTY_NOTICES for
their provenance, modifications, and applicable licenses.
