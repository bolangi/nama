# ---------- ChainSetup-----------
#
# variables we need to access


package ::;

# these variables are specific to chain setup
# and get initialized each time a chain setup
# is generated

our (	@io,
		$g,
		%inputs,
		%outputs,
		%post_input,
		%pre_output,
		%is_ecasound_chain,
		@input_chains,
		@output_chains,
		@post_input,
		@pre_output,
		$chain_setup,
		$length,
);
# these variables are other globals that 
# are touched in creating chain setups
our (	$debug,
		$debug2,
		$debug3,
		$this_track,
		$old_this_track,
		$preview,
		%tn,
		$main,
		$mastering_mode,
		$main_out,
		$mix_to_disk_format,
		$ecasound_globals_default,
		$ecasound_globals_realtime,
);		 	

package ::ChainSetup;

use Modern::Perl;
use ::Util qw(input_node output_node);

sub initialize {
	@io = (); 			# IO object list
	$g = Graph->new(); 	
	%inputs = %outputs = %post_input = %pre_output = ();
	%is_ecasound_chain = ();
	@input_chains = @output_chains = @post_input = @pre_output = ();
	undef $chain_setup;
	::disable_length_timer();
	reset_aux_chain_counter();
	$length = 0;
	{no autodie; unlink ::setup_file()}
}
sub generate_setup_try {  # TODO: move operations below to buses
	$debug2 and print "&generate_setup_try\n";

	# in an ideal CS world, all of the following routing
	# routines (add_paths_for_*) would be accomplished by
	# the track or bus itself, rather than the Hand of God, as
	# appears below.
	#
	# On the other hand (or Hand!), one can't complain if
	# the Hand of God happens to be doing exactly the
	# right things. :-)

	my $automix = shift; # route Master to null_out if present
	add_paths_for_main_tracks();
	$debug and say "The graph is:\n$g";
	add_paths_for_recording();
	$debug and say "The graph is:\n$g";
	add_paths_for_aux_sends();
	$debug and say "The graph is:\n$g";
	map{ $_->apply() } grep{ (ref $_) =~ /Send|Sub/ } ::Bus::all();
	$debug and say "The graph is:\n$g";
	add_paths_from_Master(); # do they affect automix?
	$debug and say "The graph is:\n$g";

	# re-route Master to null for automix
	if( $automix){
		$g->delete_edges(map{@$_} $g->edges_from('Master')); 
		$g->add_edge(qw[Master null_out]);
		$debug and say "The graph is:\n$g";
	}
	add_paths_for_mixdown_handling();
	$debug and say "The graph is:\n$g";
	prune_graph();
	$debug and say "The graph is:\n$g";

	::Graph::expand_graph($g); 

	$debug and say "The expanded graph is:\n$g";

	# insert handling
	::Graph::add_inserts($g);

	$debug and say "The expanded graph with inserts is\n$g";

	# create IO lists %inputs and %outputs

	if ( process_routing_graph() ){
		write_chains(); 
		1
	} else { 
		say("No tracks to record or play.");
		0
	}
}
sub add_paths_for_main_tracks {
	$debug2 and say "&add_paths_for_main_tracks";
	map{ 

		# connect signal sources to tracks
		
		my @path = $_->input_path;
		#say "Main bus track input path: @path";
		$::g->add_path(@path) if @path;

		# connect tracks to Master
		
		$::g->add_edge($_->name, 'Master'); 

	} 	
		grep{ 1 unless $preview eq 'doodle'
			 and $_->rec_status eq 'MON' } # exclude MON tracks in doodle mode	
		grep{ $_->rec_status ne 'OFF' }    # exclude OFF tracks
		map{$tn{$_}} 	                   # convert to Track objects
		$main->tracks;                     # list of Track names

}

sub add_paths_for_recording {
	$debug2 and say "&add_paths_for_recording";
	return if $preview; # don't record during preview modes

	# get list of REC-status tracks to record
	
	my @tracks = grep{ 
			(ref $_) !~ /Slave/  						# don't record slave tracks
			and not $_->group =~ /null|Mixdown|Temp/ 	# nor these groups
			and not $_->rec_defeat        				# nor rec-defeat tracks
			and $_->rec_status eq 'REC' 
	} ::Track::all();
	map{ 

		# Track input from a WAV, JACK client, or soundcard
		#
		# We record 'raw' signal, as per docs and design

		if( $_->source_type !~ /track|bus|loop/ ){
		
			# create temporary track for rec_file chain

			# we do this because the path doesn't
			# include the original track.
			#
			# but why not supply the track as 
			# an edge attribute, then the source
			# and output info can be provided 
			# that way.

			# Later, we will rewrite it that way

			$debug and say "rec file link for $_->name";	
			my $name = $_->name . '_rec_file';
			my $anon = ::SlaveTrack->new( 
				target => $_->name,
				rw => 'OFF',
				group => 'Temp',
				name => $name);

			# connect IO
			
			$g->add_path(input_node($_->source_type), $name, 'wav_out');

			# set chain_id to R3 (if original track is 3) 
			$g->set_vertex_attributes($name, { 
				chain_id => 'R'.$_->n,
				mono_to_stereo => '', # override 
			});

		} elsif ($_->source_type =~ /bus|track/) {

			# for tracks with identified (track|bus) input

			# cache_tracks/merge_edits has its own logic
			# therefore these connections (triggered from
			# generate_setup()) will not affect AFAIK
			# any other recording scenario

			# special case, record 'cooked' signal

			# generally a sub bus 
			# - has 'rec_defeat' set (therefore doesn't reach here)
			# - receives a stereo input
			# - mix track width is set to stereo (default)

			my @edge = ($_->name, 'wav_out'); # cooked signal

			$g->add_path(@edge); 

			# set chain_id to R3 (if original track is 3) 

			$g->set_edge_attributes(@edge, { 
				chain_id => 'R'.$_->n,
			});
			
			# if this path is left unconnected, 
			# i.e. track gets no input		
			# it will be removed by prune_graph()
			
			# to record raw:
			
			# source_type: loop
			# source_id:   loop,track_name_in

			# but for WAV to contain content, 
			# we need to guarantee that track_name as
			# an input
		}


	} @tracks;
}


sub add_paths_for_aux_sends {
	$debug2 and say "&add_paths_for_aux_sends";

	map {  add_path_for_one_aux_send( $_ ) } 
	grep { (ref $_) !~ /Slave/ 
			and $_->group !~ /Mixdown|Master/
			and $_->send_type 
			and $_->rec_status ne 'OFF' } ::Track::all();
}
sub add_path_for_one_aux_send {
	my $track = shift;
		my @e = ($track->name, output_node($track->send_type));
		$g->add_edge(@e);
		 $g->set_edge_attributes(@e,
			  {	track => $track->name,
				# force stereo output width
				width => 2,
				chain_id => 'S'.$track->n,});
}

sub add_paths_from_Master {
	$debug2 and say "&add_paths_from_Master";

	if ($mastering_mode){
		$g->add_path(qw[Master Eq Low Boost]);
		$g->add_path(qw[Eq Mid Boost]);
		$g->add_path(qw[Eq High Boost]);
	}
	$g->add_path($mastering_mode ?  'Boost' : 'Master',
			output_node($tn{Master}->send_type)) if $main_out;
 

}
sub add_paths_for_mixdown_handling {
	$debug2 and say "&add_paths_for_mixdown_handling";

	if ($tn{Mixdown}->rec_status eq 'REC'){
		my @p = (($mastering_mode ? 'Boost' : 'Master'), ,'Mixdown', 'wav_out');
		$g->add_path(@p);
		$g->set_vertex_attributes('Mixdown', {
		  	format		=> signal_format($mix_to_disk_format,$tn{Mixdown}->width),
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
	$debug2 and say "&prune_graph";
	# prune graph: remove tracks lacking inputs or outputs
	::Graph::remove_out_of_bounds_tracks($g) if ::edit_mode();
	::Graph::recursively_remove_inputless_tracks($g);
	::Graph::recursively_remove_outputless_tracks($g); 
}
# new object based dispatch from routing graph
	
sub process_routing_graph {
	$debug2 and say "&process_routing_graph";
	@io = map{ dispatch($_) } $g->edges;
	$debug and map $_->dumpp, @io;
	map{ $inputs{$_->ecs_string} //= [];
		push @{$inputs{$_->ecs_string}}, $_->chain_id;
		$post_input{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} grep { $_->direction eq 'input' } @io;
	map{ $outputs{$_->ecs_string} //= [];
		push @{$outputs{$_->ecs_string}}, $_->chain_id;
		$pre_output{$_->chain_id} = $_->ecs_extra if $_->ecs_extra;
	} grep { $_->direction eq 'output' } @io;
	no warnings 'numeric';
	my @in_keys = values %inputs;
	my @out_keys = values %outputs;
	use warnings 'numeric';
	%is_ecasound_chain = map{ $_, 1} map{ @$_ } values %inputs;

	# sort entries into an aesthetic order

	%inputs = reverse %inputs;	
	%outputs = reverse %outputs;	
	@input_chains = sort map {'-a:'.join(',',sort by_chain @$_)." $inputs{$_}"} @in_keys;
	@output_chains = sort map {'-a:'.join(',',sort by_chain @$_)." $outputs{$_}"} @out_keys;
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
	$debug and say "non-track dispatch: ",join ' -> ',@$edge;
	my $eattr = $g->get_edge_attributes(@$edge) // {};
	$debug and say "found edge attributes: ",yaml_out($eattr) if $eattr;

	my $vattr = $g->get_vertex_attributes($edge->[0]) // {};
	$debug and say "found vertex attributes: ",yaml_out($vattr) if $vattr;

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
		$debug and say "non-track: $_, class: $class, chain_id: $attrib->{chain_id},",
 			"device_id: $attrib->{device_id}";
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
	$debug and say 'dispatch: ',join ' -> ',  @$edge;
	my($name, $endpoint, $direction) = decode_edge($edge);
	$debug and say "name: $name, endpoint: $endpoint, direction: $direction";
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
	$debug2 and say "&override";
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

	$debug2 and print "&write_chains\n";

	## write general options
	
	my $globals = $ecasound_globals_default;

	# use realtime globals if they exist and we are
	# recording to a non-mixdown file
	
	$globals = $ecasound_globals_realtime
		if $ecasound_globals_realtime 
			and grep{ ! /Mixdown/} really_recording();
			# we assume there exists latency-sensitive monitor output 
			# when recording
			
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
	$debug and print "ECS:\n",$ecs_file;
	open my $setup, ">", ::setup_file();
	print $setup $ecs_file;
	close $setup;
	$chain_setup = $ecs_file;

}

1;
__END__
