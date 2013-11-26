# ------------  Bus --------------------

package ::Bus;
use Modern::Perl; use Carp; 
use ::Log qw(logsub logpkg);
our @ISA = qw( ::Object );

# share the following variables with subclasses

our $VERSION = 1.0;
our (%by_name);
use ::Object qw(
					name
					rw
					version 
					send_type
					send_id
					class

					);
sub initialize { 
	%by_name = (); 
};
sub new {
	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	if (! $vals{name}){
		::throw("missing bus name");
		return
	}
	if ( $by_name{$vals{name}} ){ 
		::throw("$vals{name}: bus name already exists. Skipping.");
		return;
	}
	my $bus = bless { 
		class => $class, # for serialization, may be overridden
		rw   	=> 'REC', # for group control
		@_ }, $class;
	$by_name{$bus->name} = $bus;
}
sub group { $_[0]->name }


sub tracks { # returns list of track names in bus
	my $bus = shift;
	map{ $_->name } grep{ $_->group eq $bus->name } ::Track::all();
}

sub last {
	#logpkg('debug', "group: @_");
	my $group = shift;
	my $max = 0;
	map{ 
		my $track = $_;
		my $last;
		$last = $track->last || 0;
		#print "track: ", $track->name, ", last: $last\n";

		$max = $last if $last > $max;

	}	map { $::Track::by_name{$_} } $group->tracks;
	$max;
}

sub remove { ::throw($_[0]->name, " is system bus. No can remove.") }

{ my %allows = (REC => 'REC/MON', MON => 'MON', OFF => 'OFF');
sub allows { $allows{ $_[0]->rw } }
}
{ my %forces = (
		REC => 'REC (allows REC/MON)', 
		MON => 'MON (forces REC to MON)', 
		OFF => 'OFF (enforces OFF)'
 );
sub forces { $forces{ $_[0]->rw } }
}
	
## class methods

# sub buses, and Main
sub all { grep{ ! $::config->{_is_system_bus}->{$_->name} } values %by_name };

sub overall_last { 
	my $max = 0;
	map{ my $last = $_->last; $max = $last if $last > $max  } all();
	$max;
}
sub settings_line {
	
	my ($mix,$bus) = @_;
	
	my $nothing = '-' x 77 . "\n";
	#return if $maybe_mix->name eq 'Master' or $maybe_mix->group eq 'Mastering';
	return unless defined $mix;

	my ($bustype) = $bus->class =~ /(\w+)$/;
	my $line = join " ", $bustype ,$bus->name,"is",$bus->forces;
	$line   .= " Version setting".$bus->version if $bus->version;
	#$line   .= "feeds", 
	$line .= " Mix track is ". $mix->rw;
	$line = "------[$line]";
	$line .= '-' x (77 - length $line);
	$line .= "\n";
	$line
}
	
sub trackslist {
	my $bus = shift;
	my $mix = $::tn{$bus->send_id};
	my @list = ($mix,$bus);
	push @list, map{$::tn{$_}} ($mix->name, $bus->tracks);
	\@list;
}

sub apply {}  # base class does no routing of its own

### subclasses
{
package ::SubBus;
use Modern::Perl; use Carp; our @ISA = '::Bus';
use ::Log qw(logsub logpkg);
use ::Util qw(input_node);

# connect source --> member_track --> mix_track

sub output_is_connectable {
 	my $bus = shift;

	# Either the bus's mix track must be set to REC:
 	
 	$bus->send_type eq 'track' and $::tn{$bus->send_id}->rec_status eq 'REC'

	# Or, during mixdown, we connect bus member tracks to Master
	# even tho Master may be set to OFF
	
	or $bus->send_type eq 'track' 
				and $bus->send_id eq 'Master' 
				and $::tn{Mixdown}->rec_status eq 'REC'

	
	or $bus->send_type eq 'loop' and $bus->send_id =~ /^\w+_(in|out)$/;
}

sub apply {
	no warnings 'uninitialized';
	my ($bus, $g)  = @_;
	logpkg('debug', "bus ". $bus->name. ": applying routes");
	logpkg('debug', "Bus destination is type: $bus->{send_type}, id: $bus->{send_id}");
	map{ 
		# connect member track input paths
		logpkg('debug', "track ".$_->name);
		my @path = $_->input_path;
		$g->add_path(@path) if @path;
		logpkg('debug',"input path: @path") if scalar @path;

		logpkg('debug', join " ", "bus output:", $_->name, $bus->send_id);

		# connect member track outputs to target
		# disregard Master track rec_status when connecting
		# Main bus during mixdown handling

		::Graph::add_path_for_send($g, $_->name, $bus->send_type, $bus->send_id )
			if $bus->output_is_connectable;
		
		# add paths for recording
		
		# say "rec status: ",$_->rec_status;
		# say "rec defeat: ",$_->rec_defeat; 
		# say q($mode->{preview}: ),$::mode->{preview};
		# say "result", $_->rec_status eq 'REC' and ! $_->rec_defeat
		# 		and ! ( $::mode->{preview} eq 'doodle' );
			
		::Graph::add_path_for_rec($g,$_) 
			if $_->rec_status eq 'REC' 
			and ! $_->rec_defeat
				and $::mode->{preview} !~ /doodle|preview/ ;

	} grep {$_->rec_status ne 'OFF'} grep{ $_->group eq $bus->group} ::Track::all()
}
sub remove {
	my $bus = shift;

	# all tracks returned to Main group
	map{$::tn{$_}->set(group => 'Main') } $by_name{$bus->name}->tracks;

	my $mix_track = $::tn{$bus->name};

	if ( defined $mix_track ){
	 
		$mix_track->unbusify;
	
		# remove mix track unless it has some WAV files

		$mix_track->remove unless scalar @{ $mix_track->versions };
	}

	# remove bus from index
	
	delete $::bn{$bus->name};
} 
}
{
package ::SendBusRaw;
use Modern::Perl; use Carp; our @ISA = '::Bus';
use ::Log qw(logsub logpkg);
sub apply {
	my $bus = shift;
	map{ 
		$::g->add_edge($_->input_path);
		my @edge = ($_->name, ::output_node($bus->send_type));
		$::g->add_edge(@edge);
		$::g->set_edge_attributes( @edge, { 
			send_id => $bus->send_id,
			width => 2 }); # force to stereo 
	} grep{ $_->group eq $bus->group and $_->input_path} ::Track::all()
}
sub remove {
	my $bus = shift;

	# delete all (slave) tracks
	map{$::tn{$_}->remove } $by_name{$bus->name}->tracks;

	# remove bus
	delete $by_name{$bus->name};
}
}
{
package ::SendBusCooked;
use ::Log qw(logsub logpkg);
use Modern::Perl; use Carp; our @ISA = '::SendBusRaw';

# graphic routing: target -> slave -> bus_send_type

sub apply {
	my $bus = shift;
	my $g = shift;
	map{ my @edge = ($_->name, ::output_node($bus->send_type));
		 $g->add_path( $_->target, @edge);
		 $g->set_edge_attributes( @edge, { 
				send_id => $bus->send_id,
				width => 2})
	} grep{ $_->group eq $bus->group} ::Track::all()
}


}

{ package ::Sequence;
use Modern::Perl; use Carp; 
use ::Assign qw(json_out);
use ::Log qw(logsub logpkg);
use ::Effects qw(fxn modify_effect);
our @ISA = '::SubBus';

# share the following variables with subclasses

our $VERSION = 1.0;
use ::Object qw( items clip_counter );
use SUPER;
sub new { 
	my ($class,%args) = @_;
	# take out args we will process
	my $items = delete $args{items};
	my $counter = delete $args{clip_counter};
	#logpkg('debug', "items: ",map{json_out($_->as_hash)}map{$::tn{$_}}@$items) if $items;
	$items //= [];
	@_ = ($class, %args);
	my $self = super();
	logpkg('debug',"new object: ", json_out($self->as_hash));
	logpkg('debug', "items: ",json_out($items));
	$self->{clip_counter} = $counter;
	$self->{items} = $items;
	$::this_sequence = $self;
	$self;
} 
sub clip {
	my ($self, $index) = @_;
	return 0 if $index <= 0;
	$::tn{$self->{items}->[$index - 1]}
}
sub rw { 
	my $self = shift;
	$::mode->{offset_run} ? 'OFF' : $self->{rw}
}
# perl indexes arrays at zero, for nama users we number items from one
sub insert_item {
	my $self = shift;
	my ($item, $index) = @_;
	$self->append_item($item), return if $index == @{$self->{items}} + 1;
	$self->verify_item($index) or die "$index: sequence index out of range";
	splice @{$self->{items}}, $index - 1,0, $item->name 
}
sub verify_item {
	my ($self, $index) = @_;
	$index >= 1 and $index <= scalar @{$self->items} 
}
sub delete_item {
	my $self = shift;
	my $index = shift;
	$self->verify_item($index) or die "$index: sequence index out of range";
	my $trackname = splice(@{$self->{items}}, $index - 1, 1);
	$::tn{$trackname} and $::tn{$trackname}->remove;
}
sub append_item {
	my $self = shift;
	my $item = shift;
	push( @{$self->{items}}, $item->name );
}
sub item {
	my $self = shift;
	my $index = shift;
	return 0 if $index <= 0;
	$::tn{$self->{items}->[$index - 1]};
}
sub list_output {
	my $self = shift;
	my $i;
	join "\n","Sequence $self->{name} clips:",
		map { join " ", 
				++$i, 
				$::tn{$_}->n,
				$_,
				sprintf("%.3f %.3f", $::tn{$_}->duration, $::tn{$_}->endpoint),
		} @{$self->items}
}
sub remove {
	my $sequence = shift;

	# delete all clips
	map{$::tn{$_}->remove } $by_name{$sequence->name}->tracks;

	# delete clip array
	delete $sequence->{items};
	
	my $mix_track = $::tn{$sequence->name};

	if ( defined $mix_track ){
	 
		$mix_track->unbusify;
	
		# remove mix track unless it has some WAV files

		$mix_track->remove unless scalar @{ $mix_track->versions };
	}

	# remove sequence from index
	
	delete $by_name{$sequence->name};
} 
sub new_clip {
	my ($self, $track, %args) = @_; # $track can be object or name
	my $markpair = delete $args{region};
	logpkg('debug',json_out($self->as_hash), json_out($track->as_hash));
	ref $track or $track = $::tn{$track} 
		or die("$track: track not found."); 
	my %region_args = (
		region_start => $markpair && $markpair->[0]->name || $track->region_start,
		region_end	 => $markpair && $markpair->[1]->name || $track->region_end
	);
	my $clip = ::Clip->new(
		target => $track->basename,
		name => $self->unique_clip_name($track->name, $track->monitor_version),
		rw => 'MON',
		group => $self->name,
		version => $track->monitor_version,
		hide => 1,
		%region_args,
		%args
	);
	modify_effect( $clip->vol, 1, undef, fxn($track->vol)->params->[0]);
	modify_effect( $clip->pan, 1, undef, fxn($track->pan)->params->[0]);
	$clip
}
sub new_spacer {
	my( $self, %args ) = @_;
	my $position = delete $args{position};
	my $spacer = ::Spacer->new( 
		duration => $args{duration},
		name => $self->unique_spacer_name(),
		rw => 'OFF',
		group => $self->name,
	);
	$self->insert_item( $spacer, $position || ( scalar @{ $self->{items} } + 1 ))
}
sub unique_clip_name {
	my ($self, $trackname, $version) = @_;
	join '-', $self->name , ++$self->{clip_counter}, $trackname, 'v'.$version;
}
sub unique_spacer_name {
	my $self = shift;
	join '-', $self->name, ++$self->{clip_counter}, 'spacer';
}
} # end package
# ---------- Bus routines --------
{
package ::;
use Modern::Perl; use Carp;
use ::Util qw(dest_type);
our (
	$this_track,
	$this_bus,
	%tn,
	%bn,
);

sub set_current_bus {
	my $track = shift || ($this_track ||= $tn{Master});
	return unless $track;
	#say "track: $track";
	#say "this_track: $this_track";
	#say "master: $tn{Master}";
	if( $track->name =~ /Master|Mixdown/){ $this_bus = 'Main' }
	elsif( $bn{$track->name} ){
		$this_bus = $track->name;
		$this_sequence = $bn{$track->group} if (ref $bn{$track->group}) =~ /Sequence/;
}
	else { 
		$this_bus = $track->group;
		$this_sequence = $bn{$track->group} if (ref $bn{$track->group}) =~ /Sequence/;
 	}
}
sub add_sub_bus {
	my ($name, @args) = @_; 
	
	::SubBus->new( 
		name => $name, 
		send_type => 'track',
		send_id	 => $name,
		) unless $::Bus::by_name{$name};

	@args = ( 
		rec_defeat	=> 1,
		is_mix_track => 1,
		rw 			=> 'REC',
		@args
	);

	$tn{$name} and ::pager3( qq($name: setting as mix track for bus "$name"));

	my $track = $tn{$name}// add_track($name, width => 2);

	$track->set( @args );
	
}
	
sub add_send_bus {

	my ($name, $dest_id, $bus_type) = @_;
	my $dest_type = dest_type( $dest_id );

	# dest_type: soundcard | jack_client | loop | jack_port | jack_multi
	
	print "name: $name: dest_type: $dest_type dest_id: $dest_id\n";
	if ($bn{$name} and (ref $bn{$name}) !~ /SendBus/){
		::throw($name,": bus name already in use. Aborting."), return;
	}
	if ($bn{$name}){
		::pager3( qq(monitor bus "$name" already exists.  Updating with new tracks.) );
	} else {
	my @args = (
		name => $name, 
		send_type => $dest_type,
		send_id	 => $dest_id,
	);

	my $class = $bus_type eq 'cooked' ? '::SendBusCooked' : '::SendBusRaw';
	my $bus = $class->new( @args );

	$bus or carp("can't create bus!\n"), return;

	}
	map{ ::SlaveTrack->new(	name => "$name\_$_", # BusName_TrackName
							rw => 'MON',
							target => $_,
							group  => $name,
						)
   } $bn{Main}->tracks;
		
}

	
sub update_send_bus {
	my $name = shift;
		add_send_bus( $name, 
						 $bn{$name}->send_id),
						 "dummy",
}
sub new_sequence {

	my %args = @_;
	my $name = $args{name};
	my @tracks = @{ $args{tracks} };
	my $group = $args{group} || 'Main';
	my $mix_track = $tn{$name} || add_track($name, group => $group);
	$mix_track->set( rec_defeat	=> 1,
						is_mix_track => 1,
						rw 			=> 'REC');
	$this_sequence = ::Sequence->new(
		name => $name,
		send_type => 'track',
		send_id	 => $name,
	);
;
	map{ $this_sequence->append_item($_) }
	map{ $this_sequence->new_clip($_)} @tracks;

}
sub compose_sequence {
	my ($sequence_name, $track, $markpairs) = @_;
	my $sequence = ::new_sequence( name   => $sequence_name);
	my @clips = map { 
		$sequence->new_clip($track, region => $_) 
	} @$markpairs
}

} # end package

1;
__END__
