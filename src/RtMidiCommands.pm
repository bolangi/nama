package Audio::Nama;

use v5.36;
use List::Util qw(max);
use Audio::Nama::Globals qw(:all);

sub rt_tracks { grep { $_ isa Audio::Nama::RtMidiTrack } all_tracks() }

sub this_rt_track {
    return $this_track if $this_track isa Audio::Nama::RtMidiTrack;
    throw("Current track is not a MIDI take track. See add_rt_track.");
    return;
}

sub add_rt_track ($name, @params) {
	# novol/nopan: no Ecasound effects on a track with no audio chain
	# group Null: not routed to Main
	add_track($name,
		class => 'Audio::Nama::RtMidiTrack',
		group => 'Null',
		novol => 1,
		nopan => 1,
		@params);
}

# rt_set show settings of the current track
# rt_set input keyboard output synth thru 1
sub rt_set (@kv) {
	my $track = this_rt_track() or return;
	return pager($track->rt_summary) unless @kv;
	@kv % 2 and throw("rt_set takes key value pairs, e.g. rt_set input keyboard"), return;
	$track->rt_configure(@kv);
}
sub rt_record { my $t = this_rt_track() or return; $t->start_record }
sub rt_play   { my ($take) = @_; my $t = this_rt_track() or return; $t->start_play($take) }
sub rt_stop   { my $t = this_rt_track() or return; $t->stop }
sub rt_takes  { my $t = this_rt_track() or return; pager($t->take_summary) }

# rt_make_track NAME [TAKE ...]
# Create a new MIDI track whose take 1 is the given takes of the current
# track merged together (default: the selected take). Use it to keep the
# best attempt on its own, or to combine attempts.
sub rt_make_track ($new, @takes) {
	my $src = this_rt_track() or return;
	@takes = ($src->current_take) unless @takes;
	my $have = { map { $_ => 1 } $src->take_numbers };
	for my $n (@takes) {
		$have->{$n} or throw($src->name . ": take $n does not exist."), return;
	}
	my @data = map { $src->load_take($_) } @takes;
	@data == @takes or throw("Could not read all of the takes."), return;

	my $events = Audio::Nama::RtMidiTrack::merge_events(map { $_->{events} } @data);
	my $length = max(map { $_->{length} } @data);

	my $dst = add_rt_track($new,
		rt_input  => $src->rt_input,
		rt_output => $src->rt_output,
		rt_thru   => $src->rt_thru,
	) or return;
	$dst->save_take(1, $events, $length);
	pager(sprintf '%s: created from %s take%s %s (%d events, %.1f s)',
		$new, $src->name, (@takes > 1 ? 's' : ''), join(',', @takes),
		scalar @$events, $length);
	$dst
}

1;