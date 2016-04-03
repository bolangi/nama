package ::TrackLatency;
use Role::Tiny;
use Modern::Perl;
use ::Globals qw($setup);

sub latency_offset {
	my $track = shift;
	no warnings 'uninitialized';
	$setup->{latency}->{sibling}->{$track->name} 
		- $setup->{latency}->{track}->{$track->name}->{total};
}

sub capture_latency {
	my $track = shift;
	my $io = $track->input_object;
	return $io->capture_latency if ref $io;
}
sub playback_latency {
	my $track = shift;
	my $io = $track->input_object;
	return $io->playback_latency if ref $io;
}
sub sibling_latency {
	my $track = shift;
	$setup->{latency}->{sibling}->{$track->name}
}
sub sibling_count {
	my $track = shift;
	$setup->{latency}->{sibling_count}->{$track->name}
}

1;
