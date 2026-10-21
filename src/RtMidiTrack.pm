# ---------- RtMidiTrack: real-time MIDI track with saved takes ----------
#
# Install as lib/Audio/Nama/RtMidiTrack.pm (drop the .txt suffix).
# Supersedes the earlier ArpTrack module.
#
# Each recording attempt is saved as a numbered "take" (a version, like WAV
# versions): <project>/.rtmidi/<track>_<n>.json. Takes can be listed,
# selected (Nama's usual 'version N' command), played back, and merged into
# a brand-new track with rt_make_track.
#
# Live input comes from MIDI::RtController, which reads the port in a
# separate worker process and delivers events on Nama's IO::Async loop
# (Tickit::Async runs on IO::Async::Loop->new, the process-wide loop).
#
# Like the other non-audio tracks, rec_status is always OFF, so ChainSetup
# and Ecasound never see it. Runtime state (listeners, timers, the take
# being recorded) lives in file-level hashes, never in the track hash, so
# save_state serializes only plain settings.

package Audio::Nama::RtMidiTrack '1.000';

use v5.36;
use File::Path qw(make_path);
use JSON::PP ();
use List::Util qw(max);
use Time::HiRes ();
use parent -norequire, 'Audio::Nama::Track';  # before Object import: keeps @ISA
use Audio::Nama::Globals qw(:all);
use Audio::Nama::Object qw( rt_input rt_output rt_thru );
use Audio::Nama::RtMidiTrack::NullOut;

no warnings qw(redefine);

# event types captured from the controller. 'clock', 'start' and 'stop'
# are deliberately absent. Extend this list if you want more recorded.
my @RECORDED = qw(note_on note_off control_change pitch_wheel_change patch_change);

my %DEFAULT = (
	rt_input  => '',   # MIDI input port name (substring match)
	rt_output => '',   # MIDI output port: playback and thru monitoring
	rt_thru   => 1,    # echo incoming notes to the output while recording
);
my %VALID = (
	rt_input  => qr/\S/,
	rt_output => qr/\S/,
	rt_thru   => qr/^[01]$/,
);

# runtime state (see header)
my %IN;    # input port name  => { rtc }
my %OUT;   # output port name => { dev, users }
my %REC;   # track name       => recording state
my %PLAY;  # track name       => playback state

# ---- construction ----

# Track::new rejects fields it doesn't know, so strip ours first
sub new {
	my ($class, %args) = @_;
	my %rt = map  { $_ => delete $args{$_} }
	         grep { exists $args{$_} } keys %DEFAULT;
	my $self = $class->SUPER::new(%args) or return;
	$self->{$_} = $rt{$_} // $DEFAULT{$_} for keys %DEFAULT;
	$self
}

sub remove {
	my $self = shift;
	$self->stop;
	$self->SUPER::remove(@_);   # take files are left on disk, like WAV files
}

# ---- Track interface overrides ----

sub rec_status { OFF }           # nothing for the audio engine to do
sub rec_status_display {
	my $self = shift;
	$REC{ $self->name }  ? 'REC'
	: $PLAY{ $self->name } ? 'PLAY'
	: $self->rw eq OFF   ? OFF
	:                      'MIDI'
}
sub select_track {               # no Ecasound chain to select
	my $self = shift;
	$Audio::Nama::this_track = $self;
	Audio::Nama::set_current_bus();
}
sub set_rw {
	my ($self, $setting) = @_;
	$self->{rw} = $setting;
	$self->stop if $setting eq OFF;
}
sub rw_set { my ($self, $bus, $setting) = @_; $self->set_rw($setting) }
sub mute   { $_[0]->set_rw(OFF) }
sub unmute { $_[0]->set_rw(MON) }

# 'source <port>' sets the MIDI input, 'send <port>' the output
sub set_io ($self, $direction, $id = undef, @) {
	my $field = $direction eq 'send' ? 'rt_output' : 'rt_input';
	return $self->{$field} || undef unless defined $id;
	$self->rt_configure($field => $id);
	return $id;
}

# 'version N' picks the take that rt_play plays; 0 follows the latest take
sub set_version ($self, $n) {
	my $name = $self->name;
	if (!$n) {
		Audio::Nama::pager("$name: following latest take");
		$self->set(version => 0);
	}
	elsif (grep { $_ == $n } $self->versions->@*) {
		Audio::Nama::pager("$name: take $n selected");
		$self->set(version => $n);
	}
	else { Audio::Nama::throw("$name: take $n does not exist, skipping.") }
}
sub versions     { [ $_[0]->take_numbers ] }
sub current_take { my $self = shift; $self->version || max($self->take_numbers) // 0 }

# ---- settings ----

sub rt_configure {
	my ($self, %kv) = @_;
	for my $key (keys %kv) {
		my $field = $key =~ /^rt_/ ? $key : "rt_$key";
		my $check = $VALID{$field}
			or Audio::Nama::throw("$key: unknown setting. Known: input output thru"), return;
		$kv{$key} =~ $check
			or Audio::Nama::throw("$key: invalid value '$kv{$key}'"), return;
		$self->set($field => $kv{$key});
		# start listening as soon as the input is known, so the port is
		# already open when the first take begins
		_listener($self->{rt_input}) if $field eq 'rt_input';
	}
	1
}
sub rt_summary {
	my $self = shift;
	join "\n", $self->name . ': MIDI track',
		map { sprintf "  %-7s %s", s/^rt_//r, $self->{$_} } sort keys %DEFAULT;
}

# ---- take files ----

sub take_dir {
	my $dir = Audio::Nama::project_dir() or return;
	Audio::Nama::join_path($dir, '.rtmidi')
}
sub take_file {
	my ($self, $n) = @_;
	my $dir = $self->take_dir or return;
	Audio::Nama::join_path($dir, $self->name . "_$n.json")
}
sub take_numbers {
	my $self = shift;
	my $dir = $self->take_dir or return;
	opendir my $dh, $dir or return;
	my $name = $self->name;
	sort { $a <=> $b } map { /^\Q$name\E_(\d+)\.json$/ ? $1 : () } readdir $dh
}

# One event per line: [seconds, type, channel, ...], easy to read and diff.
sub save_take {
	my ($self, $n, $events, $length) = @_;
	my $path = $self->take_file($n) or return;
	make_path($self->take_dir);
	my $json = JSON::PP->new->canonical;
	open my $fh, '>', $path or croak "$path: $!";
	printf {$fh} qq({"format":1,"length":%.4f,"events":[\n), $length;
	print  {$fh} join(",\n", map { $json->encode($_) } @$events), "\n";
	print  {$fh} "]}\n";
	close $fh or croak "$path: $!";
	$path
}
sub load_take {
	my ($self, $n) = @_;
	my $path = $self->take_file($n) or return;
	open my $fh, '<', $path or return;
	my $data = eval { JSON::PP->new->decode(do { local $/; <$fh> }) };
	return unless ref $data eq 'HASH' and ref $data->{events} eq 'ARRAY';
	$data
}
sub take_summary {
	my $self = shift;
	my $current = $self->current_take;
	join "\n", $self->name . ' takes:', map {
		my $d = $self->load_take($_);
		sprintf "  %s%2d  %6.1f s  %5d events",
			($_ == $current ? '*' : ' '), $_,
			$d ? ($d->{length}, scalar $d->{events}->@*) : (0, 0)
	} $self->take_numbers;
}

# ---- recording ----

sub start_record {
	my $self = shift;
	my $name = $self->name;
	return if $self->rw eq OFF;
	$REC{$name} || $PLAY{$name}
		and Audio::Nama::throw("$name: already recording or playing. Use rt_stop."), return;
	my $port = $self->rt_input
		or Audio::Nama::throw("$name: no input port. Try: rt_set input <name>"), return;
	$self->take_dir
		or Audio::Nama::throw("$name: no project is loaded."), return;
	eval { _listener($port) }
		or Audio::Nama::throw("$name: cannot listen on MIDI port '$port': " . ($@ || 'unknown error')), return;

	my $out;
	if ($self->rt_thru and my $outport = $self->rt_output) {
		$out = eval { _acquire_port($outport) }
			or Audio::Nama::throw("$name: cannot open output '$outport': $@"), return;
	}
	my $n = (max($self->take_numbers) // 0) + 1;
	$REC{$name} = {
		track   => $self,
		take    => $n,
		port    => $port,
		outport => $out ? $self->rt_output : undef,
		out     => $out,
		t0      => Time::HiRes::time(),
		started => 0,     # becomes 1 at the first event
		last    => 0,     # time of the previous event
		events  => [],
		held    => {},    # "chan:note" => 1, for closing hanging notes
	};
	Audio::Nama::pager("$name: recording take $n. Play something, then rt_stop.");
	1
}

sub stop_record {
	my $self = shift;
	my $st = delete $REC{ $self->name } or return;
	my $length = max(Time::HiRes::time() - $st->{t0}, $st->{last});

	# close notes still held, so a take never contains a stuck note
	for my $key (sort keys $st->{held}->%*) {
		my ($ch, $note) = map { $_ + 0 } split /:/, $key;
		push $st->{events}->@*, [ 0 + sprintf('%.4f', $length), 'note_off', $ch, $note, 0 ];
		$st->{out}->send_event('note_off', $ch, $note, 0) if $st->{out};
	}
	_release_port($st->{outport}) if $st->{out};

	if (!$st->{events}->@*) {
		Audio::Nama::pager($self->name . ": nothing was played; take $st->{take} discarded.");
		return 1;
	}
	$self->save_take($st->{take}, $st->{events}, $length);
	Audio::Nama::pager(sprintf "%s: saved take %d (%d events, %.1f s)",
		$self->name, $st->{take}, scalar $st->{events}->@*, $length);
	1
}

# Called by the RtController filter for each event on $port. The delta
# time from RtMidi is exact but starts at zero, so the first event is
# placed by the wall clock and the rest by accumulating delta times.
sub _on_event ($port, $dt, $event) {
	return 0 unless ref $event eq 'ARRAY';
	my $now = Time::HiRes::time();
	for my $st (grep { $_->{port} eq $port } values %REC) {
		my $t = $st->{started} ? $st->{last} + ($dt // 0) : $now - $st->{t0};
		@{$st}{qw(started last)} = (1, $t);
		push $st->{events}->@*, [ 0 + sprintf('%.4f', $t), @$event ];
		_track_held($st->{held}, @$event);
		$st->{out}->send_event(@$event) if $st->{out};   # thru
	}
	return 1;   # handled; RtController is silent, nothing else is forwarded
}

# one RtController (hence one worker process) per input port, kept for the
# life of Nama so takes don't miss notes while a port is being opened
sub _listener ($port) {
	$IN{$port} //= do {
		require MIDI::RtController;
		require IO::Async::Loop;
		my $rtc = MIDI::RtController->new(
			input    => $port,
			loop     => IO::Async::Loop->new,         # Nama's loop
			midi_out => Audio::Nama::RtMidiTrack::NullOut->new,
			silent   => 1,
		);
		$rtc->add_filter(rt_record => \@RECORDED,
			sub ($p, $dt, $event) { _on_event($port, $dt, $event) });
		{ rtc => $rtc }
	};
	1
}

# ---- playback ----

sub start_play {
	my ($self, $n) = @_;
	my $name = $self->name;
	return if $self->rw eq OFF;
	$REC{$name} || $PLAY{$name}
		and Audio::Nama::throw("$name: already recording or playing. Use rt_stop."), return;
	$n ||= $self->current_take
		or Audio::Nama::throw("$name: no takes recorded yet."), return;
	my $take = $self->load_take($n)
		or Audio::Nama::throw("$name: take $n not found."), return;
	my $outport = $self->rt_output
		or Audio::Nama::throw("$name: no output port. Try: rt_set output <name>"), return;
	require IO::Async::Loop;
	require IO::Async::Timer::Countdown;
	my $out = eval { _acquire_port($outport) }
		or Audio::Nama::throw("$name: cannot open output '$outport': $@"), return;

	my $st = {
		track   => $self,
		take    => $n,
		outport => $outport,
		out     => $out,
		loop    => IO::Async::Loop->new,
		events  => $take->{events},
		idx     => 0,
		held    => {},
		t0      => Time::HiRes::time(),
	};
	$st->{timer} = IO::Async::Timer::Countdown->new(
		delay     => 0,
		on_expire => sub { _pump($st) },
	);
	$st->{loop}->add($st->{timer});
	$PLAY{$name} = $st;
	Audio::Nama::pager("$name: playing take $n");
	_pump($st);
	1
}

# send every event that is due, then sleep until the next one: one timer
# per track, however many events the take has
sub _pump ($st) {
	my $events = $st->{events};
	my $now = Time::HiRes::time() - $st->{t0};
	while ($st->{idx} < @$events and $events->[ $st->{idx} ][0] <= $now + 0.001) {
		my (undef, @msg) = $events->[ $st->{idx}++ ]->@*;
		_track_held($st->{held}, @msg);
		$st->{out}->send_event(@msg);
	}
	return _end_play($st, 'finished') if $st->{idx} >= @$events;

	my $timer = $st->{timer};
	my $delay = $events->[ $st->{idx} ][0] - $now;
	$timer->stop if $timer->is_running;
	$timer->configure(delay => $delay > 0 ? $delay : 0);
	$timer->start;
}

sub _end_play ($st, $how) {
	my $name = $st->{track}->name;
	delete $PLAY{$name};
	if (my $timer = delete $st->{timer}) {    # also breaks the closure cycle
		$timer->stop if $timer->is_running;
		$st->{loop}->remove($timer);
	}
	# silence only the notes this track left sounding
	for my $key (sort keys $st->{held}->%*) {
		my ($ch, $note) = map { $_ + 0 } split /:/, $key;
		$st->{out}->send_event('note_off', $ch, $note, 0);
	}
	_release_port($st->{outport});
	Audio::Nama::pager("$name: $how");
	1
}

# stop whatever this track is doing
sub stop {
	my $self = shift;
	my $name = $self->name;
	if    ($REC{$name})  { return $self->stop_record }
	elsif ($PLAY{$name}) { return _end_play($PLAY{$name}, 'stopped') }
	return;
}

# ---- helpers ----

sub _track_held ($held, $type, @args) {
	return unless $type eq 'note_on' or $type eq 'note_off';
	my ($ch, $note, $vel) = @args;
	if ($type eq 'note_on' and $vel) { $held->{"$ch:$note"} = 1 }
	else                             { delete $held->{"$ch:$note"} }
}

# output ports are shared between tracks and closed with the last user
sub _acquire_port ($name) {
	require MIDI::RtMidi::Util;
	my $slot = $OUT{$name} //= { dev => MIDI::RtMidi::Util::out_port($name), users => 0 };
	$slot->{users}++;
	$slot->{dev}
}
sub _release_port ($name) {
	my $slot = $OUT{$name} or return;
	return if --$slot->{users} > 0;
	eval { $slot->{dev}->close_port };
	delete $OUT{$name};
}

# merge event lists by time (sort is stable, so ties keep their order)
sub merge_events (@lists) {
	[ sort { $a->[0] <=> $b->[0] } map { @$_ } @lists ]
}

sub stop_all {
	$_->{track}->stop_record for values %REC;   # finished takes are saved
	_end_play($_, 'stopped')  for values %PLAY;
}

END { eval { stop_all() } }   # don't leave hanging notes or lose a take

1;