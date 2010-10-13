# ----------- Edit ------------
package ::Edit;

# each edit is uniquely identified by:
#  -  host track name
#  -  host track version
#  -  edit index

# - I would like to let users adjust edit input source_type/source_id
#   at the host track

# - But as mix track, the host track is usually set to bus/bus
# - That information goes only to $track->input_path() 
#
# - Solution: new field "is_mix_track"
# - set when we create bus, clear when remove bus

# - save/recall
# - new project initializations
# - region and playat settings
#

use Modern::Perl;
our $VERSION = 1.0;
use Carp;
no warnings qw(uninitialized);
our @ISA;
use vars qw(%n %by_index %by_name );
use ::Object qw( 
				n
				play_start_mark
				rec_start_mark
				rec_end_mark
				host_track
				host_version
				 );

sub initialize {
	%n = ();
	%by_index = ();	
	%by_name = ();
}

sub next_n {
	my ($trackname, $version) = @_;
	++$n{$trackname}{$version}
}
sub edit_index { join ':',@_ }

sub new {
	my $class = shift;	
	my %vals = @_;

	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	
	my $self = bless { n => next_n(@vals{qw(host_track host_version)}), @_ }, $class;

	$by_index{ edit_index($self->host_track, $self->host_version, $self->n) } = $self;
	$by_name{ $self->edit_name } = $self;

	#print "self class: $class, self type: ", ref $self, $/;
	
	my $name = $self->host_track;

	# get the current version of host_track

	# host track will become mix track of a sub-bus
	
	# create the bus
	
	::SubBus->new( 
		name => $name, 
		send_type => 'bus',
		send_id	 => $name,
	);

	# convert host track to mix track
	
	my @vals = (is_mix_track => 1,
				rec_defeat 	=> 1,
				rw => 'REC',
				);

	$::tn{$name}->set( @vals );

	# create host track alias if necessary

	# To ensure that users don't get into trouble, we would like to 
	# restrict this track:
	#  - version number must *not* be allowed to change
	#  - rw setting must be fixed to 'MON'
	#
	#  The easiest way may be to provide our own 'set' routine
	#  since this is what is used by all commands
	
	my $host_track_alias = ::Track->new(
		name 	=> $self->host_track_alias_name,
		version => $::tn{$self->host_track}->monitor_version,
		target  => $self->host_track,
		rw		=> 'MON',
		group   => $self->host_track, # bus affiliation
	);

	# create edit track
	#   - same name as edit
	#   - we expect to record
	#   - source_type and source_id come from host track
	
	my $edit_track = ::EditTrack->new(
		name	=> $self->edit_name,
		rw		=> 'REC',
		group	=> $self->host_track, # bus affiliation
	); 
	$self
}

sub edit_root_name {
	my $self = shift;
	join '-', $self->host_track, 'v'.$self->host_version;
}

sub edit_name {
	my $self = shift;
	join '-', $self->edit_root_name, 'edit'.$self->n
}

sub host_track_alias_name {
	my $self = shift;
	join '-', $self->edit_root_name, 'original'
}

# default mark names

sub play_start_name {
	my $self = shift;
	join '-', $self->edit_name,'play-start'
}
sub rec_start_name {
	my $self = shift;
	join '-', $self->edit_name,'rec-start'
}
sub rec_end_name {
	my $self = shift;
	join '-', $self->edit_name,'rec-end'
}
sub play_start_time {
	my $self = shift;
	$self->marktime('play_start_name')
}
sub rec_start_time {
	my $self = shift;
	$self->marktime('rec_start_name')
}
sub rec_end_time {
	my $self = shift;
	$self->marktime('rec_end_name')
}
sub play_end_time {
	my $self = shift;
	$self->marktime('rec_end_name') + $::edit_playback_end_margin
}

sub marktime { 
	my ($self,$markfield) = @_;
	::Mark::by_name{$self->$markfield}->time
}

sub is_active {
	my $self = shift;

	# the host track's current version must match
	# the version the Edit object applies to
	
	# however the host track 'sax' will be made into a bus
	# and the original WAV will be offered through
	# 'sax-v3-original'
	
	#$::tn{$self->host_track}->current_version == $self->host_version
}


sub host_alias {
	my $self = shift;
}

sub remove { # supply index
	my $i = shift;
	#my $edit = $by_index{$i};
	#my $track = $::tn{$edit->track};
	
	# remove object from index
	#delete $by_index{$i};

}
1;

