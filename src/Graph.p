package ::Graph;
use Modern::Perl;
use Carp;
use Graph;
use vars qw(%reserved $debug);
# this dispatch table also identifies labels reserved
# for signal sources and sinks.
*reserved = \%::dispatch;
*debug = \$::debug;
my %seen;
my $anon_tracks;

sub expand_graph {
	$anon_tracks = [];
	my $g = shift; 
	%seen = ();
	
	# case 1: both nodes are tracks
	
	map{ my($a,$b) = @{$_}; 
		$debug and say "reviewing edge: $a-$b";
		$debug and say "$a-$b: already seen" if $seen{"$a-$b"};
		add_loop($g,$a,$b) unless $seen{"$a-$b"};
	} grep{my($a,$b) = @{$_}; is_a_track($a) and is_a_track($b);} 
	$g->edges;

	# case 2: fan out from (track) with one arm reaching soundard
	map{ 
		my($a,$b) = @{$_}; 
		is_a_track($a) or croak "$a: expected track." ;
		$debug and say "soundcard edge $a $b";
		insert_near_side_loop($g,$a,$b) 
	}
	grep{ my($a,$b) = @{$_};  
		$b eq 'soundcard_out' and $g->successors($a) > 1
	} $g->edges;
	
	$anon_tracks;
}

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
		
	if($i->{insert_type} eq 'cooked') {	
	
	my ($successor) = $g->successors($name);
	my $loop = $name."_insert";
	my ($dry) = insert_near_side_loop( $g, $name, $successor, $loop);
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
	
	$g->add_path($loop, $wet->name, $i->{send_type}."_out");

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
	
	$g->add_path($i->{return_type}.'_in',  $dry->name.'wr', $successor);


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
		insert_near_side_loop($g,$a,$b, out_loop($a), $anon_tracks)
	} elsif ($fan_in  > 1){
		insert_far_side_loop($g,$a,$b, in_loop($b), $anon_tracks)
	} elsif ($fan_in == 1 and $fan_out == 1){

	# we expect a single user track to feed to Master_in 
	# as multiple user tracks do
	
			$b eq 'Master' 
				?  insert_far_side_loop($g,$a,$b,in_loop($b), $anon_tracks)

	# otherwise default to near_side ( *_out ) loops
				: insert_near_side_loop($g,$a,$b,out_loop($a), $anon_tracks);

	} else {croak "unexpected fan"};
}

sub insert_near_side_loop {
	my ($g, $a, $b, $loop, $tracks_ref) = @_;
	$tracks_ref //= [];
	$debug and say "$a-$b: insert near side loop";
	my $j = 'a';
	map{
		$debug and say "deleting edge: $a-$_";

		# insert loop in every case
		$g->delete_edge($a,$_);
		#$debug and say "adding path: $a " , $loop, " $_";
		$g->add_edge($a,$loop);

		# add second arm if successor is track
		if ( $::tn{$_} ){ $g->add_edge($loop, $_) }

		# insert anon track if successor is non-track
		# ( when adding an insert, successor is always non-track )
		else {  
		$debug and say "successor $_ is non-track";

			my $nam = $::tn{$a}->n . $j++;
			my $anon = ::SlaveTrack->new( 
				target => $a,
				rw => 'REC',
				name => $nam);
			push @$tracks_ref, $anon;

			$g->add_path($loop,$anon->name,$_);
		}

		# move attributes to new edge
		#my $att = $g->get_edge_attributes($loop,$_);
		#$g->set_edge_attributes($loop,$_,$attr) if ref $attr;

		$seen{"$a-$_"}++
	} $g->successors($a);
	@$tracks_ref;
}

sub insert_far_side_loop {
	my ($g, $a, $b, $loop, $tracks_ref) = @_;
	$tracks_ref //= [];
	my $j = 'm';
	$debug and say "$a-$b: insert far side loop";
	map{
		$debug and say "deleting edge: $_-$b";
		$g->delete_edge($_,$b);

		# insert loop in every case
		$g->add_edge($loop,$b);

		# add second arm if predecessor is track
		if ( $::tn{$_} ){ $g->add_edge($_, $loop) }

		# insert anon track if successor is non-track
		else {  

			my $nam = $::tn{$b}->n . $j++;
			my $anon = ::SlaveTrack->new( 
				target => $b,
				name => $nam,
				rw => 'REC');
			push @$tracks_ref, $anon;

			$g->add_path($_, $anon->name, $loop);
		}

		$seen{"$_-$b"}++
	} $g->predecessors($b);
	@$tracks_ref;
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
