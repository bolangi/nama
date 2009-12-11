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
			add_near_side_loop($g,$a,$b);}
	
		# case 3: fan in to track: use far side loop
		
		elsif ( is_a_track($b) and $g->predecessors($b) > 1 ) {
			$debug and say "fan in to track $b";
			add_far_side_loop($g,$a,$b);}
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
	my @track_names = grep{ $::tn{$_} 
		and $::tn{$_}->inserts =~ /HASH/
		and $::tn{$_}->inserts->{insert_type}} $g->vertices;
	$debug and say "Inserts will be applied to the following tracks: @track_names";
	map{ add_insert($g, $_) } @track_names;
}
	
sub add_insert {

	# this routine will be called after expand_graph, so that
	# every track will connect to either loop or source/sink
	no warnings qw(uninitialized);

	my ($g, $name) = @_;
	$debug and say "add_insert name: $name";
	my $t = $::tn{$name}; 
	my $i = $t->inserts; 

	# assume post-fader send
	# t's successor will be loop or reserved

	# case 1: post-fader insert
		
	if($i->{insert_type} eq 'cooked') {	 # the only type we support
	
	my ($successor) = $g->successors($name);
	my $loop = $name."_insert";
	my ($dry) = add_near_side_loop( $g, $name, $successor, $loop);
	$dry->set(group => 'Insert');

	$dry->set( hide => 1);
	my $wet = ::Track->new( 
				name => $dry->name . 'w',
				group => 'Insert',
				width => 2, # default for cooked
 				send_type => $i->{send_type},
 				send_id => $i->{send_id},
				hide => 1,
				rw => 'REC',
	
				);


	# connect wet track to graph
	
	add_path($loop, $wet->name, $i->{send_type}."_out");

	# add return leg for wet signal
	
	my $wet_return = ::Track->new( 

				name => $dry->name . 'wr',
				group => 'Insert',
				width => 2, # default for cooked
 				source_type => $i->{return_type},
 				source_id => $i->{return_id},
				rw => 'REC',
				hide => 1,
			);
	$i->{dry_vol} = $dry->vol;
	$i->{wet_vol} = $wet_return->vol;
	
	::command_process($t->name);
	::command_process('wet',$i->{wetness});


	$i->{tracks} = [ map{ $_->name } ($wet, $wet_return, $dry) ];
	
	add_path($i->{return_type}.'_in',  $dry->name.'wr', $successor);


	}
	
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
# a - a_out
# a_out - b
# a_out - c
# a_out - d

# if b is a track, b provides the chain_id
#
# if b is a non-track, we need to use an anonymous track
# providing a chain_id to make the connection, or we
# need to make a edge with it's own chain_id and a 
# reference to the track snapshot. 
#
# that is the new method.
#
# (comment: why do we need a track snapshot? why can't we
# just copy the attributes from the track itself? I think
# because we need to override, and accomplish this by 
# appending key-value pairs to a hash)

# we deal with all edges departing from $a, the left node.
# I call it a-x below, but it is actually a-$_ where $_ 
# is an alias to each of the successor node.
#
# The old way, using a temporary SlaveTrack
# 
# 1. start with a - x
# 
# 2. delete a - x 
# 
# 3. add a - a_out
# 
# 4. x is track: add a_out - x
# 
# 5. x is non - track: add a_out - slave_track - x
# 
# The new way, using edge attributes
# 
# 1,2,3,4. as above
# 
# 5. x is non-track: add a_out-x with attributes
# 	track => a_track_snapshot, chain_id => J<n><a>
# 	where <n> is the track index, and <a> is an 
# 	alphabetical incrementing counter.
#
#   No auto increment (here), 
#   a) because we allow ONE aux send and ONE insert per track
#   b) because we set the chain_id (however determined)
#      in, for example, the add_paths_for_aux_sends()
#      so we can consider that problem solved here.
#
#  Conclusion: create the new edge and copy the edge attribute if any
#
#  Edges are still unique (no multiedge handling needed) because:
#  If tracks are feeding a bus or Master, with an aux-send to Soundcard,
#  that is only one edge to Soundcard. Send buses create new tracks,
#  so their output edges to soundcard, etc. will all
#  have unique names.

# I will be moving edges (along with their attributes)
# but I cannot assign chain_id them because I have
# no way of knowing which is the edge that will use
# the track number and will therefore get the track effects

 	my ($g, $a, $b, $loop) = @_;
 	$debug and say "$a-$b: insert near side loop";
	# we will insert loop _after_ processing successor
	# edges so $a-$loop will not be picked up 
	# in successors list.
	
	# for later assigning chain_id to loop-loop chain
	# will take forms like J7a, J7b,...
	# n: track index, j: alphabetical counter
	$g->set_vertex_attributes($loop,{n => $::tn{$a}->n, j => 'a'});
	map{ 
 		my $attr = $g->get_edge_attributes($a,$_);
 		$debug and say "deleting edge: $a-$_";
 		$g->delete_edge($a,$_);
 		$debug and say "adding edge: $loop-$_";
		$g->add_edge($loop, $_);
		$g->set_edge_attributes($loop,$_, $attr) if $attr;
		$seen{"$a-$_"}++;
 	} $g->successors($a);
	$debug and say "adding edge: $a-$loop";
	$g->add_edge($a,$loop);
}
 

sub add_far_side_loop {
 	my ($g, $a, $b, $loop) = @_;
 	$debug and say "$a-$b: insert far side loop";
	# we will insert loop _after_ processing predecessors
	# edges so $loop-$b  will not be picked up 
	# in predecessors list.
	
	map{ 
 		my $attr = $g->get_edge_attributes($_,$b);
 		$debug and say "deleting edge: $_-$b";
 		$g->delete_edge($_,$b);
 		$debug and say "adding edge: $_-$loop";
		$g->add_edge($_,$loop);
		$g->set_edge_attributes($_,$loop, $attr) if $attr;
		$seen{"$_-$b"}++;
 	} $g->predecessors($b);
	$debug and say "adding edge: $loop-$b";
	$g->add_edge($loop,$b);
}


sub in_loop{ "$_[0]_in" }
sub out_loop{ "$_[0]_out" }
sub is_a_track{ $::tn{$_[0]} }
#sub is_a_track{ return unless $_[0] !~ /_(in|out)$/;
# $debug and say "$_[0] is a track"; 1
#}
sub is_terminal { $reserved{$_[0]} }
sub is_a_loop{
	my $name = shift;
	return if $reserved{$name};
	if (my($root, $suffix) = $name =~ /^(.+?)_(in|out)$/){
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
sub remove_inputless_tracks {
	my $g = shift;
	while(my @i = ::Graph::inputless_tracks($g)){
		map{ 	$g->delete_edges(map{@$_} $g->edges_from($_));
				$g->delete_vertex($_);
		} @i;
	}
}
sub outputless_tracks {
	my $g = shift;
	(grep{ is_a_track($_) and $g->is_sink_vertex($_) } $g->vertices)
}	
sub remove_outputless_tracks {
	my $g = shift;
	while(my @i = ::Graph::outputless_tracks($g)){
		map{ 	$g->delete_edges(map{@$_} $g->edges_to($_));
				$g->delete_vertex($_);
		} @i;
	}
}
		
1;
