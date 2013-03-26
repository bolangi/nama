# ----------- Latency Compensation -----------

package ::;
use Modern::Perl;
no warnings 'uninitialized';
use ::Globals qw(:all);
use Storable qw(dclone);
use List::Util qw(max);
use Carp qw(confess);
sub propagate_latency {   

	# make our own copy of the latency graph, and an alias
	my $lg = $jack->{graph} = dclone($g);

	# remove record-to-disk branches of the graph
	# which are unrelated to latency compensation
	
	remove_connections_to_wav_out($lg);

	# want to deal with specific ports,
	# so substitute them into the graph
	
	replace_terminals_by_jack_ports($lg);
	
    my @sinks = grep{ $lg->is_sink_vertex($_) } $lg->vertices();
	logpkg('debug',"recurse through latency graph starting at sinks: sinks");
	map{ latency_of($lg,$_) } @sinks;
} 
sub predecessor_latency {
	scalar @_ > 2 and die "too many args to predecessor_latency: @_";
	my ($g, $v) = @_;
	my $latency = latency_of($g, $g->predecessors($v));
	logpkg('debug',"$v: predecessor_latency is $latency");
	$latency;
}
sub latency_of {
	my ($g, @v) = @_;
	return report_jack_port_latency(@v, predecessor_latency($g, @v))
		if scalar @v == 1 and $g->is_sink_vertex(@v);
	return self_latency($g, @v) if scalar @v == 1;
	return sibling_latency($g, @v) if scalar @v > 1;
}
sub self_latency {
	my ($g, $node_name) = @_;
	return input_latency($node_name) if $g->is_source_vertex($node_name);
	my $predecessor_latency = predecessor_latency($g, $node_name);
	return($predecessor_latency + track_ops_latency($tn{$node_name}))
		if ::Graph::is_a_track($node_name);
	return($predecessor_latency + loop_device_latency()) 
		if ::Graph::is_a_loop($node_name);
	die "shouldn't reach here\nnodename: $node_name, graph:$g";
}
sub track_ops_latency {
	# LADSPA plugins return latency in frames
	my $track = shift;
	my $total = 0;;
	map { $total += op_latency($_) } $track->fancy_ops;
	$total
}
sub op_latency {
	my $op = shift;
	return 0 if is_controller($op); # skip controllers
	my $p = latency_param($op);
	defined $p and ! bypassed($op)
		? get_live_param($op, $p) 
		: 0
}
sub loop_device_latency { 
	# results in frames
	$engine->{buffersize}; 
}
sub input_latency { 222 }

{ my %loop_adjustment;
sub sibling_latency {
    my ($g, @siblings) = @_;
	logpkg('debug',"Siblings were: @siblings");
	@siblings = map{ advance_sibling($g, $_) } @siblings;
	logpkg('debug',"Siblings are now: @siblings");
	my %self_latency; # cache returned values
    my $max = max map 
		# we fold into the track the latency of any
		# loop devices we advanced past to get 
		# to a track capable of providing latency
		# compensation
		{ $self_latency{$_} = 
			self_latency($g, $_) + $loop_adjustment{$_}  * $engine->{buffersize} 
		} @siblings;
    for (@siblings) { compensate_latency($tn{$_}, $max - $self_latency{$g, $_}) }
	logpkg('debug',"max latency among siblings:\n    @siblings\nis $max.");
    $max
}

### on encountering a loop device in a group
### of siblings, we advance that sibling
### to a track, and perform the latency
### compensation on a group of tracks,
### which provide a latency_op  

sub advance_sibling {
	my ($g, $head) = @_;
	my $loop_count = 0;
	while( ! ::Graph::is_a_track($head) ){
		my @predecessors = $g->predecessors($head);
		die "$head: too many predecessors!  @predecessors"
			if @predecessors > 1;
		my $predecessor = shift @predecessors;
		$head = $predecessor;
		$loop_count++;
	}
	$loop_adjustment{$head} = $loop_count;
	$head
}
}
sub remove_connections_to_wav_out {
	my $g = shift;
	::Graph::remove_branch($g,'wav_out');
	::Graph::remove_isolated_vertices($g);
}

sub replace_terminals_by_jack_ports {
	my $g = shift;

    my @sinks = grep{ $g->is_sink_vertex($_) } $g->vertices();
	my @sources = grep{ $g->is_source_vertex($_) } $g->vertices();

    for my $sink (@sinks) {
        #logpkg('debug')
		logpkg('debug',"found sink $sink");
		my @predecessors = $g->predecessors($sink);
		logpkg('debug',"preceeded by: @predecessors");
		my @edges = map{ [$_, $sink] } @predecessors;
		;
		logpkg('debug',"edges: ",json_out(\@edges));

		for my $edge ( @edges ) {
			logpkg('debug',"edge: @$edge");
			my $output = $g->get_edge_attribute(@$edge, "output")
				|| $g->get_vertex_attribute($edge->[0], "output");
			logpkg('debug',Dumper $output);
			logpkg('debug', join " ", 
				"JACK client:", $output->client, $output->ports);
			
			$g->delete_edge(@$edge);
			for my $port($output->ports()){
				$g->add_edge($edge->[0], $port);
				#$g->set_edge_attribute($edge->[0], $port, "output", $output);
			}
		}
    }
    for my $source (@sources) {
        #logpkg('debug')
		logpkg('debug',"found source $source");
		my @successors = $g->successors($source);
		logpkg('debug',"succeeded by: @successors");
		my @edges = map{ [$source, $_] } @successors;
		;
		logpkg('debug',"edges: ",json_out(\@edges));

		for my $edge ( @edges ) {
			my $input = $g->get_edge_attribute(@$edge, "input") ;
			logpkg('debug',Dumper $edge, Dumper $input);
			logpkg('debug', join " ", 
				"JACK client:", $input->client, $input->ports);
			$g->delete_edge(@$edge);
			for my $port($input->ports()){
				$g->add_edge($port, $edge->[1]);
				#$g->set_edge_attribute($port, $edge->[1], "input", $input);
			}
		}

	}
	::Graph::remove_isolated_vertices($g);

}

		
###### 
#
#   remove (or reset) latency operators
#   generate and connect setup
#   determine latency
#   add (or set) operators 
#    (to optimize: add operators only to plural sibling edges, not only edges)

sub compensate_latency {
	
	my $track = shift;
	my $delay = shift || 0;
	my $units = shift;

# because of brass_out -> system:playback_1, we
# need to advance past brass_out and do 
# latency compensation on 'brass' instead,
# adding in the loop device.

	my $id = $track->latency_op || add_latency_compensation_op ( $track );

	# execute coderef to modify effect, adjusting for units
	# assume frames by default
	# but don't convert to frames if $delay is 0
	
	$config->{latency_op_set}->( 
			$id, 
			(! $delay or $units =~ /^s/i) ? $delay : frames_to_secs($delay)
	);
	$id;
}
sub add_latency_compensation_op {

	# add the effect, and set the track's latency_op field
	
	my $track = shift;
	my @args = @_;
	@args or @args = (2,0);

	my $id = $track->latency_op;

	# create a delay effect if necessary, place before first effect
	# if it exists
	
	if (! $id){	
		my $first_effect = $track->ops->[0];
		$id = add_effect({
				before 	=> $first_effect, 
				track	=> $track,
				type	=> $config->{latency_op}, 
				values	=> \@args,
		});

		$track->set(latency_op => $id);
	}
	$id
}






sub reset_latency_compensation {
 	map{ compensate_latency($_, 0) } grep{ $_->latency_op } ::Track::all();
 }

sub initialize_latency_vars {
	$setup->{latency} = {};
	$setup->{latency}->{track} = {};
	$setup->{latency}->{sibling} = {};
	$setup->{latency}->{sibling_count} = {};
}

{ my %reverse = qw(input output output input);
sub jack_port_latency {

	my ($dir, $name) = @_; 
	my $direction;
	$direction = 'capture' if $dir eq 'input';
	$direction = 'playback' if $dir eq 'output';
	$direction or confess "$direction: illegal or missing direction";
	logpkg('debug', "name: $name, dir: $dir, direction: $direction");

	if ($name !~ /:/)
	{
		# we have only the client name, i.e. "system"
		# pick a port from the ports list 

		logpkg('debug',"$name is client desriptor, lacks specific port");

		# replace with a full port descriptor, i.e. "system:playback_1"
		# but reverse direction for this:
		my $node = jack_client($name);
		$name = $node->{$reverse{$dir}}->[0];

		logpkg('debug', "replacing with $name");
	}
	my ($client, $port) = client_port($name);
	logpkg('debug',"name: $name, client: $client, port: $port, dir: $dir, direction: $direction");
	my $node = jack_client($client)
		or ::pager3("$name: non existing JACK client"),
		return;
	$node->{$port}->{latency}->{$direction}->{min}
		ne $node->{$port}->{latency}->{$direction}->{max}
	and ::pager3('encountered unmatched latencies', 
		sub{ json_out($node) });
	$node->{$port}->{latency}->{$direction}->{min}
}
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

sub frames_to_secs { # One time conversion for delay op
	my $frames = shift;
	$frames / $config->{sample_rate};
}
sub report_jack_port_latency {
	my ($port, $latency) = @_;
	# rather than report directly for system:playback_1
	# we report our own port latency, something like
	# Nama:out_1
	logpkg('debug',"port $port: latency is $latency");
}
1;
