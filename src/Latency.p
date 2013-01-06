# ----------- Latency Compensation -----------

package ::;
use Modern::Perl;
no warnings 'uninitialized';
use ::Globals qw(:all);
use List::Util qw(max);
use Carp qw(confess);

###### 
#
#   remove (or reset) latency operators
#   generate and connect setup
#   determine latency
#   add (or set) operators 
#    (to optimize: add operators only to plural sibling edges, not only edges)

sub set_latency_compensation {
	
	my $track = shift;
	my $delay = shift || 0;
	my $units = shift;

	my $id = $track->latency_op || add_latency_compensation_op ( $track );

	# execute coderef to modify effect, adjusting for units
	# assume frames by default
	
	$config->{latency_op_set}->( $id, 
								$units =~ /^s/i ? $delay : frames_to_secs($delay));
	$id;
}
sub add_latency_compensation_op {

	# add the effect, and set the track's latency_op field
	
	my $track = shift;
	my @args = @_;
	@args = (2,0) unless scalar @args;

	my $id = $track->latency_op;

	# create a delay effect if necessary, place before first effect
	# if it exists
	
	if (! $id){	
		my $first_effect = $track->ops->[0];
		$id = add_effect({
				before 	=> $first_effect, 
				track	=> $track,
				type	=> $config->{latency_op}, 
				values	=> \@args,
		});
		# sometimes after passing default args,
		# we see delay parameter of 9e-6 so
		# set to zero unless caller provided args 

		modify_effect($id, 2, undef, 0) unless @_;

		$track->set(latency_op => $id);
	}
	$id
}
sub calculate_and_adjust_latency {
	initialize_latency_vars();
	calculate_latency();
	adjust_latency();
}

sub calculate_latency {
	my $starting_track_name = $mode->{mastering} ?  'Boost' : 'Master'; 
	push my(@first_siblings), $starting_track_name;
	push @first_siblings, 'Mixdown' if $tn{Mixdown}->rec_status eq 'MON';
	logpkg('debug',"starting nodes: @first_siblings");
	sibling_latency(@first_siblings);
}
sub adjust_latency {
	eval_iam('cs-disconnect');

	for ( ::ChainSetup::engine_tracks() )
	{ 	
		next unless has_siblings($_) and $_->latency_offset;

		set_latency_compensation($_, $_->latency_offset);

		# store offset for debugging
		$setup->{latency}->{track}->{$_->name}->{offset} = $_->latency_offset; 

  	}
	connect_transport('quiet');
}
sub cl2 {

	initialize_latency_vars();
=comment
	get predecessors of all output types (wav_out, etc)
	sibling latency groups from soundcard_out 
	start with same as currently (Master/Boost and Mixdown)


	each item

	set own latency

	is loop device # set own latency
	is track	   # set own latency
	is output
	is input 

	get predecessors of all output types (wav_out, etc)
	set outputs

	propagate latency
	propagate again 
	

	#walk($coderef_set_own_latency)
	
=cut



}

sub reset_latency_compensation {
 	map{ set_latency_compensation($_, 0) } grep{ $_->latency_op } ::Track::all();
 }
sub has_siblings { 
	my $count = $setup->{latency}->{sibling_count}->{$_[0]->name};
	#say "track: ",$_[0]->name, " siblings: $count";
	$setup->{latency}->{sibling_count}->{$_[0]->name} > 1 
}

sub initialize_latency_vars {
	$setup->{latency} = {};
	$setup->{latency}->{track} = {};
	$setup->{latency}->{sibling} = {};
	$setup->{latency}->{sibling_count} = {};
}

sub track_latency {
	my $track = shift;

	# initialize
	my $node = $setup->{latency}->{track}->{$track->name} = {};
	my $accumulator = 0;

	### track effects latency
	
	$accumulator += ($node->{ops} = track_ops_latency($track));

	### track insert latency
	
	$accumulator += ($node->{insert} = insert_latency($track));

	### track's own latency
	
	$node->{own} = $accumulator;

	### track predecessor latency (if has tracks as predecessors)

	my $pl = predecessor_latency($track);

	$accumulator += ($node->{predecessor} = $pl); # zero if no predecessors

	$pl or $accumulator += ($node->{capture}     = $track->capture_latency );

	### track source latency (if track has "live" i.e.  non-WAV input)

	### track total latency

	$node->{total} = $accumulator;

}
sub track_ops_latency {
	# LADSPA plugins return latency in frames
	my $track = shift;
	my $total = 0;;
	map { $total += op_latency($_) } $track->fancy_ops;
	$total
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
		or ::pager3("$name: non existing JACK client"),
		return;
	$node->{$port}->{latency}->{$direction}->{min}
		ne $node->{$port}->{latency}->{$direction}->{max}
	and ::pager3('encountered unmatched latencies', 
		sub{ json_out($node) });
	$node->{$port}->{latency}->{$direction}->{min}
}
}
sub insert_latency {
	my $track = shift;
	my $latency = 0;
	map{ $latency += $_->latency} ::Insert::get_inserts($track->name);
	$latency;
}
sub predecessor_latency {
	my $track = shift;
	my @predecessors 
		= grep{ ::Graph::is_a_track($_) } 
			$setup->{latency_graph}->predecessors($track->name);
	scalar @predecessors or return 0;
	#say "track: ",$track->name;
	sibling_latency(@predecessors) + loop_device_latency();
}
sub sibling_latency {
	my @siblings = grep{ ::Graph::is_a_track($_) } @_; 
	my $node = $setup->{latency}->{sibling};
	#say join " ", "siblings:", @siblings;
	scalar @siblings or return 0;
	my $max = max map { track_latency($_) } map{$tn{$_}} @siblings;
	map { $node->{$_} = $max } @siblings;
	my $node2 = $setup->{latency}->{sibling_count};
	map { $node2->{$_} = scalar @siblings } @siblings;
	return $max
}
sub loop_device_latency { 
	# results in frames
	$engine->{buffersize}; 
}

sub op_latency {
	my $op = shift;
	return 0 if is_controller($op); # skip controllers
	my $p = latency_param($op);
	defined $p and ! bypassed($op)
		? get_live_param($op, $p) 
		: 0
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
	my $n = chain($op);
	my $i = ecasound_effect_index($op);
	eval_iam("c-select $n");
	eval_iam("cop-select $i");
	eval_iam("copp-select $param");
	eval_iam("copp-get")
}

sub frames_to_secs { # One time conversion for delay op
	my $frames = shift;
	$frames / $config->{sample_rate};
}

1;
