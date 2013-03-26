# ----------- Latency Compensation -----------

package ::;
use Modern::Perl;
no warnings 'uninitialized';
use ::Globals qw(:all);
use Storable qw(dclone);
use List::Util qw(max);
use Carp qw(confess);
our $lg; # latency_graph
sub propagate_latency {   
	# make our own copy of the graph
	$lg = dclone($g);
	remove_connections_to_wav_out($lg);
	replace_terminals_by_jack_ports($lg);
    my @sinks = grep{ $lg->is_sink_vertex($_) } $lg->vertices();
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
			my $output = $g->get_edge_attribute(@$edge, "output");
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
			my $input = $g->get_edge_attribute(@$edge, "input");
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
sub predecessor_latency {
    my $edge = shift;

	my ($upstream, $downstream) = @$edge;
	if( ::Graph::is_terminal($downstream) ){

		# report predecessor latency 
	}
	elsif( ::Graph::is_terminal($upstream) ){

		# ask for latency

	}
	# three cases:
	# 1. downstream vertex is terminal
	#report_latency(get_output_port($_), 
	# 2. neither vertex is terminal
	# 3. upstream vertex is terminal
	
    my @predecessors = $lg->predecessors($downstream);

	# with one predecessor, return its latency
    return self_latency(@predecessors) if scalar @predecessors == 1;

	# if multiple predecessors, equalize the siblings
	# and return the latency
	
    sibling_latency(@predecessors);
}
sub sibling_latency {
    my @siblings = @_;
	my %self_latency; # cache returned values
    my $max = max map { $self_latency{$_} = self_latency($_) } @siblings;
    for (@siblings) { compensate_latency($_, $max - $self_latency{$_}) }
    $max
}

sub self_latency {
	my $node_name = shift;
	my $latency;
	$latency = track_latency($node_name) if ::Graph::is_a_track($node_name);
	$latency = loop_latency($node_name)  if ::Graph::is_loop($node_name);
	$latency = input_latency($node_name) if ::Graph::is_terminal($node_name);
	$latency + predecessor_latency($node_name) 
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







sub adjust_latency {
	eval_iam('cs-disconnect');

	for ( ::ChainSetup::engine_tracks() )
	{ 	
		next unless has_siblings($_) and $_->latency_offset;

		#set_latency_compensation($_, $_->latency_offset);

		# store offset for debugging
		$setup->{latency}->{track}->{$_->name}->{offset} = $_->latency_offset; 

  	}
	connect_transport('quiet');
}
sub cl2 {

	initialize_latency_vars();
=comment
	get predecessors of all output types (wav_out, etc)
	sibling latency groups from soundcard_out 
	start with same as currently (Master/Boost and Mixdown)


	each item

	set own latency

	is loop device # set own latency
	is track	   # set own latency
	is output
	is input 

	get predecessors of all output types (wav_out, etc)
	set outputs

	propagate latency
	propagate again 
	

	#walk($coderef_set_own_latency)
	
=cut



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

sub track_latency {
	my $track = shift;
	track_ops_latency($track);
}
sub track_ops_latency {
	# LADSPA plugins return latency in frames
	my $track = shift;
	my $total = 0;;
	map { $total += op_latency($_) } $track->fancy_ops;
	$total
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
sub loop_device_latency { 
	# results in frames
	$engine->{buffersize}; 
}

sub op_latency {
	my $op = shift;
	return 0 if is_controller($op); # skip controllers
	my $p = latency_param($op);
	defined $p and ! bypassed($op)
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

sub frames_to_secs { # One time conversion for delay op
	my $frames = shift;
	$frames / $config->{sample_rate};
}

1;
