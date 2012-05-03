{
package ::Insert;
use Modern::Perl;
use Carp;
no warnings qw(uninitialized redefine);
our $VERSION = 0.1;
our ($debug);
local $debug = 0;
use vars qw(%by_index);
use ::Globals qw($jack $setup $config);
use ::Object qw(
	insert_type
	n
	class
	send_type
	send_id
	return_type
	return_id
	wet_track
	dry_track
	tracks
	track
	wetness
	wet_vol
	dry_vol
);
use ::Util qw(input_node output_node dest_type);
# tracks: deprecated

initialize();

sub initialize { %by_index = () }

sub idx { # return first free index
	my $n = 0;
	while (++$n){
		return $n if not $by_index{$n}
	}
}

sub wet_name {
	my $self = shift;
	# use the field if available for backward compatibility (pre 1.054)
	$self->{wet_name} || join('-', $self->track, $self->n, 'wet'); 
}
sub dry_name {
	my $self = shift;
	# use the field if available for backward compatibility (pre 1.054)
	$self->{dry_name} || join('-', $self->track, $self->n, 'dry'); 
}
sub new {
	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	$vals{n} ||= idx(); 
	my $self = bless { 
					class	=> $class, 	# for restore
					wetness		=> 100,
					%vals,
								}, $class;
	my $name = $vals{track};
	my $wet = ::SlaveTrack->new( 
				name => $self->wet_name,
				target => $name,
				group => 'Insert',
				rw => 'REC',
	
				# don't hide wet track if used for hosting effects
				
				hide => ! $self->is_local_effects_host,
			);
	my $dry = ::SlaveTrack->new( 
				name => $self->dry_name,
				target => $name,
				group => 'Insert',
				hide => 1,
				rw => 'REC');
	map{ ::remove_effect($_)} $wet->vol, $wet->pan, $dry->vol, $dry->pan;

	$self->{dry_vol} = ::add_effect({
		track  => $dry, 
		type   => 'ea',
		values => [0]
	});
	$self->{wet_vol} = ::add_effect({
		track  => $wet, 
		type   => 'ea',
		values => [100],
	});
	$by_index{$self->n} = $self;
}

# method name for track field holding insert

sub type { (ref $_[0]) =~ /Pre/ ? 'prefader_insert' : 'postfader_insert' }

sub remove {
	my $self = shift;
	local $::this_track;
	$::tn{ $self->wet_name }->remove;
	$::tn{ $self->dry_name }->remove;
	delete $by_index{$self->n};
}
# subroutine
#
sub add_insert {
	my ($type, $send_id, $return_id) = @_;
	# $type : prefader_insert | postfader_insert
	say "\n",$::this_track->name , ": adding $type\n";
	local $::this_track = $::this_track; # temporarily change
	my $t = $::this_track;
	my $name = $t->name;

	# the input fields will be ignored, since the track will get input
	# via the loop device track_insert
	
	my $class =  $type =~ /pre/ ? '::PreFaderInsert' : '::PostFaderInsert';
	
	# remove an existing insert of specified type, if present
	$t->$type and $by_index{$t->$type}->remove;

	my $i = $class->new( 
		track => $t->name,
		send_type 	=> ::dest_type($send_id),
		send_id	  	=> $send_id,
		return_type 	=> ::dest_type($return_id),
		return_id	=> $return_id,
	);
	if (! $i->{return_id}){
		$i->{return_type} = $i->{send_type};
		$i->{return_id} =  $i->{send_id} if $i->{return_type} eq 'jack_client';
		$i->{return_id} =  $i->{send_id} + 2 if $i->{return_type} eq 'soundcard';
	}
}
sub get_id {
	# get Insert index for track
	
	# optionally specify whether we are looking for
	# prefader or postfader insert
	
	# 
	my ($track, $prepost) = @_;
	my @inserts = grep{ $track->name eq $_->track} values %by_index;
	my ($prefader) = (map{$_->n} 
					grep{$_->class =~ /pre/i} 
					@inserts);
	my ($postfader) = (map{$_->n} 
					grep{$_->class =~ /post/i} 
					@inserts);
	my %id = ( pre => $prefader, post => $postfader);
	$prepost = $id{pre} ? 'pre' : 'post'
		if (! $prepost and ! $id{pre} != ! $id{post} );
	$id{$prepost};;
}

sub is_local_effects_host { ! $_[0]->send_id }


### Insert Latency calculation
#    
#    In brief, the maximum latency for the two arms is the
#    latency of any effects on the wet track plus the additional
#    latency of the JACK client and JACK connection. (We
#    assume send/receive from the same client.)
#    
#    Here is the long explanation:
#    
#    We need to calculate and compensate the latency
#    of the two arms of the insert.
#    
#    $setup->{sibling_latency} is the maximum latency value
#    measured among a group of parallel tracks (i.e.
#    bus members).
#    
#    For example, Low, Mid and High tracks for mastering
#    are siblings. When we get the maximum for the
#    group, we set $setup->{sibling_latency}->{track_name} = $max
#    
#    $setup->{track_latency}->{track_name} is the latency
#    calculated for a track (including predecessor tracks when
#    that is significant.)
#    
#    So later on, when we get to adjusting latency, the
#    amount is given by
#    
#    $setup->{sibling_latency}->{track_name} - $setup->{track_latency}->{track_name}
#    
sub latency { 

	my $self = shift;
	my $jack_related_latency = 0;

	# get the latency associated with the JACK client, if any
	if($self->send_type eq "jack_client")
	{

		my $client_latency_frames = 
			$jack->{clients}->{$_->send_name}->{playback}->{max} 
				+ $jack->{clients}->{$_->send_name}->{capture}->{max};
		my $jack_connection_latency_frames = $jack->{period}; 
		
		$jack_related_latency =
			($client_latency_frames + $jack_connection_latency_frames) 
			/$config->{sample_rate}
			* 1000;
	}
	

	# set the track and sibling(i.e. max) latency values
	# for wet and dry arms (tracks)
	
	# assuming no latency-causing effects on the dry arm
	$setup->{track_latency}->{$_->dry_name} = 0;
	
	# checking the dry arm  TODO
	
	#$setup->{track_latency}->{$_->dry_name} = 
	#	track_ops_latency($::tn{$_->dry_name})
	#	+ insert_latency($::tn{$_->dry_name});

	# sibling latency (i.e. max), is same as wet track latency
	
	my $latency = $setup->{sibling_latency}->{$_->wet_name}
				= $setup->{sibling_latency}->{$_->dry_name} 
				= $setup->{track_latency}->{$_->wet_name} 
				= track_ops_latency($::tn{$_->wet_name}) + $jack_related_latency
		# + insert_latency($::tn{$_->wet_name}) # for inserts within inserts
		;

	# increment insert latency by one additional loop device
	
	$latency += ::loop_device_latency(); 
}
}
{
package ::PostFaderInsert;
use Modern::Perl; use Carp; our @ISA = qw(::Insert); our $debug;
use ::Util qw(input_node output_node dest_type);
sub add_paths {

	# Since this routine will be called after expand_graph, 
	# we can be sure that every track vertex will connect to 
	# to a single edge, either loop or an output 
	
	my ($self, $g, $name) = @_;
	no warnings qw(uninitialized);
	#my $debug = 1;
	$debug and say "add_insert for track: $name";

	my $t = $::tn{$name}; 


	$debug and say "insert structure:", $self->dump;

	my ($successor) = $g->successors($name);

	# successor will be either a loop, device or JACK port
	# i.e. can accept multiple signals

	$g->delete_edge($name, $successor);
	my $loop = "$name\_insert_post";
	my $wet = $::tn{$self->wet_name};
	my $dry = $::tn{$self->dry_name};

	$debug and say "found wet: ", $wet->name, " dry: ",$dry->name;

	# if no insert target, our insert will 
	# a parallel effects host with wet/dry dry branches
	
	# --- track ---insert_post--+--- wet ---+-- successor 
	#                           |           |
	#                           +--- dry ---+

	# otherwise a conventional wet path with send and receive arms
	
	# --- track ---insert_post--+-- wet-send    wet-return ---+-- successor
	#                           |                             |
	#                           +-------------- dry ----------+
	
	if ( $self->is_local_effects_host )
	{
		$g->add_path($name, $loop, $wet->name, $successor);

	}
	else

	{	
		# wet send path (no extra track): track -> loop -> output

		my @edge = ($loop, output_node($self->{send_type}));
		$debug and say "edge: @edge";
		$g->add_path( $name, @edge);
		$g->set_vertex_attributes($loop, {n => $t->n});
		$g->set_edge_attributes(@edge, { 
			send_id => $self->{send_id},
			width => 2,
		});
		# wet return path: input -> wet_track (slave) -> successor
		
		# we override the input with the insert's return source

		$g->set_vertex_attributes($wet->name, {
					width => 2, # default for cooked
					mono_to_stereo => '', # override
					source_type => $self->{return_type},
					source_id => $self->{return_id},
		});
		$g->add_path(input_node($self->{return_type}), $wet->name, $successor);

	}

	# connect dry track to graph
	
	$g->add_path($loop, $dry->name, $successor);
	}
	
}
{
package ::PreFaderInsert;
use Modern::Perl; use Carp; our @ISA = qw(::Insert); our $debug;
use ::Util qw(input_node output_node dest_type);
sub add_paths {

# --- predecessor --+-- wet-send    wet-return ---+-- insert_pre -- track
#                   |                             |
#                   +-------------- dry ----------+
           

	my ($self, $g, $name) = @_;
	no warnings qw(uninitialized);
	#my $debug = 1;
	$debug and say "add_insert for track: $name";

	my $t = $::tn{$name}; 


	$debug and say "insert structure:", $self->dump;

		my ($predecessor) = $g->predecessors($name);
		$g->delete_edge($predecessor, $name);
		my $loop = "$name\_insert_pre";
		my $wet = $::tn{$self->wet_name};
		my $dry = $::tn{$self->dry_name};

		$debug and say "found wet: ", $wet->name, " dry: ",$dry->name;


		#pre:  wet send path (no track): predecessor -> output

		my @edge = ($predecessor, output_node($self->{send_type}));
		$debug and say "edge: @edge";
		$g->add_path(@edge);
		$g->set_edge_attributes(@edge, { 
			send_id => $self->{send_id},
			send_type => $self->{send_type},
			mono_to_stereo => '', # override
			width => $t->width,
			track => $name,
			n => $t->n,
		});

		#pre:  wet return path: input -> wet_track (slave) -> loop

		
		# we override the input with the insert's return source

		$g->set_vertex_attributes($wet->name, {
				width => $t->width, 
				mono_to_stereo => '', # override
				source_type => $self->{return_type},
				source_id => $self->{return_id},
		});
		$g->set_vertex_attributes($dry->name, {
				mono_to_stereo => '', # override
		});
		$g->add_path(input_node($self->{return_type}), $wet->name, $loop);

		# connect dry track to graph
		#
		# post: dry path: loop -> dry -> successor
		# pre: dry path:  predecessor -> dry -> loop
		
		$g->add_path($predecessor, $dry->name, $loop, $name);
	}
	
}
1;
