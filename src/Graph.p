package ::Graph;
use Modern::Perl;
use Carp;
use Graph;
use ::Util qw(input_node output_node);
use Log::Log4perl;
use ::Log qw(logsub);
use vars qw(%reserved);
# this dispatch table also identifies labels reserved
# for signal sources and sinks.
*reserved = \%::IO::io_class;

our $logger;

sub initialize_logger { $logger = Log::Log4perl->get_logger() }

sub add_path_for_rec {

	# connect input source to file 
	
	my($g,$track) = @_;

	logsub("&add_path_for_rec: track ".$track->name);
	# Track input from a WAV, JACK client, or soundcard
	# Record 'raw' signal
	#
	# Do *not* record signals if the source reports it is
	# a track, bus or loop

	if( $track->source_type !~ /track|bus|loop/ )
	{
		# create temporary track for rec_file chain

		# (it may be possible to avoid creating a 
		# temporary track by providing the data as 
		# graph edge attributes)

		$logger->debug("rec file link for ".$track->name);
		my $name = $track->name . '_rec_file';
		my $anon = ::SlaveTrack->new( 
			target => $track->name,
			rw => 'OFF',
			group => 'Temp',
			hide => 1,
			name => $name);

		# connect writepath: source --> temptrackname --> wav_out
		
		$g->add_path(input_node($track->source_type), $name, 'wav_out');


		$g->set_vertex_attributes($name, { 

			# set chain_id to R3 (if original track is 3) 

			chain_id => 'R'.$track->n,

			# do not perform mono-to-stereo copy,
			# (override IO class default)

			mono_to_stereo => '', 
		});

	} 
	elsif ($track->source_type =~ /bus|track/) 
	{

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

		my @edge = ($track->name, 'wav_out'); # cooked signal

		$g->add_path(@edge); 

		# set chain_id to R3 (if original track is 3) 

		$g->set_edge_attributes(@edge, { 
			chain_id => 'R'.$track->n,
		});
		
		# if this path is left unconnected, 
		# i.e. track gets no input		
		# it will be removed by prune_graph()
		
		# to record raw:
		
		# source_type: loop
		# source_id:   loop,track_name_in

		# but for WAV to contain content, 
		# we need to guarantee that track_name has
		# an input
	}
}
sub add_path_for_aux_send {
	my ($g, $track) = @_;
		logsub("&add_path_for_aux_send: track ".$track->name);
		# for track 'sax', send_type 'jack_client', create route as 
		# sax-jack_client_out
		my @edge = ($track->name, output_node($track->send_type));
		$g->add_edge(@edge);
		 my $attr = {	track => $track->name,
						chain_id => 'S'.$track->n,
					};
		# force stereo output width except for Master
		$attr->{width} = 2 unless $track->name eq 'Master';
	 	$g->set_edge_attributes( @edge, $attr);
}
{
my %seen;

sub expand_graph {
	
	my $g = shift; 
	%seen = ();
	
	
	for ($g->edges){
		my($a,$b) = @{$_}; 
		$logger->debug("$a-$b: processing...");
		$logger->debug("$a-$b: already seen") if $seen{"$a-$b"};
		next if $seen{"$a-$b"};

		# case 1: both nodes are tracks: default insertion logic
	
		if ( is_a_track($a) and is_a_track($b) ){ 
			$logger->debug("processing track-track edge: $a-$b");
			add_loop($g,$a,$b) } 

		# case 2: fan out from track: use near side loop

		elsif ( is_a_track($a) and $g->successors($a) > 1 ) {
			$logger->debug("fan_out from track $a");
			add_near_side_loop($g,$a,$b,out_loop($a));}
	
		# case 3: fan in to track: use far side loop
		
		elsif ( is_a_track($b) and $g->predecessors($b) > 1 ) {
			$logger->debug("fan in to track $b");
			add_far_side_loop($g,$a,$b,in_loop($b));}
		else { $logger->debug("$a-$b: no action taken") }
	}
	
}
	
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
	$logger->debug("adding loop");
	my $fan_out = $g->successors($a);
	$logger->debug("$a: fan_out $fan_out");
	my $fan_in  = $g->predecessors($b);
	$logger->debug("$b: fan_in $fan_in");
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
 	$logger->debug("$a-$b: insert near side loop");
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
 		$logger->debug("deleting edge: $a-$_");
 		$g->delete_edge($a,$_);
		$g->add_edge($loop, $_);
		$g->set_edge_attributes($loop,$_, $attr) if $attr;
		$seen{"$a-$_"}++;
 	} $g->successors($a);
	$g->add_edge($a,$loop);
}
 

sub add_far_side_loop {
 	my ($g, $a, $b, $loop) = @_;
 	$logger->debug("$a-$b: insert far side loop");
	
	$g->set_vertex_attributes($loop,{
		n => $::tn{$a}->n, j => 'a',
		track => $::tn{$a}->name});
	map{ 
 		my $attr = $g->get_edge_attributes($_,$b);
 		$logger->debug("deleting edge: $_-$b");
 		$g->delete_edge($_,$b);
		$g->add_edge($_,$loop);
		$g->set_edge_attributes($_,$loop, $attr) if $attr;
		$seen{"$_-$b"}++;
 	} $g->predecessors($b);
	$g->add_edge($loop,$b);
}

}

sub in_loop{ "$_[0]_in" }
sub out_loop{ "$_[0]_out" }
sub is_a_track{ $::tn{$_[0]} }  # most reliable
sub is_terminal { $reserved{$_[0]} or is_port($_[0]) }
sub is_port { $_[0] =~ /^[^:]+:[^:]+$/ }
sub is_a_loop{
	my $name = shift;
	return if $reserved{$name};
	if (my($root, $suffix) = $name =~ /^(.+?)_(in|out|insert_p.+)$/){
		return ($root, $suffix);
	} 
}
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
	while(my @i = inputless_tracks($g)){
		remove_tracks($g, @i);
	}
}
sub outputless_tracks {
	my $g = shift;
	(grep{ is_a_track($_) and $g->is_sink_vertex($_) } $g->vertices)
}	
sub recursively_remove_outputless_tracks {
	my $g = shift;
	while(my @i = outputless_tracks($g)){
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

