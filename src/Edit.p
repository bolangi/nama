# ----------- Edit ------------
package ::Edit;

# each edit is identified by:
#  -  host track name
#  -  host track version
#  -  edit name (i.e. sax-v1) used as key in %by_name
#

use Modern::Perl;
our $VERSION = 1.0;
use Carp;
no warnings qw(uninitialized);
our @ISA;
use vars qw(%n %by_index %by_name );
use ::Object qw( 
				n
				play_start_mark_name
				rec_start_mark_name
				rec_end_mark_name
				host_track
				host_version
				fades
				 );

sub initialize {
	%n = ();
	%by_name = ();
	@::edits_data = (); # for save/restore
}

sub next_n {
	my ($trackname, $version) = @_;
	++$n{$trackname}{$version}
}

sub new {
	my $class = shift;	
	my %vals = @_;

	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	
	# increment edit version number by host track and host version
	
	my $n = next_n(@vals{qw(host_track host_version)});

	my $self = bless 
		{ 
			n 		=> $n,
		  	fades 	=> [],
			@_ 
		}, $class;

	$by_name{ $self->edit_name } = $self;

	#print "self class: $class, self type: ", ref $self, $/;

	my $name = $self->host_track;
	my $host = $::tn{$name};

# Routing:
#
#    sax-v5-original --+
#                      |
#    sax-v5-edit1 -----+--- sax-v5 (bus/track) --- sax (bus/track) ----- 


	# prepare top-level bus and mix track
	
	$host->busify;     # i.e. sax (bus/track)
	
	# create the version-level bus and mix track
	# i.e. sax-v5 (bus/track)
	
	::Track->new(
		name 		=> $self->edit_root_name, # i.e. sax-v5
	#	rw			=> 'REC',                 # set by ->busify
		source_type => 'bus',
		source_id 	=> 'bus',
		width		=> 2,                     # default to stereo 
	#	rec_defeat 	=> 1,                     # set by ->busify
		group   	=> $self->host_track,     # i.e. sax
	)->busify;                                # create sub-bus

	# create host track alias if necessary

	# To ensure that users don't get into trouble, we would like to 
	# restrict this track:
	#  - version number must *not* be allowed to change
	#  - rw setting must be fixed to 'MON' #
	#  The easiest way may be to subclass the 'set' routine
	
	my $host_track_alias = $::tn{$self->host_alias} // 
		::VersionTrack->new(
			name 	=> $self->host_alias,
			version => $host->monitor_version, # static
			target  => $host->name,
			rw		=> 'MON',                  # do not REC
			group   => $self->edit_root_name,  # i.e. sax-v5
		);

	# create edit track
	#   - same name as edit
	#   - we expect to record
	#   - source_type and source_id come from host track
	
	my $edit_track = ::EditTrack->new(
		name		=> $self->edit_name,
		rw			=> 'REC',
		source_type => $host->source_type,
		source_id	=> $host->source_id,
		group		=> $self->edit_root_name,  # i.e. sax-v5
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
sub host_alias {
	my $self = shift;
	join '-', $self->edit_root_name, 'original'
}

# default mark names

sub play_start_name {
	my $self = shift;
	$self->play_start_mark_name || (join '-', $self->edit_name,'play-start')
}
sub rec_start_name {
	my $self = shift;
	$self->rec_start_mark_name || (join '-', $self->edit_name,'rec-start')
}
sub rec_end_name {
	my $self = shift;
	$self->rec_end_mark_name || (join '-', $self->edit_name,'rec-end')
}

sub play_start_mark { $::Mark::by_name{$_[0]->play_start_name} }
sub rec_start_mark  { $::Mark::by_name{$_[0]->rec_start_name}  }
sub rec_end_mark    { $::Mark::by_name{$_[0]->rec_end_name}    }

# the following are unadjusted values

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
	$::Mark::by_name{$self->$markfield}->{time}
}

sub store_fades { # replacing previous
	my $edit = shift;
	my @fades = @_;
	my @indices = map{$_->n} @fades;
	$edit->remove_fades;
	$edit->set(fades => \@indices)
}
sub remove_fades {
	my $edit = shift;
	map{ $_->remove } map{ $::Fade::by_index{$_} } @{$edit->fades};
	$edit->set(fades => []);
}

sub host	 		{ $::tn{$_[0]->host_track} } # top-level mix track, i.e. 'sax'
sub bus 			{ $::Bus::by_name{$_[0]->host_track} }  # top-level bus
sub version_mix     { $::tn{$_[0]->edit_root_name} }        # in top-level bus
sub version_bus     { $::Bus::by_name{$_[0]->edit_root_name} } # version-level bus
sub host_alias_track{ $::tn{$_[0]->host_alias} }            # in version_bus
sub edit_track 		{ $::tn{$_[0]->edit_name} }             # in version_bus

# utility routines
1;

