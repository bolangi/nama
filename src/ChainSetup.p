# ---------- ChainSetup-----------

package ::ChainSetup;
use ::Globals qw($file $config $jack $setup $engine %tn %bn $mode);
use ::Log qw(logsub);
use Modern::Perl;
use Data::Dumper::Concise;
use Storable qw(dclone);
no warnings 'uninitialized';
use ::Util qw(signal_format input_node output_node);
use ::Assign qw(yaml_out);

our (

	$g,  # routing graph object

	@io, # IO objects corresponding to chain setup

	%is_ecasound_chain, # chains in final chain seutp

	# for sorting final result

	%inputs,
	%outputs,
	%post_input,
	%pre_output,

	# for final result
	
	@input_chains,	# list of input chain segments 
	@output_chains, # list of output chain segments
	@post_input,	# post-input chain operators
	@pre_output, 	# pre-output chain operators

	$chain_setup,	# final result as string
	$logger,
	);


sub initialize {
	$logger = Log::Log4perl->get_logger();
	::Graph::initialize_logger();
	delete $setup->{latency_graph};
	delete $setup->{final_graph};
	@io = (); 			# IO object list
	$g = Graph->new(); 	
	%inputs = %outputs = %post_input = %pre_output = ();
	%is_ecasound_chain = ();
	@input_chains = @output_chains = @post_input = @pre_output = ();
	undef $chain_setup;
	::disable_length_timer();
	reset_aux_chain_counter();
	{no autodie; unlink $file->chain_setup}
	$g;
}
sub ecasound_chain_setup { $chain_setup } 
sub is_ecasound_chain { $is_ecasound_chain{$_[0]} }

sub engine_tracks { # tracks that belong to current chain setup
     map{$::ti{$_}} grep{$::ti{$_}} keys %is_ecasound_chain;
}
sub is_engine_track { 
		# takes Track object, name or index
		# returns object if corresponding track belongs to current chain setup
	my $t = shift;
	my $n;
	given($t){
	when( (ref $_) =~ /Track/){ $n = $_->n     }
	when( ! /\D/ )            { $n = $_        }
	when(   /\D/ and $tn{$_} ){ $n = $::tn{$_}->n}
	}
	$::ti{$n} if $is_ecasound_chain{$n}
}
sub engine_wav_out_tracks {
	grep{$_->rec_status eq 'REC' and ! $_->rec_defeat } engine_tracks();
}
# return file output entries, including Mixdown 
sub really_recording { 
	map{ /-o:(.+?\.wav)$/} grep{ /-o:/ and /\.wav$/} split "\n", $chain_setup
}
	
sub show_io {
	my $output = yaml_out( \%inputs ). yaml_out( \%outputs ); 
	::pager( $output );
}

sub generate_setup_try {  # TODO: move operations below to buses
	logsub("&generate_setup_try");

	# in an ideal CS world, all of the following routing
	# routines (add_paths_for_*) would be accomplished by
	# the track or bus itself, rather than the Hand of God, as
	# appears below.
	#
	# On the other hand (or Hand!), one can't complain if
	# the Hand of God happens to be doing exactly the
	# right things. :-)

	my $automix = shift; # route Master to null_out if present
	
	# start with bus routing
	
	map{ $_->apply($g) } ::Bus::all();
	$logger->debug("Graph after bus routing:\n$g");
	
	# now various manual routing

	add_paths_for_aux_sends();
	$logger->debug("Graph after aux sends:\n$g");

	add_paths_from_Master(); # do they affect automix?
	$logger->debug("Graph with paths from Master:\n$g");

	# re-route Master to null for automix
	if( $automix){
		$g->delete_edges(map{@$_} $g->edges_from('Master')); 
		$g->add_edge(qw[Master null_out]);
		$logger->debug("Graph with automix mods:\n$g");
	}
	add_paths_for_mixdown_handling();
	$logger->debug("Graph with mixdown mods:\n$g");
	prune_graph();
	$setup->{latency_graph} = dclone($g);
	$logger->debug("Graph after pruning unterminated branches:\n$g");

	::Graph::expand_graph($g); 

	$logger->debug("Graph after adding loop devices:\n$g");

	# insert handling
	::Graph::add_inserts($g);

	$logger->debug("Graph with inserts:\n$g");

	::Graph::add_jack_io($g);
	$setup->{final_graph} = dclone($g);

	

	# Mix tracks to mono if Master is mono
	# (instead of just throwing away right channel)

	if ($g->has_vertex('Master') and $tn{Master}->width == 1)
	{
		$g->set_vertex_attribute('Master', 'ecs_extra' => '-chmix:1')
	}
	$logger->debug(sub{"Graph object dump:\n",Dumper($g)});

	# create IO lists %inputs and %outputs

	if ( process_routing_graph() ){
		write_chains(); 
		set_buffersize();
		1
	} else { 
		say("No tracks to record or play.");
		0
	}
}

sub add_paths_for_aux_sends {

	# currently this routing is track-oriented 

	# we could add this to the ::Bus base class
	# then suppress it in Mixdown and Master groups

	logsub("&add_paths_for_aux_sends");

	map {  ::Graph::add_path_for_aux_send($g, $_ ) } 
	grep { (ref $_) !~ /Slave/ 
			and $_->group !~ /Mixdown|Master/
			and $_->send_type 
			and $_->rec_status ne 'OFF' } ::Track::all();
}


sub add_paths_from_Master {
	logsub("&add_paths_from_Master");

	if ($mode->{mastering}){
		$g->add_path(qw[Master Eq Low Boost]);
		$g->add_path(qw[Eq Mid Boost]);
		$g->add_path(qw[Eq High Boost]);
	}
	my $final_leg_origin = $mode->{mastering} ?  'Boost' : 'Master';
	$g->add_path($final_leg_origin, output_node($tn{Master}->send_type)) 
		if $tn{Master}->rw ne 'OFF'

}
sub add_paths_for_mixdown_handling {
	logsub("&add_paths_for_mixdown_handling");

	if ($tn{Mixdown}->rec_status eq 'REC'){
		my @p = (($mode->{mastering} ? 'Boost' : 'Master'), ,'Mixdown', 'wav_out');
		$g->add_path(@p);
		$g->set_vertex_attributes('Mixdown', {
		  	format		=> signal_format($config->{mix_to_disk_format},$tn{Mixdown}->width),
		  	chain_id	=> "Mixdown" },
		); 
		# no effects will be applied because effects are on chain 2
												 
	# Mixdown handling - playback
	
	} elsif ($tn{Mixdown}->rec_status eq 'MON'){
			my @e = qw(wav_in Mixdown soundcard_out);
			$g->add_path(@e);
			$g->set_vertex_attributes('Mixdown', {
				send_type	=> $tn{Master}->send_type,
				send_id		=> $tn{Master}->send_id,
				chain			=> "Mixdown" }); 
		# no effects will be applied because effects are on chain 2
	}
}
sub prune_graph {
	logsub("&prune_graph");
	# prune graph: remove tracks lacking inputs or outputs
	::Graph::remove_out_of_bounds_tracks($g) if ::edit_mode();
	::Graph::recursively_remove_inputless_tracks($g);
	::Graph::recursively_remove_outputless_tracks($g); 
}
# new object based dispatch from routing graph
	
sub process_routing_graph {
	logsub("&process_routing_graph");

	# generate a set of IO objects from edges
	@io = map{ dispatch($_) } $g->edges;
	
	$logger->debug( sub{ join "\n",map $_->dump, @io });

	# sort chain_ids by attached input object
	# one line will show all with that one input
	# -a:3,5,6 -i:foo
	
	map{ $inputs{$_->ecs_string} //= [];
		push @{$inputs{$_->ecs_string}}, $_->chain_id;

	# supplemental post-input modifiers
	
		$post_input{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} grep { $_->direction eq 'input' } @io;

	# sort chain_ids by output

	map{ $outputs{$_->ecs_string} //= [];
		push @{$outputs{$_->ecs_string}}, $_->chain_id;

	# pre-output modifers
	
		$pre_output{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} grep { $_->direction eq 'output' } @io;

	no warnings 'numeric';
	my @in_keys = values %inputs;
	my @out_keys = values %outputs;
	use warnings 'numeric';
	%is_ecasound_chain = map{ $_, 1} map{ @$_ } values %inputs;

	# sort entries into an aesthetic order

	my %rinputs = reverse %inputs;	
	my %routputs = reverse %outputs;	
	@input_chains = sort map {'-a:'.join(',',sort by_chain @$_)." $rinputs{$_}"} @in_keys;
	@output_chains = sort map {'-a:'.join(',',sort by_chain @$_)." $routputs{$_}"} @out_keys;
	@post_input = sort by_index map{ "-a:$_ $post_input{$_}"} keys %post_input;
	@pre_output = sort by_index map{ "-a:$_ $pre_output{$_}"} keys %pre_output;
	@input_chains + @output_chains # to sense empty chain setup
}
{ my ($m,$n,$o,$p,$q,$r);
sub by_chain {
	($m,$n,$o) = $a =~ /(\D*)(\d+)(\D*)/ ;
	($p,$q,$r) = $b =~ /(\D*)(\d+)(\D*)/ ;
	if ($n != $q){ $n <=> $q }
	elsif ( $m ne $p){ $m cmp $p }
	else { $o cmp $r }
}
}
sub by_index {
	my ($i) = $a =~ /(\d+)/;
	my ($j) = $b =~ /(\d+)/;
	$i <=> $j
}

sub non_track_dispatch {

	# loop -> loop
	#	
	# assign chain_id to edge based on chain_id of left-side loop's
	# corresponding track:
	#	
	# hihat_out -- J7a -> Master_in
	#
	# soundcard_in -> wav_out (rec_file)
	#
	# currently handled using an anonymous track
	#
	# we expect edge attributes 
	# to have been provided for handling this. 

	# loop -> soundcard_out
	#
	# track7-soundcard_out as aux_send will have chain id S7
	# that will be transferred by expand_graph() to 
	# the new edge, loop-soundcard-out

	# we will issue two IO objects, one for the chain input
	# fragment, one for the chain output
	
	
	my $edge = shift;
	$logger->debug("non-track IO dispatch:",join ' -> ',@$edge);
	my $eattr = $g->get_edge_attributes(@$edge) // {};
	$logger->debug("found edge attributes: ",yaml_out($eattr)) if $eattr;

	my $vattr = $g->get_vertex_attributes($edge->[0]) // {};
	$logger->debug("found vertex attributes: ",yaml_out($vattr)) if $vattr;

	if ( ! $eattr->{chain_id} and ! $vattr->{chain_id} ){
		my $n = $eattr->{n} || $vattr->{n};
		$eattr->{chain_id} = jumper_count($n);
	}
	my @direction = qw(input output);
	map{ 
		my $direction = shift @direction;
		my $class = ::IO::get_class($_, $direction);
		my $attrib = {%$vattr, %$eattr};
		$attrib->{endpoint} //= $_ if ::Graph::is_a_loop($_); 
		$logger->debug("non-track: $_, class: $class, chain_id: $attrib->{chain_id},","device_id: $attrib->{device_id}");
		$class->new($attrib ? %$attrib : () ) } @$edge;
		# we'd like to $class->new(override($edge->[0], $edge)) } @$edge;
}

{ 
### counter for jumper chains 
#
#   sequence: J1 J1a J1b J1c, J2, J3, J4, J4d, J4e

my %used;
my $counter;
my $prefix = 'J';
reset_aux_chain_counter();
  
sub reset_aux_chain_counter {
	%used = ();
	$counter = 'a';
}
sub jumper_count {
	my $track_index = shift;
	my $try1 = $prefix . $track_index;
	$used{$try1}++, return $try1 unless $used{$try1};
	$try1 . $counter++;
}
}
	

sub dispatch { # creates an IO object from a graph edge
my $edge = shift;
	return non_track_dispatch($edge) if not grep{ $tn{$_} } @$edge ;
	$logger->debug('dispatch: ',join ' -> ',  @$edge);
	my($name, $endpoint, $direction) = decode_edge($edge);
	$logger->debug("name: $name, endpoint: $endpoint, direction: $direction");
	my $track = $tn{$name};
	my $class = ::IO::get_class( $endpoint, $direction );
		# we need the $direction because there can be 
		# edges to and from loop,Master_in
	my @args = (track => $name,
			endpoint => $endpoint, # for loops
				chain_id => $tn{$name}->n, # default
				override($name, $edge));   # priority: edge > node
	#say "dispatch class: $class";
	$class->new(@args);
}
sub decode_edge {
	# assume track-endpoint or endpoint-track
	# return track, endpoint
	my ($a, $b) = @{$_[0]};
	#say "a: $a, b: $b";
	my ($name, $endpoint) = $tn{$a} ? @{$_[0]} : reverse @{$_[0]} ;
	my $direction = $tn{$a} ? 'output' : 'input';
	($name, $endpoint, $direction)
}
sub override {
	# data from edges has priority over data from vertexes
	# we specify $name, because it could be left or right 
	# vertex
	logsub("&override");
	my ($name, $edge) = @_;
	(override_from_vertex($name), override_from_edge($edge))
}
	
sub override_from_vertex {
	my $name = shift;
		warn("undefined graph\n"), return () unless (ref $g) =~ /Graph/;
		my $attr = $g->get_vertex_attributes($name);
		$attr ? %$attr : ();
}
sub override_from_edge {
	my $edge = shift;
		warn("undefined graph\n"), return () unless (ref $g) =~ /Graph/;
		my $attr = $g->get_edge_attributes(@$edge);
		$attr ? %$attr : ();
}
							
sub write_chains {

	logsub("&write_chains");

	## write general options
	
	my $globals = $config->{engine_globals_general};
	$globals .=  setup_requires_realtime()
			? join " ", " -b:$config->{engine_buffersize_realtime}", 
				$config->{engine_globals_realtime}
			: join " ", " -b:$config->{engine_buffersize_nonrealtime}", 
				$config->{engine_globals_nonrealtime};

	# use realtime globals if they exist and we are
	# recording to a non-mixdown file
	
	$globals = $config->{engine_globals_realtime}
		if $config->{engine_globals_realtime} 
			and grep{ ! /Mixdown/} really_recording();
			# we assume there exists latency-sensitive monitor output 
			# when recording
	
	my $format = signal_format($config->{devices}->{jack}->{signal_format},2);
	$globals .= " -f:$format" if $jack->{jackd_running};
			
	my $ecs_file = join "\n\n", 
					"# ecasound chainsetup file",
					"# general",
					$globals, 
					"# audio inputs",
					join("\n", @input_chains), "";
	$ecs_file .= join "\n\n", 
					"# post-input processing",
					join("\n", @post_input), "" if @post_input;				
	$ecs_file .= join "\n\n", 
					"# pre-output processing",
					join("\n", @pre_output), "" if @pre_output;
	$ecs_file .= join "\n\n", 
					"# audio outputs",
					join("\n", @output_chains), "";
	$logger->debug("Chain setup:\n",$ecs_file);
	open my $fh, ">", $file->chain_setup;
	print $fh $ecs_file;
	close $fh;
	$chain_setup = $ecs_file;

}
sub setup_requires_realtime {
	my @fields = qw(soundcard jack_client jack_manual jack_ports_list);
	grep { has_vertex("$_\_in") } @fields 
		or grep { has_vertex("$_\_out") } @fields

}
sub has_vertex { $setup->{final_graph}->has_vertex($_[0]) }

sub set_buffersize { 
	my $buffer_type = setup_requires_realtime() ? "realtime" : "nonrealtime";
	$engine->{buffersize} = $config->{"engine_buffersize_$buffer_type"}	;
}

1;
__END__
