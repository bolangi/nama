package ::Graph;
use Modern::Perl;
use Carp;
use Graph;
use vars qw(%reserved $debug $debug2);
# this dispatch table also identifies labels reserved
# for signal sources and sinks.
*reserved = \%::IO::io_class;
*debug = \$::debug;
*debug2 = \$::debug2;

my %seen;

sub expand_graph {
	
	my $g = shift; 
	%seen = ();
	
	
	for ($g->edges){
		my($a,$b) = @{$_}; 
		$debug and say "$a-$b: processing...";
		$debug and say "$a-$b: already seen" if $seen{"$a-$b"};
		next if $seen{"$a-$b"};

		# case 1: both nodes are tracks: default insertion logic
	
		if ( is_a_track($a) and is_a_track($b) ){ 
			$debug and say "processing track-track edge: $a-$b";
			add_loop($g,$a,$b) } 

		# case 2: fan out from track: use near side loop

		elsif ( is_a_track($a) and $g->successors($a) > 1 ) {
			$debug and say "fan_out from track $a";
			add_near_side_loop($g,$a,$b,out_loop($a));}
	
		# case 3: fan in to track: use far side loop
		
		elsif ( is_a_track($b) and $g->predecessors($b) > 1 ) {
			$debug and say "fan in to track $b";
			add_far_side_loop($g,$a,$b,in_loop($b));}
		else { $debug and say "$a-$b: no action taken" }
	}
	
}
sub add_path {
	my @nodes = @_;
	$debug and say "adding path: ", join " ", @nodes;
	$::g->add_path(@nodes);
}
sub add_edge { add_path(@_) }
	
sub add_inserts {
	my $g = shift;
	map{ my $i = $::tn{$_}->prefader_insert;
		 $::Insert::by_index{$i}->add_paths($g, $_) if $i;
			$i = $::tn{$_}->postfader_insert;
		 $::Insert::by_index{$i}->add_paths($g, $_) if $i;
	}
	grep{ $::tn{$_} } 
	$g->vertices;
}

sub add_loop {
	my ($g,$a,$b) = @_;
	$debug and say "adding loop";
	my $fan_out = $g->successors($a);
	$debug and say "$a: fan_out $fan_out";
	my $fan_in  = $g->predecessors($b);
	$debug and say "$b: fan_in $fan_in";
	if ($fan_out > 1){
		add_near_side_loop($g,$a,$b, out_loop($a))
	} elsif ($fan_in  > 1){
		add_far_side_loop($g,$a,$b, in_loop($b))
	} elsif ($fan_in == 1 and $fan_out == 1){

	# we expect a single user track to feed to Master_in 
	# as multiple user tracks do
	
			$b eq 'Master' 
				?  add_far_side_loop($g,$a,$b,in_loop($b))

	# otherwise default to near_side ( *_out ) loops
				: add_near_side_loop($g,$a,$b,out_loop($a));

	} else {croak "unexpected fan"};
}

 sub add_near_side_loop {

# a - b
# a - c
# a - d
#
# converts to 
#
# a_out - b
# a_out - c
# a_out - d
# a - a_out

# we deal with all edges departing from $a, the left node.
# I call it a-x below, but it is actually a-$_ where $_ 
# is an alias to each of the successor node.
#
# 1. start with a - x
# 
# 2. delete a - x 
# 
# 3. add a - a_out
# 
# 4. add a_out - x
# 
# 5. Add a_out attributes for track name and 
#    other info need to generate correct chain_ids
#
# 6. Copy any attributes of edge a - x  to a_out - x.
#
#  No multiedge handling needed because with our 
#  current topology, we never have a track
#  with, for example, multiple edges to a soundcard.
#
#  Send buses create new tracks to provide connections.
#
# I will be moving edges (along with their attributes)
# but I cannot assign chain_id them because I have
# no way of knowing which is the edge that will use
# the track number and will therefore get the track effects

 	my ($g, $a, $b, $loop) = @_;
 	$debug and say "$a-$b: insert near side loop";
	# we will insert loop _after_ processing successor
	# edges so $a-$loop will not be picked up 
	# in successors list.
	
	# We will assign chain_ids to loop-to-loop edges
	# looking like J7a, J7b,...
	#
	# To make this possible, we store the following 
	# information in the left vertex of
	# the edge:
	#
	# n: track index, j: alphabetical counter
	 
	$g->set_vertex_attributes($loop,{
		n => $::tn{$a}->n, j => 'a',
		track => $::tn{$a}->name});
	map{ 
 		my $attr = $g->get_edge_attributes($a,$_);
 		$debug and say "deleting edge: $a-$_";
 		$g->delete_edge($a,$_);
		add_edge($loop, $_);
		$g->set_edge_attributes($loop,$_, $attr) if $attr;
		$seen{"$a-$_"}++;
 	} $g->successors($a);
	add_edge($a,$loop);
}
 

sub add_far_side_loop {
 	my ($g, $a, $b, $loop) = @_;
 	$debug and say "$a-$b: insert far side loop";
	
	$g->set_vertex_attributes($loop,{
		n => $::tn{$a}->n, j => 'a',
		track => $::tn{$a}->name});
	map{ 
 		my $attr = $g->get_edge_attributes($_,$b);
 		$debug and say "deleting edge: $_-$b";
 		$g->delete_edge($_,$b);
		add_edge($_,$loop);
		$g->set_edge_attributes($_,$loop, $attr) if $attr;
		$seen{"$_-$b"}++;
 	} $g->predecessors($b);
	add_edge($loop,$b);
}


sub in_loop{ "$_[0]_in" }
sub out_loop{ "$_[0]_out" }
sub is_a_track{ $::tn{$_[0]} }  # most reliable
# although it is unlikely that someone names a track sax_in
#sub graph_tracks { my $g = shift; grep{is_a_track($_)} $g->vertices }
# c.f. %is_ecasound_chain for same data (
#sub is_a_track{ return unless $_[0] !~ /_(in|out)$/;}
# $debug and say "$_[0] is a track"; 1
#}
sub is_terminal { $reserved{$_[0]} }
sub is_a_loop{
	my $name = shift;
	return if $reserved{$name};
	if (my($root, $suffix) = $name =~ /^(.+?)_(in|out|insert_p.+)$/){
		return ($root, $suffix);
	} 
}
sub is_a_jumper { 		! is_terminal($_[0])
				 	and ! is_a_track($_[0]) 
					and ! is_a_loop($_[0]) }
	

sub inputless_tracks {
	my $g = shift;
	(grep{ is_a_track($_) and $g->is_source_vertex($_) } $g->vertices)
}	
sub remove_out_of_bounds_tracks {
	my $g = shift;
	my @names = $g->successors('wav_in');  # MON status tracks
	map{ remove_tracks($g, $_) } 
	grep{
		::set_edit_vars($::tn{$_});
		::edit_case() =~ /out_of_bounds/
	} @names;
}

sub recursively_remove_inputless_tracks {
	my $g = shift;
	# make multiple passes if necessary
	while(my @i = ::Graph::inputless_tracks($g)){
		remove_tracks($g, @i);
	}
}
sub outputless_tracks {
	my $g = shift;
	(grep{ is_a_track($_) and $g->is_sink_vertex($_) } $g->vertices)
}	
sub recursively_remove_outputless_tracks {
	my $g = shift;
	while(my @i = ::Graph::outputless_tracks($g)){
		remove_tracks($g, @i);
	}
}
sub remove_tracks {
	my ($g, @names) = @_;
		map{ 	$g->delete_edges(map{@$_} $g->edges_from($_));
				$g->delete_edges(map{@$_} $g->edges_to($_));
				$g->delete_vertex($_);
		} @names;
}
		
1;
__END__

The graphic routing system is complicated enough that some comment is
warranted.

The first step of routing is to create a graph that expresses the signal flow.

	soundcard_in -> sax -> Master -> soundcard_out

If we are to record the input, we need:

	sax -> wav_out

If we add an instrument monitor on a separate channel for the sax player, we need:

	sax -> soundcard_out

Ecasound requires that we insert loop devices wherever the signals
must fan out or fan in.

	soundcard_in -> sax -> sax_out -> Master -> soundcard_out

	                       sax_out -> wav_out

	                       sax_out -> soundcard_out

Here 'sax_out' is a loop device.

All routing functions follow these rules.

We then process each edge to generate a line for the Ecasound chain setup
file.

Master -> soundcard_out is easy to process, because the track
Master knows what it's outputs should be.

The edge sax_out -> soundcard_out, an auxiliary send, needs to know its
associated track, the chain_id (identifier for the Ecasound
chain corresponding to this edge) and in the final step
the soundcard channel number.

We can provide this information as edge attributes.

We also allow vertexes, for example a track or loop device, to carry data is
well, for example to tell the dispatcher to override the 
chain_id of a temporary track.

An Ecasound chain setup is a graph comprised of multiple 
signal processing chains, each of which consists 
of exactly one input and one output.
 
The dispatch process transforms the graph edges into a group of 
IO objects, each with enough information to create
the input or output fragment of a chain.

Finally, these objects are processed into the Ecasound
chain setup file. 
