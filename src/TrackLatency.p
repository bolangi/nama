package ::TrackLatency;
use Role::Tiny;
use v5.36;
our $VERSION = 1.0;
use ::Globals qw($setup);

sub latency_offset ($track) {
	no warnings 'uninitialized';
	$setup->{latency}->{sibling}->{$track->name} 
		- $setup->{latency}->{track}->{$track->name}->{total};
}

sub capture_latency ($track) {
	my $io = $track->input_object;
	return $io->capture_latency if $io isa '::IO';
}
sub playback_latency ($track) {
	my $io = $track->input_object;
	return $io->playback_latency if $io isa '::IO';
}
sub sibling_latency ($track) {
	$setup->{latency}->{sibling}->{$track->name}
}
sub sibling_count ($track) {
	$setup->{latency}->{sibling_count}->{$track->name}
}

1;
