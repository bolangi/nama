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
);
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
	my $name = shift;
	"$name\_wet"
}
sub dry_name {
	my $name = shift;
	"$name\_dry"
}
sub new {
	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	my $name = $vals{track};
	my $wet = ::SlaveTrack->new( 
				name => wet_name($name),
				target => $name,
				group => 'Insert',
				rw => 'REC',
				hide => 1,
			);
	my $dry = ::SlaveTrack->new( 
				name => dry_name($name),
				target => $name,
				group => 'Insert',
				hide => 1,
				rw => 'REC');
	$vals{n} ||= idx(); 
	my $self = bless { 
					class	=> $class, 	# for restore
					dry_vol => $dry->vol,
					wet_vol => $wet->vol,
					wetness		=> 100,
					%vals,
								}, $class;
	$by_index{$self->n} = $self;
	if (! $self->{return_id}){
		$self->{return_type} = $self->{send_type};
		$self->{return_id} =  $self->{send_id} if $self->{return_type} eq 'jack_client';
		$self->{return_id} =  $self->{send_id} + 2 if $self->{return_type} eq 'soundcard';
	}
	$self;
}
sub remove {
	my $self = shift;
	$::tn{ wet_name($self->track) }->remove;
	$::tn{ dry_name($self->track) }->remove;
	my $type = (ref $self) =~ /Pre/ ? 'prefader_insert' : 'postfader_insert';
	$::tn{ $self->track }->set(  $type => undef );
	delete $by_index{$self->n};
}
	
sub add_insert {
	my ($type, $send_id, $return_id) = @_;
	# $type : prefader_insert | postfader_insert
	my $old_this_track = $::this_track;
	my $t = $::this_track;
	my $name = $t->name;

	# the input fields will be ignored, since the track will get input
	# via the loop device track_insert
	
	my $class =  $type =~ /pre/ ? '::PreFaderInsert' : '::PostFaderInsert';
	
	my $i = $class->new( 
		track => $t->name,
		send_type 	=> ::dest_type($send_id),
		send_id	  	=> $send_id,
		return_type 	=> ::dest_type($return_id),
		return_id	=> $return_id,
	);
	$t->$type and $by_index{$t->$type}->remove;
	$t->set($type => $i->n); 
	$::this_track = $old_this_track;
}

}
{
package ::PostFaderInsert;
use Modern::Perl; use Carp; our @ISA = qw(::Insert);
sub add_paths {

	# Since this routine will be called after expand_graph, 
	# we can be sure that every track vertex will connect to 
	# to a single edge, either loop or an output 
	
	my ($self, $g, $name) = @_;
	no warnings qw(uninitialized);
	my $debug = 1;
	$debug and say "add_insert for track: $name";

	my $t = $::tn{$name}; 


	$debug and say "insert structure:", $self->dump;

		my ($successor) = $g->successors($name);
		$g->delete_edge($name, $successor);
		my $loop = "$name\_insert";
		my $wet = $::tn{"$name\_wet"};
		my $dry = $::tn{"$name\_dry"};

		$debug and say "found wet: ", $wet->name, " dry: ",$dry->name;

		# wet send path (no track): track -> loop -> output
		
		my @edge = ($loop, ::output_node($self->{send_type}));
		$debug and say "edge: @edge";
		::Graph::add_path($name, @edge);
		$g->set_vertex_attributes($loop, {n => $t->n, j => 'a'});
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
		::Graph::add_path(::input_node($self->{return_type}), $wet->name, $successor);

		# connect dry track to graph
		
		::Graph::add_path($loop, $dry->name, $successor);

		::command_process($t->name); 
		::command_process('wet '.$self->{wetness});
	}
	
	
}
{
package ::PreFaderInsert;
use Modern::Perl; use Carp; our @ISA = qw(::Insert);
sub add_paths {
	my $self = shift;

	# Since this routine will be called after expand_graph, 
	# we can be sure that every track vertex will connect to 
	# to a single edge, either loop or an output 
	
	my ($g, $name) = @_;
	no warnings qw(uninitialized);
	my $debug = 1;
	$debug and say "add_insert for track: $name";

	my $t = $::tn{$name}; 


	$debug and say "insert structure:", $self->dump;

	my $i = $t->postfader_insert;  # assume post-fader send

	my ($successor) = $g->successors($name);
	$g->delete_edge($name, $successor);
	my $loop = "$name\_insert";
	my $wet = $::tn{"$name\_wet"};
	my $dry = $::tn{"$name\_dry"};

	$debug and say "found wet: ", $wet->name, " dry: ",$dry->name;

	# wet send path (no track): track -> loop -> output
	
	my @edge = ($loop, ::output_node($i->{send_type}));
	$debug and say "edge: @edge";
	::Graph::add_path($name, @edge);
	$g->set_vertex_attributes($loop, {n => $t->n, j => 'a'});
	$g->set_edge_attributes(@edge, { 
		send_id => $i->{send_id},
		width => 2,
	});
	# wet return path: input -> wet_track (slave) -> successor
	
	# we override the input with the insert's return source

	$g->set_vertex_attributes($wet->name, {
				width => 2, # default for cooked
				mono_to_stereo => '', # override
				source_type => $i->{return_type},
				source_id => $i->{return_id},
	});
	::Graph::add_path(::input_node($i->{return_type}), $wet->name, $successor);

	# connect dry track to graph
	
	::Graph::add_path($loop, $dry->name, $successor);

	::command_process($t->name); 
	::command_process('wet '.$i->{wetness});
}
	
}
1;
