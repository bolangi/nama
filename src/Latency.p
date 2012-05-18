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

sub add_latency_control_op {
	my $n = shift;
	my $delay = shift || 0;
	my $id = add_effect({
				chain => $n, 
				type => 'etd', # ecasound time delay operator
				cop_id => $ti{$n}->latency_op, # may be undef
				values => [ $delay,
							0,    # no surround mode
							1,    # 1 delay operation
							100,  # 100% delayed signal
							100 ],# feedback in each iteration
			# We will be adjusting the first (delay) parameter
				});
	
	$ti{$n}->set(latency_op => $id);  # save the id for next time
	$id;
}

sub calculate_and_adjust_latency {

	initialize_latency_vars();
	return if $config->{opts}->{O};
	
	my $starting_track_name = $mode->{mastering} ?  'Boost' : 'Master'; 
	logit('::Latency','debug',"starting node: $starting_track_name");

	sibling_latency($starting_track_name);
	apply_latency_ops();
}

sub reset_latency_ops {
	map{ modify_effect($_->latency_op, 0, 0) if $_->latency_op } ::Track::all();
}
sub remove_latency_ops {
	map{::remove_effect($_)} grep{ $_ and fx($_)} map{$_->latency_op} ::Track::all();
}
sub apply_latency_ops {
	
	for ( ::ChainSetup::engine_tracks() )
	{ 	
		next unless has_siblings($_) and $_->latency_offset;
		
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

	### track predecessor latency (if has tracks as predecessors)

	$accumulator += ($node->{predecessor} = predecessor_latency($track));

	### track source latency (if track has "live" i.e.  non-WAV input)

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
sub jack_client : lvalue {
	my $name = shift;
	# we require that every call is already known correct
	# try it till it breaks
	
	logit->logconfess("$name: non-existent JACK client") 
		if not $jack->{clients}->{$name} ;
	$jack->{clients}->{$name}

}
sub jack_client_node_latency {
	my ($names, $dir) = @_; # $names can be array_ref or scalar
	my $name;
	$name = ref $names ? $names->[0] : $names;
	my $direction = ($dir eq 'input') ? 'capture' : 'playback';
	my ($client, $port) = client_port($name);
	logit('::Latency','debug',"name: $name, client: $client, port: $port, dir: $dir, direction: $direction");
	my $node = jack_client($client)
		or logit('::Latency','debug',"$name: non existing JACK client"),
		return;
	$node->{$port}->{latency}->{$direction}->{min}
		ne $node->{$port}->{latency}->{$direction}->{max}
	and logit('::Latency','info','encountered unmatched latencies', 
		sub{ json_out($node) });
	$node->{$port}->{latency}->{$direction}->{min}
}
sub jack_client_playback_latency {
	my $name = shift;
	jack_client_node_latency($name,'output');
}
sub jack_client_capture_latency {
	my $name = shift;
	jack_client_node_latency($name,'input');
}
	
sub insert_latency {
	my $track = shift;
	my $latency = 0;
	map{ $latency += $_->latency} ::Insert::get_inserts($track->name);
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
