package ::Graph;
use Modern::Perl;
use Carp;
use Graph;
use vars qw(%seen %reserved $debug);

%reserved = map{ $_, 1} qw( soundcard_in soundcard_out wav_in wav_out jack_in jack_out );
$debug = 1;
=comment
my %seen;
my $g = Graph->new;
my $debug = 1;
$g->add_path(qw[ wav_in piano Master Eq Low Boost soundcard_out]) ;
$g->add_path(qw[ Eq High Boost]);
$g->add_path(qw[ Eq Low Boost]);

say "The initial graph is  $g";

expand_graph($g);

say "The expanded graph is $g";
=cut

sub expand_graph {
	my $g = shift; 
	%seen = ();
	map{ my($a,$b) = @{$_}; 
		$debug and say "reviewing edge: $a-$b";
		$debug and say "$a-$b: already seen" if $seen{"$a-$b"};
		 add_loop($g,$a,$b) if is_a_track($a) and is_a_track($b);
	} $g->edges;
}

sub add_loop {
	my ($g,$a,$b) = @_;
	$debug and say "adding loop";
	my $fan_out = $g->successors($a);
	$debug and say "$a: fan_out $fan_out";
	my $fan_in  = $g->predecessors($b);
	$debug and say "$b: fan_in $fan_in";
	if ($fan_out > 1){
		insert_near_side_loop($g,$a,$b)
	} elsif ($fan_in  > 1){
		insert_far_side_loop($g,$a,$b)
	} elsif ($fan_in ==1 and $fan_out == 1){
			$b eq 'Master' 
				?  insert_far_side_loop($g,$a,$b)
				:  insert_near_side_loop($g,$a,$b);
	} else {croak "unexpected fan"};
}

sub insert_near_side_loop {
	my ($g, $a, $b) = @_;
	$debug and say "$a-$b: insert near side loop";
	$debug and say("$a-$b: already visited"), return if $seen{"$a-$b"};
	map{
	$debug and say "deleting edge: $a-$_";
	$g->delete_edge($a,$_);
	$debug and say "adding path: $a " , out_loop($a), " $_";
	$g->add_path($a,out_loop($a),$_);
	$seen{"$a-$_"}++
	} $g->successors($a);
}

sub insert_far_side_loop {
	my ($g, $a, $b) = @_;
	$debug and say "$a-$b: insert far side loop";
	$debug and say("$a-$b: already visited"), return if $seen{"$a-$b"};
	map{
		$debug and say "deleting edge: $_-$b";
		$g->delete_edge($_,$b);
		$debug and say "adding path: $_ " , in_loop($b), " $b";
		$g->add_path($_,in_loop($b),$b);
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
