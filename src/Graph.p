package ::Graph;
use Modern::Perl;
use Carp;
use Graph;
use vars qw(%reserved);
%reserved = map{ $_, 1} qw( soundcard_in soundcard_out wav_in wav_out jack_in jack_out null_in null_out);
my $debug = 0;
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
	my @track_names = grep{ $::tn{$_} and @{$::tn{$_}->inserts}} $g->vertices;
	map{ add_insert($g, $_) } @track_names;
}
	
sub add_insert {
	my ($g, $name) = @_;
	my $t = $::tn{$name}; 
	my @inserts = @{ $t->inserts };
	my %i = %{ pop @inserts }; # assume just one, copy

	# default to return via same system (soundcard or JACK)
	$i{return_type} //= $i{send_type};

	# default to return from same JACK client or adjacent soundcard channels
	$i{return_id}  //= $i{return_type} eq 'jack_client' 
			? $i{send_id} 
			: ( $i{insert_type} eq 'cooked' ? 2 : $i{send_id} + $t->ch_count);
	
	# assume post-fader send
	# t's successor will be loop or reserved
	
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
	$debug and say "$a-$b: insert near side loop";
	my $j = 'a';
	map{
		$debug and say "deleting edge: $a-$_";
		#my $attr = $g->get_edge_attributes($a,$_);

		# insert loop in every case
		$g->delete_edge($a,$_);
		#$debug and say "adding path: $a " , $loop, " $_";
		$g->add_edge($a,$loop);

		# add second arm if successor is track
		if ( $::tn{$_} ){ $g->add_edge($loop, $_) }

		# insert anon track if successor is non-track
		else {  

			my $n = $::tn{$b}->n . $j++;
			my $anon = ::AnonSlaveTrack->new( 
				target => $a,
				name => $n);
			push @$tracks_ref, $anon;

			$g->add_path($loop,$anon->name,$_);
		}

		#$g->set_edge_attributes($loop,$_,$attr) if ref $attr;
		#my $att = $g->get_edge_attributes($loop,$_);
		#say ::yaml_out($att) if ref $att;
		$seen{"$a-$_"}++
	} $g->successors($a);
}

sub insert_far_side_loop {
	my ($g, $a, $b, $loop, $tracks_ref) = @_;
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

			my $n = $::tn{$b}->n . $j++;
			my $anon = ::AnonSlaveTrack->new( 
				target => $b,
				n => $n,
				name => $n);
			push @$tracks_ref, $anon;

			$g->add_path($_, $anon->name, $loop);
		}

		$seen{"$_-$b"}++
	} $g->predecessors($b);
}


sub in_loop{ "$_[0]_in" }
sub out_loop{ "$_[0]_out" }
#sub is_a_track{ $tn{$_[0]} }
sub is_a_track{ return unless $_[0] !~ /_(in|out)$/;
	$debug and say "$_[0] is a track"; 1
}
	
sub is_terminal { $reserved{$_[0]} }
sub is_a_loop{
	my $name = shift;
	return if $reserved{$name};
	if (my($root, $suffix) = $name =~ /(.+)(_(in|out))/){
		return $root;
	} 
}
1;
