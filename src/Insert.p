{
package ::Insert;
use Modern::Perl;
use Carp;
no warnings qw(uninitialized redefine);
our $VERSION = 0.1;
our ($debug);
local $debug = 0;
use vars qw(%by_index);
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
				hide => 1,
			);
	my $dry = ::SlaveTrack->new( 
				name => $self->dry_name,
				target => $name,
				group => 'Insert',
				hide => 1,
				rw => 'REC');
	map{ ::remove_effect($_)} $wet->vol, $wet->pan, $dry->vol, $dry->pan;

	$self->{dry_vol} = ::Text::t_add_effect($dry, 'ea',[0]);
	$self->{wet_vol} = ::Text::t_add_effect($wet, 'ea',[100]);
	$by_index{$self->n} = $self;
}

# method name for track field holding insert

sub type { (ref $_[0]) =~ /Pre/ ? 'prefader_insert' : 'postfader_insert' }

sub remove {
	my $self = shift;
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
	local $::this_track;
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
}
{
package ::PostFaderInsert;
use Modern::Perl; use Carp; our @ISA = qw(::Insert); our $debug;
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

	# wet send path (no track): track -> loop -> output
	
	my @edge = ($loop, output_node($self->{send_type}));
	$debug and say "edge: @edge";
	::Graph::add_path($name, @edge);
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
	::Graph::add_path(input_node($self->{return_type}), $wet->name, $successor);

	# connect dry track to graph
	
	::Graph::add_path($loop, $dry->name, $successor);
	}
	
}
{
package ::PreFaderInsert;
use Modern::Perl; use Carp; our @ISA = qw(::Insert); our $debug;
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
		::Graph::add_path(@edge);
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
		::Graph::add_path(input_node($self->{return_type}), $wet->name, $loop);

		# connect dry track to graph
		#
		# post: dry path: loop -> dry -> successor
		# pre: dry path:  predecessor -> dry -> loop
		
		::Graph::add_path($predecessor, $dry->name, $loop, $name);
	}
	
}
1;
