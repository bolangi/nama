# ------------  Bus --------------------
{
package ::Bus;
use Modern::Perl; use Carp; 
use ::Log qw(logsub logpkg);
use ::Globals qw(:trackrw $setup); 
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
					engine_group
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
		#::throw("$vals{name}: bus name already exists. Skipping.") unless $::quiet;
		return;
	}
	my $bus = bless { 
		class => $class, # for serialization, may be overridden
		rw   	=> MON, # for group control
		@_ }, $class;
	$by_name{$bus->name} = $bus;
}
sub group { $_[0]->name }


sub tracks { # returns list of track names in bus
	my $bus = shift;
	map{ $_->name } $bus->track_o;
}
sub track_o { 
	my $bus = shift;
	grep{ $_->group eq $bus->name } ::all_tracks();
}
sub last {
	#logpkg('debug', "group: @_");
	my $bus = shift;
	my $max = 0;
	map{ 
		my $track = $_;
		my $last;
		$last = $track->last || 0;
		#print "track: ", $track->name, ", last: $last\n";

		$max = $last if $last > $max;

	} $bus->track_o;
	$max;
}

sub remove { ::throw($_[0]->name, " is system bus. No can remove.") }

sub tracks_on {
	my $bus = shift;
	for ( $bus->track_o )
	{
	my $old = $setup->{bus}->{oldrw}->{$_->name};
		$_->set( rw =>  $old) if $old;
			delete $setup->{bus}->{oldrw}->{$_->name };
	}
}

sub tracks_off {
	my $bus = shift;
	return if not grep { $_->rw ne OFF } $bus->track_o;
	for ( $bus->track_o )
	{
		delete $setup->{bus}->{oldrw}->{$_->name };
		next if $_->rw eq OFF;
		$setup->{bus}->{oldrw}->{$_->name } = $_->rw;
		$_->set( rw => OFF );
	}	
}

## class methods

# all buses that have mutable state, and therefore reason to
# save or display that state

sub all { values %by_name }

sub overall_last { 
	my $max = 0;
	map{ my $last = $_->last; $max = $last if $last > $max  } all();
	$max;
}
sub settings_line {
	
	my ($mix,$bus) = @_;
	
	my $nothing = '-' x 77 . "\n";
	#return if $maybe_mix->name eq 'Main' or $maybe_mix->group eq 'Mastering';
	return unless defined $mix;

	my ($bustype) = $bus->class =~ /(\w+)$/;
	my $line = join " ", $bustype ,$bus->name;
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
package ::SubBus; # with magic for Main bus
use Modern::Perl; use Carp; our @ISA = '::Bus';
use ::Log qw(logsub logpkg);
use ::Util qw(input_node);
use ::Globals qw(:trackrw %tn);

# connect source --> member_track --> mix_track

sub output_is_connectable {
 	my $bus = shift;

	# Either the bus's mix track is set to REC or MON
 	
 	$bus->send_type eq 'track' and $::tn{$bus->send_id}->rec_status =~ /REC|MON/

	# Or, during mixdown, we connect bus member tracks to Main
	# even tho Main may be set to OFF
	
	or $bus->send_type eq 'track' 
				and $bus->send_id eq 'Main' 
				and $::tn{Mixdown}->rec
	
	# or we are connecting directly to a loop device
	or $bus->send_type eq 'loop' and $bus->send_id =~ /^\w+_(in|out)$/;
}

sub apply {
	no warnings 'uninitialized';
	my ($bus, $g)  = @_;
	logpkg('debug', "bus ". $bus->name. ": applying routes");
	logpkg('debug', "Bus destination is type: $bus->{send_type}, id: $bus->{send_id}");
	my @wantme = $bus->wantme;
	logpkg('debug', "bus ". $bus->name. " consumed by ".$_->name) for @wantme;
	map{ 
		my $member = $_;
		# connect member track input paths
		logpkg('debug', "track ".$_->name);
		my @path = $member->input_path;
		$g->add_path(@path) if @path;
		logpkg('debug',"input path: @path") if scalar @path;

		logpkg('debug', join " ", "bus output:", $_->name, $bus->send_id);

		# connect member track outputs to target
		for (@wantme) { 
			my $consumer = $_; 
			::Graph::add_path_for_send($g, $member->name, 'track', $consumer->name)
		}
		
		# add paths for recording
		
		::Graph::add_path_for_rec($g,$_) 
			if $_->rec
				and ! $::mode->preview and ! $::mode->doodle;

	} grep {$_->rec_status ne OFF} $bus->track_o;
}
sub remove {
	my $bus = shift;

	# all tracks returned to Main group
	map{$_->set(group => 'Main') } $bus->track_o;

	my $mix_track = $::tn{$bus->name};

	# remove mix track unless it has some WAV files
	$mix_track->remove if defined $mix_track and not scalar @{ $mix_track->versions };

	# remove bus from index
	
	delete $::bn{$bus->name};
} 
sub wantme {
	my $bus = shift;
	no warnings 'uninitialized';
	my @wantme = grep{ 	$_->{rw} =~ /REC|MON/ 
					and $_->source_type eq 'bus' 
					and $_->source_id eq $bus->name 
					and $_->is_used} ::all_tracks();
	@wantme

}
}
{
package ::SendBusRaw;
use Modern::Perl; use Carp; our @ISA = '::Bus';
use ::Log qw(logsub logpkg);
sub apply {
	my $bus = shift;
	map{ 
		my @input_path = $_->input_path;
		$::g->add_edge(@input_path);
		$::g->set_edge_attributes( @input_path, 
			{ width => $::tn{$_->target}->width });
		my @edge = ($_->name, ::output_node($bus->send_type));
		$::g->add_edge(@edge);
		$::g->set_edge_attributes( @edge, { 
			send_id => $bus->send_id,
			width => 2 }); # force to stereo 
	} grep{ $_->input_path } $bus->track_o;
}
sub remove {
	my $bus = shift;

	# delete all tracks
	map{$_->remove } $bus->track_o;

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
				send_type => $bus->send_type,
				send_id => $bus->send_id,
				width => 2})
	} $bus->track_o;
}

}
{
package ::MidiBus;
use Modern::Perl; use Carp; our @ISA = '::Bus';
use ::Log qw(logsub logpkg);
use ::Util qw(input_node);
use ::Globals qw(:trackrw);

sub output_is_connectable {
 	my $bus = shift;
	undef	

}

sub apply {
	my ($bus)  = @_;
	logpkg('debug', "bus ". $bus->name. ": applying routes");
	logpkg('debug', "Bus destination is type: $bus->{send_type}, id: $bus->{send_id}");
	# 
}
sub remove { }  # We never remove the Midi bus
}

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
	my $track = shift || ($this_track ||= $tn{Main});

	return unless $track; # needed for test environment

	# The current sequence changes when the user touches a
	# track that belongs to another sequence.
	
	$this_sequence = $bn{$track->group} if (ref $bn{$track->group}) =~ /Sequence/;

	my $bus_name = 
		$track->name =~ /Main|Mixdown/ 	
		? 'Main'
		: $track->is_mixing()			
			? $track->name 
			: $track->group;
	
	select_bus($bus_name);
}
sub select_bus {
	my $name = shift;
	my $bus = $bn{$name} or return;
	$this_bus = $name;
	$this_bus_o = $bus;
}
sub add_bus {
	# creates named bus if necessary
	# creates named mix track if necessary
	# sets mix track to MON with bus as source
	my ($name, @args) = @_; 
	
	# don't create bus if such named already exists
	::SubBus->new( 
		name => $name, 
		send_type => 'track',
		send_id	 => $name,
		) unless $bn{$name};
	
	my $bus = $bn{$name};
	# modify bus and track settings to activate bus
	$bus->set(rw => MON); 

	@args = ( 
		rw 			=> MON,
		source_type => 'bus',
		source_id   => $name,
		@args
	);

	$tn{$name} and pager_newline( qq($name: setting as mix track for bus "$name"));

	my $track = $tn{$name}// add_track($name, width => 2);

	$track->set( @args );
}
	

	
sub add_submix {

	my ($name, $dest_id, $bus_type) = @_;
	my $dest_type = dest_type( $dest_id );

	# dest_type: soundcard | jack_client | loop | jack_port | jack_multi
	
	logpkg('debug',"name: $name, dest_type: $dest_type, dest_id: $dest_id");
	if ($bn{$name} and (ref $bn{$name}) !~ /SendBus/){
		::throw($name,": bus name already in use. Aborting."), return;
	}
	if ($bn{$name}){
		::pager_newline( qq(monitor bus "$name" already exists.  Updating with new tracks.) );
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
	map{ ::EarTrack->new(	name => "$name\_$_", # BusName_TrackName
							rw => MON,
							target => $_,
							group  => $name,
							width => 2,
							hide	=> 1,
						)
   } $bn{Main}->tracks;
		
}

	
sub update_submix {
	my $name = shift;
		add_submix( $name, 
						 $bn{$name}->send_id),
						 "dummy",
}
sub remove_submix_helper_tracks {
	my $name = shift;
	#say "got name: $name";
	my @submixes = submixes(); 
	#say "got submixes:", Dumper \@submixes;
	for my $sm ( @submixes ){ 
		my $to_remove = join '_', $sm->name, $name;
		#say "to_remove: $to_remove";
		local $quiet;
		$quiet++;
		for my $name ($sm->tracks) { 
			$tn{$name}->remove, last if $name eq $to_remove
		}
	}

}
sub submixes { grep { (ref $_) =~ /SendBusCooked/ } values %::Bus::by_name }

}
}
1;
__END__
