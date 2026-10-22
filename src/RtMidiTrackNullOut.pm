package Audio::Nama::RtMidiTrack::NullOut;

use v5.36;
sub new { bless {}, shift }
sub send_event {}
sub close_port {}
sub open_virtual_port {}

1;