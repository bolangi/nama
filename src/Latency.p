# ----------- Latency Compensation -----------

package ::;
use Modern::Perl;
no warnings 'uninitialized';
use ::Globals qw(:all);
use List::Util qw(max);

sub track_latency {
	my $track = shift;
	my $total = 0;
	map { $total += op_latency($_) } $track->fancy_ops;
	$total += insert_latency($track);
	$total += predecessor_latency($track);
	$setup->{track_latency}->{$track->name} = $total;
	$total
}
sub insert_latency {
	my $track = shift;
	my $latency = 0;
	map{ $latency += $_->latency}
		grep{ $_ }
		map{ $::Insert::by_index{$_} }
		($track->prefader_insert, $track->postfader_insert);
	$latency;
}
sub predecessor_latency {
	my $track = shift;
	my @predecessors = $setup->{latency_graph}->predecessors($track->name);
	scalar @predecessors or return 0;
	sibling_latency(@predecessors) + loop_device_latency();
}
sub sibling_latency {
	my @siblings = grep{ $tn{$_} } @_; # filter out non-tracks (sources)
	scalar @siblings or return 0;
	my $max = max map { track_latency($_) } map { $tn{$_} } @siblings;
	map { $setup->{sibling_latency}->{$_} = $max } @siblings;
	return $max
}
sub loop_device_latency { 
	$engine->{buffersize} / $config->{sample_rate} # i.e. soundcard frequency
}

sub op_latency {
	my $op = shift;
	return 0 if is_controller($op); # skip controllers
	my $p = latency_param($op);
	defined $p 
		? get_live_param($op, $p) 
		: 0
}
sub latency_param {
	my $op = shift;
	my $i = effect_index(type($op));	
	my $p = 0; 
	for my $param ( @{ $fx_cache->{registry}->[$i]->{params} } )
	{
		$p++;
		return $p if lc( $param->{name}) eq 'latency' 
					and $param->{dir} eq 'output';
	}
	undef
}
sub get_live_param { # for effect, not controller
					 # $param is position, starting at one
	my ($op, $param) = @_;
	my $n = chain($op);
	my $i = ecasound_effect_index($op);
	eval_iam("c-select $n");
	eval_iam("cop-select $i");
	eval_iam("copp-select $param");
	eval_iam("copp-get")
}
1;
