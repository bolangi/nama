# ----------- Latency Compensation -----------

package ::;
use Modern::Perl;
no warnings 'uninitialized';
use ::Globals qw(:all);
use Storable qw(dclone);
use List::Util qw(max);
use Carp qw(confess);
my $lg; # latency_graph, alias to $jack->{graph}

latency_memoize();

sub initialize_jack_graph {

	# make our own copy of the signal network, and an alias
	$lg = $jack->{graph} = dclone($g);

	# remove record-to-disk branches of the graph
	# which are unrelated to latency compensation
	
	remove_connections_to_wav_out($lg);

	# want to deal with specific ports,
	# so substitute them into the graph
	
	replace_terminals_by_jack_ports($lg);
}


sub propagate_latency {   
	logsub((caller(0))[3]);

	initialize_jack_graph();
	logpkg('debug',"jack graph\n","$lg");
	parse_port_connections();
	start_latency_watcher();
	propagate_capture_latency();
	#propagate_playback_latency();
} 
sub propagate_capture_latency {

    my @sinks = grep{ $lg->is_sink_vertex($_) } $lg->vertices();

	logpkg('debug',"recurse through latency graph starting at sinks: @sinks");
	latency_rememoize();
	map{ latency_of($lg,'capture',$_) } @sinks;
}

sub propagate_playback_latency {
	logsub((caller(0))[3]); 
 	logpkg('debug',"jack graph\n","$lg");
    my @sources = grep{ $lg->is_source_vertex($_) } $lg->vertices();
 	logpkg('debug',"recurse through latency graph starting at sources: @sources");
	latency_rememoize();
 	map{ latency_of($lg,'playback',$_) } @sources;
 }

sub predecessor_latency {
	scalar @_ > 2 and die "too many args to predecessor_latency: @_";
	my ($g, $v) = @_;
	my $latency = latency_of($g, 'capture', $g->predecessors($v));
	logpkg('debug',"$v: predecessor latency is $latency");
	$latency;
}
sub successor_latency {
	scalar @_ > 2 and die "too many args to successor_latency: @_";
	my ($g, $v) = @_;
	my $latency = latency_of($g, 'playback', $g->successors($v));
	logpkg('debug',"$v: successor latency is $latency");
	$latency
}

sub latency_of {
	my ($g, $direction, @v) = @_;

	if ($direction eq 'capture' and $g->is_sink_vertex(@v)){

		die "too many args: @v" if scalar @v > 1;
		my $latency = predecessor_latency($g, @v);
		set_capture_latency($latency->values, jack_port_to_nama(@v));
		$latency
	}
	elsif($direction eq 'playback' and $g->is_source_vertex(@v)){

		die "too many args: @v" if scalar @v > 1;
		my $latency = successor_latency($g,@v);
		set_playback_latency($latency->values, jack_port_to_nama(@v));
		$latency
	}
	elsif(scalar @v == 1){ self_latency($g, $direction, @v) }
		
	elsif(scalar @v > 1){ sibling_latency($g, $direction, @v) }
}
sub track_ops_latency {
	my $track = shift;
	my $total = 0;;
	map { $total += op_latency($_) } $track->user_ops;
	::Lat->new($total,$total);
}
sub op_latency {
	my $op = shift;
	my $FX = fxn($op);
	return 0 if $FX->is_controller; # skip controllers
	my $p = latency_param($op);
	defined $p and ! $FX->bypassed
		? get_live_param($op, $p) 
		: 0
}
sub loop_device_latency { ::Lat->new($config->buffersize, $config->buffersize) }

sub input_latency { 
	my $port = shift;
	my $latency = get_capture_latency($port);
	carp("port $port, asymmetrical latency $latency found\n") 
		if is_asymmetrical($latency);
	set_capture_latency($latency->values, jack_port_to_nama($port));
	$latency
}
sub is_asymmetrical { my $lat = shift; $lat->min != $lat->max }

{ my %loop_adjustment;
sub sibling_latency {
    my ($g, $direction, @siblings) = @_;
	logpkg('debug',"direction: $direction, Siblings were: @siblings");

	if ($direction eq 'capture'){
		%loop_adjustment = ();
		#@siblings = map{ advance_sibling($g, $_) } @siblings;
		logpkg('debug',"Siblings are now: @siblings");

		my $max = max map {$_->max} 
						map{ self_latency($g, $direction, $_) } @siblings;

		logpkg('debug',"$max frames max latency among siblings: @siblings");
		for (@siblings) { 
			my $latency = self_latency($g, $direction, $_);
			my $delay = $max - $latency->max;
			logpkg('debug',"$_: self latency: $latency frames");
			logpkg('debug',"$_: delay $delay frames");
			compensate_latency($tn{$_},$delay);
		}
		::Lat->new($max,$max);
	}
	elsif ($direction eq 'playback'){
		my ($final_min, $final_max);
		for (@siblings){
			my $latency = self_latency($g, $direction, $_);
			my ($min,$max) = $latency->values;
			$final_min //= $min;
			$final_min = $min if $min < $final_min;
			$final_max //= $max;
			$final_max = $max if $max > $final_max;
		}
		$final_min, $final_max
	}
	else { die "missing or illegal direction: $direction" }
}
# not object method
sub loop_adjustment { 
		my $trackname = shift;
		my $delta = $loop_adjustment{$trackname} || 0;
		::Lat->new($delta, $delta)
}
sub self_latency {
	my ($g, $direction, $node_name) = @_;
	return input_latency($node_name) if $g->is_source_vertex($node_name);
	my $latency = my $predecessor_or_successor_latency =
		$direction eq 'capture'
			? predecessor_latency($g, $node_name)
			: successor_latency($g, $node_name);
	ref $latency eq '::Lat' or die "wrong type for $node_name".Dumper $latency;

	return( 
			$predecessor_or_successor_latency
			+ track_ops_latency($tn{$node_name})
			+ loop_adjustment($node_name)
			+ ::Insert::soundcard_delay($node_name) 
				# if we're a wet return track and insert is
				# a hardware type, i.e. via the soundcard 
	) if ::Graph::is_a_track($node_name);

	return(
			$predecessor_or_successor_latency + loop_device_latency()
	) if ::Graph::is_a_loop($node_name);

	die "shouldn't reach here\nnodename: $node_name, graph:$g";
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
				params 	=> \@args,
		});

		$track->set(latency_op => $id);
	}
	$id
}






sub reset_latency_compensation {
 	map{ compensate_latency($_, 0) } grep{ $_->latency_op } ::audio_tracks();
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
		or ::pager_newline("$name: non existing JACK client"),
		return;
	$node->{$port}->{latency}->{$direction}->{min}
		ne $node->{$port}->{latency}->{$direction}->{max}
	and ::pager_newline('encountered unmatched latencies', 
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
	my $FX = fxn($op);
	my $n = $FX->chain;
	my $i = $FX->ecasound_effect_index;
	die "convert these direct IAM calls to cache";
	ecasound_iam("c-select $n");
	ecasound_iam("cop-select $i");
	ecasound_iam("copp-select $param"); 
	ecasound_iam("copp-get")
}

sub frames_to_secs { # One time conversion for delay op
	my $frames = shift;
	$frames / $project->{sample_rate};
}
sub start_latency_watcher {
	$jack->{watcher} ||= 
	jacks::JsClient->new("Nama latency manager", undef, $jacks::JackNullOption, 0);
}
sub get_latency {
	my ($pname, $direction) = @_;
	my %io = ( 
			capture => $jacks::JackCaptureLatency,
			playback => $jacks::JackPlaybackLatency,
	);
	my $port = $jack->{watcher}->getPort($pname);
	my $dir = $io{$direction};
	die "illegal direction $direction" unless defined $dir;
	# get latency as Jacks objects
	my $latency = $port->getLatencyRange($dir); 
	# convert to Nama object
	$latency = ::Lat->new($latency->min, $latency->max); 
}

sub set_latency {
	my ($pname, $direction, $min, $max) = @_;
	my %io = ( 
			capture => $jacks::JackCaptureLatency,
			playback => $jacks::JackPlaybackLatency,
	);
	my $port = $jack->{watcher}->getPort($pname);
	my $dir = $io{$direction};
	die "illegal direction $direction" unless defined $io{$direction};
	$port->setLatencyRange($dir, $min, $max);
	my $latency = get_latency($pname, $direction);
	my ($gmin,$gmax) = $latency->values;
	logpkg('debug',"set port $pname, $direction latency: $min, $max");
	logpkg('debug', ($min != $gmin and $max != $gmax)
			?  "Bad: got port $pname, $direction latency: $gmin, $gmax"
			:  "Verified!"
	);
}
sub set_multiport_latency {
	my ($direction, $min, $max, @pnames) = @_;
	map{ set_latency($_, $direction,$min, $max) } @pnames;
}
sub set_playback_latency {
	my ($min, $max, @pnames) = @_;
	set_multiport_latency('playback',$min, $max, @pnames)
}
sub set_capture_latency {
	my ($min, $max, @pnames) = @_;
	set_multiport_latency('capture',$min, $max, @pnames)
}
sub get_capture_latency  { get_latency($_[0], 'capture' )}

sub get_playback_latency { get_latency($_[0], 'playback')}


sub recompute_latencies {
    	$jack->{watcher}->recomputeLatencies();
}
1;
