# ----------- Latency Compensation -----------

package ::;
use Modern::Perl;
no warnings 'uninitialized';
use ::Globals qw(:all);
use List::Util qw(max);

###### For etd only adjustment
#
#   remove (or reset) latency operators
#   generate and connect setup
#   determine latency
#   add (or set) operators 
#    (to optimize: add operators only to plural sibling edges, not only edges)

sub calculate_and_adjust_latency {

	initialize_latency_vars();
	
	my $starting_track_name = $mode->{mastering} ?  'Boost' : 'Master'; 
	$debug and say "starting node: $starting_track_name";

	sibling_latency($starting_track_name);
	apply_latency_ops();
}

sub reset_latency_ops {
	map{ modify_effect($_->latency, 0, 0)  } ::Track::all()
}
sub remove_latency_ops {
	map{ ::remove_effect($_->latency) if $_->latency } ::Track::all()
}
sub apply_latency_ops {
	
	for ( ::ChainSetup::engine_tracks() )
	{ 	
		next unless has_siblings($_);
		
		# apply offset, keeping existing op_id
		::add_latency_control_op($_->n, $_->latency_offset); # keeps existing op_id

		# store offset for debugging
		
		$setup->{latency}->{track}->{$_->name}->{offset} = $_->latency_offset; 

  	}
}
sub has_siblings { 
	my $count = $setup->{latency}->{sibling_count}->{$_[0]->name};
	#say "track: ",$_[0]->name, " siblings: $count";
	$setup->{latency}->{sibling_count}->{$_[0]->name} > 1 
}

sub initialize_latency_vars {
	$setup->{latency} = {};
	$setup->{latency}->{track} = {};
	$setup->{latency}->{sibling} = {};
	$setup->{latency}->{sibling_count} = {};
}

sub track_latency {
	my $track = shift;

	# initialize
	my $node = $setup->{latency}->{track}->{$track->name} = {};
	my $accumulator = 0;

	### track effects latency
	
	$accumulator += ($node->{ops} = track_ops_latency($track));

	### track insert latency
	
	$accumulator += ($node->{insert} = insert_latency($track));

	### track's own latency
	
	$node->{own} = $accumulator;

	### track predecessor latency

	$accumulator += ($node->{predecessor} = predecessor_latency($track));

	### track total latency

	$node->{total} = $accumulator;

}
sub track_ops_latency {
	# LADSPA plugins return latency in milliseconds
	my $track = shift;
	my $total = 0;;
	map { $total += op_latency($_) } $track->fancy_ops;
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
	my @predecessors 
		= grep{ ::Graph::is_a_track($_) } 
			$setup->{latency_graph}->predecessors($track->name);
	scalar @predecessors or return 0;
	#say "track: ",$track->name;
	sibling_latency(@predecessors) + loop_device_latency();
}
sub sibling_latency {
	my @siblings = grep{ ::Graph::is_a_track($_) } @_; 
	my $node = $setup->{latency}->{sibling};
	#say join " ", "siblings:", @siblings;
	scalar @siblings or return 0;
	my $max = max map { track_latency($_) } map{$tn{$_}} @siblings;
	map { $node->{$_} = $max } @siblings;
	my $node2 = $setup->{latency}->{sibling_count};
	map { $node2->{$_} = scalar @siblings } @siblings;
	return $max
}
sub loop_device_latency { 
	# results in milliseconds
	$engine->{buffersize} / $config->{sample_rate} * 1000 
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
	local $config->{category} = 'ECI_FX';
	my ($op, $param) = @_;
	my $n = chain($op);
	my $i = ecasound_effect_index($op);
	eval_iam("c-select $n");
	eval_iam("cop-select $i");
	eval_iam("copp-select $param");
	eval_iam("copp-get")
}
1;
