{
package ::Insert;
use Modern::Perl;
use Carp;
no warnings qw(uninitialized redefine);
our $VERSION = 0.1;
use vars qw(%by_index);
use ::Log qw(logpkg);
use ::Log qw(logpkg);
use ::Globals qw($jack $setup $config);
use ::Object qw(
[% qx( ./strip_comments ./insert_fields ) %]
);

use ::Util qw(input_node output_node dest_type);

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
	join('-', $self->track, $self->n, 'wet'); 
}
sub dry_name {
	my $self = shift;
	join('-', $self->track, $self->n, 'dry'); 
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

	# this is the wet return track
	
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
	map{ my $track = $_;  map{ delete $track->{$_} } qw(vol pan) } $wet, $dry;

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
	# synchronize effects with wetness setting
	$self->set_wetness($self->{wetness}); 
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
	my ($track, $type, $send_id, $return_id) = @_;
	local $::this_track;
	# $type : prefader_insert | postfader_insert
	say "\n",$track->name , ": adding $type\n";
	my $name = $track->name;

	# the input fields will be ignored, since the track will get input
	# via the loop device track_insert
	
	my $class =  $type =~ /pre/ ? '::PreFaderInsert' : '::PostFaderInsert';
	
	# remove an existing insert of specified type, if present
	$track->$type and $by_index{$track->$type}->remove;

	my $i = $class->new( 
		track => $track->name,
		send_type 	=> ::dest_type($send_id),
		send_id	  	=> $send_id,
		return_type 	=> ::dest_type($return_id),
		return_id	=> $return_id,
	);
	if (! $i->{return_id}){
		$i->{return_type} = $i->{send_type};
		$i->{return_id} =  $i->{send_id} if $i->{return_type} eq 'jack_client';
		$i->{return_id} =  $i->{send_id} + 2 if $i->{return_type} eq 'soundcard';
			# TODO adjust to suit track channel width?
	}
}
sub get_id {
	# get Insert index for track
	
	# optionally specify whether we are looking for
	# prefader or postfader insert
	
	# 
	my ($track, $prepost) = @_;
	my @inserts = get_inserts($track->name);
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
sub get_inserts {
	my $trackname = shift;
	grep{ $_-> track eq $trackname } values %by_index;
}


sub is_local_effects_host { ! $_[0]->send_id }

sub set_wetness {
	my ($self, $p) = @_;
	$self->{wetness} = $p;
	::modify_effect($self->wet_vol, 1, undef, $p);
	::sleeper(0.1);
	::modify_effect($self->dry_vol, 1, undef, 100 - $p);
}
sub is_via_soundcard { 
	my $self = shift;
	
	for (qw(source send)){
		my $type = "$_\_type";
		my $id   = "$_\_id";
		return 0 unless is_channel($self->$id) 
						or $self->$type eq 'soundcard' 
						or is_jack_soundcard($self->$id)
	}
	sub is_channel { $_[0] =~ /^\d+$/ }
	sub is_jack_soundcard { $_[0] =~ /^system/ }
}
sub soundcard_delay {
	my $track_name = shift;
	my ($insert) = grep{ $_->wet_name eq $track_name } values %by_index;
	my $delta = 0;
	$delta = $config->{soundcard_loopback_delay} 
		if defined $insert and $insert->is_via_soundcard;
	::Lat->new($delta,$delta)
}
}
{
package ::PostFaderInsert;
use Modern::Perl; use Carp; our @ISA = qw(::Insert);
use ::Util qw(input_node output_node dest_type);
use ::Log qw(logpkg);
sub add_paths {

	# Since this routine will be called after expand_graph, 
	# we can be sure that every track vertex will connect to 
	# to a single edge, either loop or an output 
	
	my ($self, $g, $name) = @_;
	no warnings qw(uninitialized);
	::logpkg('debug', "add_insert for track: $name");

	my $t = $::tn{$name}; 


	::logpkg('debug', "insert structure: ", sub{$self->dump});

	my ($successor) = $g->successors($name);

	# successor will be either a loop, device or JACK port
	# i.e. can accept multiple signals

	$g->delete_edge($name, $successor);
	my $loop = "$name\_insert_post";
	my $wet = $::tn{$self->wet_name};
	my $dry = $::tn{$self->dry_name};

	::logpkg('debug', "found wet: ", $wet->name, " dry: ",$dry->name);

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
		::logpkg('debug', "edge: @edge");
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
use Modern::Perl; use Carp; our @ISA = qw(::Insert);
use ::Util qw(input_node output_node dest_type);
use ::Log qw(logpkg);


# --- source ---------- wet_send_track  wet_return_track -+-- insert_pre -- track
#                                                         |
# --- source ------------------ dry track ----------------+

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	my $wet_send = ::SlaveTrack->new( 
				name => $self->wet_send_name,
				target => $self->track,
				group => 'Insert',
				hide => 1,
				rw => 'REC'
	);
	map{ ::remove_effect($_)} $wet_send->vol, $wet_send->pan;
	map{ my $track = $_;  map{ delete $track->{$_} } qw(vol pan) } $wet_send;
	$self
} 
sub wet_send_name {
	my $self = shift;
	join('-', $self->track, $self->n, 'wet-send'); 
}
	
	

sub add_paths {
	my ($self, $g, $name) = @_;
	no warnings qw(uninitialized);
	::logpkg('debug', "add_insert for track: $name");

	my $t = $::tn{$name}; 


	::logpkg('debug', "insert structure:", sub{$self->dump});

		# get track source
		
		my ($predecessor) = $g->predecessors($name);

		# delete source connection to track
		
		$g->delete_edge($predecessor, $name);
		my $loop = "$name\_insert_pre";

		my $wet 		= $::tn{$self->wet_name};
		my $dry 		= $::tn{$self->dry_name};
		my $wet_send 	= $::tn{$self->wet_send_name};

		::logpkg('debug', "found wet: ", $wet->name, " dry: ",$dry->name);

		#pre:  wet send path: wet_send_name (slave) -> output

		my @edge = ($self->wet_send_name, output_node($self->send_type));
		$g->add_path($predecessor, @edge);
		::logpkg('debug', "edge: @edge");
		$g->set_vertex_attributes($self->wet_send_name, { 
			send_id => $self->{send_id},
			send_type => $self->{send_type},
			mono_to_stereo => '', # disable for prefader send path 
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
sub remove {
	my $self = shift;
	local $::this_track;
	$::tn{ $self->wet_send_name }->remove;
	$::tn{ $self->dry_name }->remove;
	$::tn{ $self->wet_name }->remove;
	delete $::Insert::by_index{$self->n};
}
1;
