# ---------- ChainSetup-----------

package ::ChainSetup;
use ::Globals qw($file $config $jack $setup $this_engine %tn %bn $mode :trackrw);
use ::Log qw(logsub logpkg);
use Modern::Perl;
use Data::Dumper::Concise;
use Storable qw(dclone);
use ::Util qw(signal_format input_node output_node);
use ::Assign qw(json_out);
no warnings 'uninitialized';

our (

	$g,  # routing graph object - 

		# based on project data 
		# the routing graph is generated,
		# then traversed over, and integrated
		# with track data to generate
		# ::IO objects. ::IO objects are iterated
		# over to generate 
		# the Ecasound chain setup text (c.f. chains command)

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
	);


sub remove_temporary_tracks {
	logsub("&remove_temporary_tracks");
	map { logpkg('debug',"removing temporary track ",$_->name); $_->remove  } 
		grep{ $_->group eq 'Temp'} 
		::audio_tracks();
}
sub initialize {

	remove_temporary_tracks(); # we will generate them again
	$setup->{audio_length} = 0;  
	@io = (); 			# IO object list
	::IO::initialize();
	$g = Graph->new(); 	
	%inputs = %outputs = %post_input = %pre_output = ();
	%is_ecasound_chain = ();
	@input_chains = @output_chains = @post_input = @pre_output = ();
	undef $chain_setup;
	::disable_length_timer();
	reset_aux_chain_counter();
	unlink $file->chain_setup;
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
	if( (ref $t) =~ /Track/){ $n = $t->n     }
	if( $t =~ ! /\D/ )      { $n = $t        }
	if( $t =~ /\D/ and $tn{$_} ){ $n = $::tn{$t}->n}
	$::ti{$n} if $is_ecasound_chain{$n}
}
sub engine_wav_out_tracks {
	grep{$_->rec_status eq REC} engine_tracks();
}
# return file output entries, including Mixdown 
sub really_recording { 
	my @files = map{ /-o:(.+?\.wav)$/} grep{ /-o:/ and /\.wav$/} split "\n", $chain_setup;
	wantarray() ? @files : scalar @files;
}
	
sub show_io {
	my $output = json_out( \%inputs ). json_out( \%outputs ); 
	::pager( $output );
}

sub generate_setup_try {
	logsub("&generate_setup_try");

	my $extra_setup_code = shift;

	# in an ideal CS world, all of the following routing
	# routines (add_paths_for_*) would be accomplished by
	# the track or bus itself, rather than handcoded below.
	
	# start with bus routing
	
	map{ $_->apply($g) } ::Bus::all();

	logpkg('debug',"Graph after bus routing:\n$g");
	
	# now various manual routing

	add_paths_for_aux_sends();
	logpkg('debug',"Graph after aux sends:\n$g");

	add_paths_from_Master();
	logpkg('debug',"Graph with paths from Master:\n$g");

	add_paths_for_mixdown_handling();
	logpkg('debug',"Graph with mixdown mods:\n$g");
	
	# run extra setup
	
	$extra_setup_code->($g) if $extra_setup_code;

	prune_graph();
	logpkg('debug',"Graph after pruning unterminated branches:\n$g");

	::Graph::expand_graph($g); 

	logpkg('debug',"Graph after adding loop devices:\n$g");

	# insert handling
	::Graph::add_inserts($g);

	logpkg('debug',"Graph with inserts:\n$g");

	# Mix tracks to mono if Master is mono
	# (instead of just throwing away right channel)

	if ($g->has_vertex('Master') and $tn{Master}->width == 1)
	{
		$g->set_vertex_attribute('Master', 'ecs_extra' => '-chmix:1')
	}
	#logpkg('info',sub{"Graph object dump:\n",Dumper($g)});

	# create IO lists %inputs and %outputs

	if ( process_routing_graph() ){
		write_chains(); 
		1
	} else { 
		::throw("No tracks to record or play.");
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
			and $_->rec_status ne OFF } ::audio_tracks();
}


sub add_paths_from_Master {
	logsub("&add_paths_from_Master");

	if ($mode->mastering){
		$g->add_path(qw[Master Eq Low Boost]);
		$g->add_path(qw[Eq Mid Boost]);
		$g->add_path(qw[Eq High Boost]);
	}
	my $final_leg_origin = $mode->mastering ?  'Boost' : 'Master';
	$g->add_path($final_leg_origin, output_node($tn{Master}->send_type)) 
		if $tn{Master}->rw ne OFF

}
sub add_paths_for_mixdown_handling {
	logsub("&add_paths_for_mixdown_handling");

	if ($tn{Mixdown}->rec_status eq REC){
		my @p = (($mode->mastering ? 'Boost' : 'Master'), ,'Mixdown', 'wav_out');
		$g->add_path(@p);
		$g->set_vertex_attributes('Mixdown', {
		  	format_template		=> $config->{mix_to_disk_format},
		  	chain_id	=> "Mixdown" },
		); 
		# no effects will be applied because effects are on chain 2
												 
	# Mixdown handling - playback
	
	} elsif ($tn{Mixdown}->rec_status eq PLAY){ 
			my @e = ('wav_in','Mixdown',output_node($tn{Master}->send_type));
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
	::Graph::simplify_send_routing($g);
	logpkg('debug',"Graph after simplify_send_routing:\n$g");
	::Graph::remove_out_of_bounds_tracks($g) if ::edit_mode();
	logpkg('debug',"Graph after remove_out_of_bounds_tracks:\n$g");
	::Graph::recursively_remove_inputless_tracks($g);
	logpkg('debug',"Graph after recursively_remove_inputless_tracks:\n$g");
	::Graph::recursively_remove_outputless_tracks($g); 
	logpkg('debug',"Graph after recursively_remove_outputless_tracks:\n$g");
}
# object based dispatch from routing graph
	
sub process_routing_graph {
	logsub("&process_routing_graph");

	# generate a set of IO objects from edges
	@io = map{ dispatch($_) } $g->edges;
	
	logpkg('debug', sub{ join "\n",map $_->dump, @io });

	# sort chain_ids by attached input object
	# one line will show all with that one input
	# -a:3,5,6 -i:foo
	
	map { 
		$inputs{$_->ecs_string} //= [];
		push @{$inputs{$_->ecs_string}}, $_->chain_id;
		# post-input modifiers
		$post_input{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} 
	grep { $_->direction eq 'input' } @io;

	# sort chain_ids by output

	map { 
		$outputs{$_->ecs_string} //= [];
		push @{$outputs{$_->ecs_string}}, $_->chain_id;
		# pre-output modifers
		$pre_output{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} 
	grep { $_->direction eq 'output' } @io;

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
	logpkg('debug',"non-track IO dispatch:",join ' -> ',@$edge);
	my $eattr = $g->get_edge_attributes(@$edge) // {};
	logpkg('debug',"found edge attributes: ",json_out($eattr)) if $eattr;

	my $vattr = $g->get_vertex_attributes($edge->[0]) // {};
	logpkg('debug',"found vertex attributes: ",json_out($vattr)) if $vattr;

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
		logpkg('debug',"non-track: $_, class: $class, chain_id: $attrib->{chain_id},","device_id: $attrib->{device_id}");
		my $io = $class->new($attrib ? %$attrib : () ) ;
		$g->set_edge_attribute(@$edge, $direction, $io);
		$io;
	} @$edge;
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
	logpkg('debug','dispatch: ',join ' -> ',  @$edge);
	my($name, $endpoint, $direction) = decode_edge($edge);
	logpkg('debug',"name: $name, endpoint: $endpoint, direction: $direction");
	my $track = $tn{$name};
	my $class = ::IO::get_class( $endpoint, $direction );
		# we need the $direction because there can be 
		# edges to and from loop,Master_in
		
	my @args = (track => $name,
				endpoint => massaged_endpoint($track, $endpoint, $direction),
				chain_id => $tn{$name}->n, # default
				override($name, $edge));   # priority: edge > node
	#say "dispatch class: $class";
	my $io = $class->new(@args);

	$g->set_edge_attribute(@$edge, $direction => $io );
	$io
}
sub massaged_endpoint {
	my ($track, $endpoint, $direction) = @_;
	if ( $endpoint =~ /^(loop_in|loop_out)$/ ){
		my $final = ($direction eq 'input' ?  $track->source_id : $track->send_id );
		$final =~ s/^loop,//;
		$final		
	} else { $endpoint }
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
	
	my $globals .= join " ", $config->{engine_globals}->{common},
							join(',', '-G:jack',$this_engine->name,$this_engine->jack_transport_mode),
							"-b",$config->buffersize,
							$config->globals_realtime;
	
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
	logpkg('debug',"Chain setup:\n",$ecs_file);
	open(my $fh, ">", $file->chain_setup) 
		or die("can't open chain setup file ".$file->chain_setup.": $!");
	print $fh $ecs_file;
	close $fh;
	$chain_setup = $ecs_file;

}
sub setup_requires_realtime {
	my $prof = $config->{realtime_profile};
	if( $prof eq 'auto'){
		grep{ ! $_->is_mix_track 
				  and $_->is_user_track 
				  and $_->rec_status eq REC 
			} ::audio_tracks() 
	} elsif ( $prof eq 'realtime') {
		my @fields = qw(soundcard jack_client jack_manual jack_ports_list);
		grep { has_vertex("$_\_in") } @fields 
			or grep { has_vertex("$_\_out") } @fields
	}
	elsif ( $prof eq 'nonrealtime' or !$prof){ 0 }
}

sub has_vertex { $g->has_vertex($_[0]) }

1;

=head1 ::ChainSetup - routines for generating Ecasound chain setup

=head2 Overview

For the Ecasound engine to run, it must be configured into a
signal processing network. This configuration is called a
"chain setup".  It is a graph comprised of multiple signal
processing chains, each of which consists of exactly one
input and one output.

When user input requires a change of configuration, Nama
generates an new chain setup file. These files are
guaranteed to be consistent with the rules of Ecasound's
routing language. 

After initializing the data structures, Nama iterates over
project tracks and buses to create a first-stage graph.
This graph is successively transformed as more routing
details are added, then each edge of the graph is processed
into a pair of IO objects--one for input and one for
output--that together constitute an Ecasound chain. With a
bit more processing, the configuration is written out 
as text in the chain setup file.

=head2 The Graph and its Transformations

Generating a chain setup starts with each bus iterating over
its member tracks, and connecting them to its mix track.
(See man ::Bus.)

In the case of one track belonging to the Main (default) 
bus, the initial graph would be:

	soundcard_in -> sax -> Master -> soundcard_out

"soundcard_in" and "soundcard_out" will eventually be mapped
to the appropriate JACK or ALSA source, depending on whether
jackd is running. The Master track hosts the master fader,
connects to the main output, and serves as the mix track for
the Main bus.

If we've asked to record the input, we automatically get
this route:

	soundcard_in -> sax-rec-file -> wav_out

The track 'sax-rec-file' is a temporary clone (slave) of track 'sax'
and connects to all the same inputs.

A 'send' (for example, a instrument monitor for
the sax player) generates this additional route:

	sax -> soundcard_out

Ecasound requires that we insert a loop device where signals fan 
out or fan in.

	soundcard_in -> sax -> sax_out -> Master -> soundcard_out

	                       sax_out -> soundcard_out

Here 'sax_out' is a loop device. (Note that we prohibit
track names matching *_out or *_in.)

Inserts are incorporated by replacing the edge either before
or after a track vertex with a network of auxiliary tracks and 
loop devices.  (See man ::Insert.)

Unterminated parts of the network are discarded. Then
redundant loop devices are removed from the graph to
minimize latency.

=head2 Dispatch

After routing is complete, Nama iterates over the graph's
edges, transforming them into pairs of IO objects that
become the inputs and outputs of Ecasound chains.

To create an Ecasound chain from 

	Master -> soundcard_out 

Nama uses 'Master' track attributes to provide
data. For example track index (1) serves as the chain_id,
and the track's send settings determine the soundcard
channel or other destination. 

Some edges are without a track at either terminal. For
example this auxiliary send:

	sax_out -> soundcard_out

In this case, the track, chain_id and other data can be
specified as vertex or edge attributes. 

Edge attributes override vertex attributes, which override
track attributes. This allows routing to be edited and
annotated to behaviors different from what the track wants.
When a temporary track is used for recording, for example

    sax-rec-file  -> wav_out

The 'sax-rec-file' vertex is assigned the 'chain_id' attribute 
'R3' rather than the track index assigned to 'sax-rec-file'. 
