{
package ::Edit;
use ::Globals qw($config REC PLAY);

# each edit is identified by:
#  -  host track name
#  -  host track version
#  -  edit name (i.e. sax-v1) used as key in %by_name
#

use v5.36;
our $VERSION = 1.0;
use Carp qw(confess croak);
no warnings qw(uninitialized);
our @ISA;
our($n, %by_index, %by_name);
use ::Object qw( 
				n
				play_start_mark_name
				rec_start_mark_name
				rec_end_mark_name
				host_track
				host_version
				edit_label
				fades
				 );

sub initialize {
	$n = 0;
	%by_name = ();
	%by_index = ();
	@::edits_data = (); # for save/restore
}

sub next_n { ++$n }

sub new {
	local $::this_track = $::this_track;
	my $class = shift;	
	my %vals = @_;

	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;

	my $self = bless 
		{ 
			n 		=> next_n(),
		  	fades 	=> [],
			@_ 
		}, $class;

    $n = $self->n if $self->n > $n;
	$by_name{ $self->edit_name } = $self;
	$by_index{ $self->n } = $self;

	#print "self class: $class, self type: ", ref $self, $/;

	my $name = $self->host_track;
	my $host = $::tn{$name};
	confess( ::project_dir().": missing host_track".  $::this_track->dump. $self->dump. ::nama_cmd("dumpa")) if !$host;


# Routing:
#
#    sax-v5-original --+ #  version_bus/version_mix   host_bus/host
#                      |
#    sax-v5-edit1 -----+--- sax-v5 (bus/track) --- sax (bus/track) ----- 


	# prepare top-level bus and mix track
	
	$host->activate_bus;     # i.e. sax (bus/track)
	
	# create the version-level bus and mix track
	# i.e. sax-v5 (bus/track)

	# (maybe it already exists)
	
	my $version_mix = $::tn{$self->edit_root_name} // ::Track->new(

		name 		=> $self->edit_root_name, # i.e. sax-v5
	#	rw			=> REC,                 # set by ->activate_bus
		source_type => 'bus',
		source_id 	=> 'bus',
		width		=> 2,                     # default to stereo 
		group   	=> $self->host_track,     # i.e. sax
		hide		=> 1,
	); 
	$version_mix->activate_bus;

	# create host track alias if necessary

	# To ensure that users don't get into trouble, we would like to 
	# restrict this track:
	#  - version number must *not* be allowed to change
	#  - rw setting must be fixed to PLAY #
	#  The easiest way may be to subclass the 'set' routine
	
	my $host_track_alias = $::tn{$self->host_alias} // 
		::VersionTrack->new(
			name 	=> $self->host_alias,
			version => $self->host_version, # static
			target  => $host->name,
			rw		=> PLAY,                  # do not REC
			group   => $self->edit_root_name,  # i.e. sax-v5
			hide 	=> 1,
		);

	# create edit track
	#   - same name as edit
	#   - we expect to record
	#   - source_type and source_id come from host track
	
	my $edit_track = ::EditTrack->new(
		name		=> $self->edit_name,
		rw			=> REC,
		source_type => $host->source_type,
		source_id	=> $host->source_id,
		width       => $host->width,
		group		=> $self->edit_root_name,  # i.e. sax-v5
		hide		=> 1,
	); 
	$self
}
sub edit_root_name ($self) {
	join '-', $self->host_track, 'v'.$self->host_version;
}
sub edit_name ($self) {
	join '-', $self->edit_root_name, ($self->edit_label // ('edit'.$self->n))
}
sub host_alias ($self) {
	join '-', $self->edit_root_name, 'original'
}

# default mark names

sub play_start_name ($self) {
	$self->play_start_mark_name || (join '-', $self->edit_name,'play-start')
}
sub rec_start_name ($self) {
	$self->rec_start_mark_name || (join '-', $self->edit_name,'rec-start')
}
sub rec_end_name ($self) {
	$self->rec_end_mark_name || (join '-', $self->edit_name,'rec-end')
}

sub play_start_mark { $::Mark::by_name{$_[0]->play_start_name} }
sub rec_start_mark  { $::Mark::by_name{$_[0]->rec_start_name}  }
sub rec_end_mark    { $::Mark::by_name{$_[0]->rec_end_name}    }

# the following are unadjusted values

sub play_start_time ($self) {
	$self->marktime('play_start_name')
}
sub rec_start_time ($self) {
	$self->marktime('rec_start_name')
}
sub rec_end_time ($self) {
	$self->marktime('rec_end_name')
}
sub play_end_time ($self) {
	$self->marktime('rec_end_name') + $config->{edit_playback_end_margin}
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
sub remove_fades ($edit) {
	map{ $_->remove } map{ $::Fade::by_index{$_} } $edit->fades->@*;
	$edit->set(fades => []);
}

sub destroy ($edit) {

	# remove object from index hash
	delete $by_index{$edit->n};
	delete $by_name{$edit->edit_name};

	# list edit track WAV files
	my @wavs = values $edit->edit_track->targets->%*;

	#   track removal also takes care of fades # VERIFY
	#	my $fades = $edit->fades;
	#	map{ $::Fade::by_index{$_}->remove } @$fades;

	# remove edit track
	$edit->edit_track->remove;

	my @sister_edits = grep{ 
			$edit->host_track   eq $_->host_track 
		and $edit->host_version == $_->host_version 
	} values %by_index;

	# if we are the last edit, remove all auxiliary tracks/buses
	
	if ( ! @sister_edits ){

		$edit->host_alias_track->remove;

		$edit->version_bus->remove;
		# note: bus->remove will not delete a mix track with WAV files

		# The host may have a version symlinked to a WAV file 
		# belonging to the version mix track. So we remove
		# the track, but not the wav files.

		$edit->version_mix->remove if defined $edit->version_mix;

		$edit->host_bus->remove;
	}
	# remove edit track WAV files if we've reached here
	map{ 
		my $path = ::join_path(::this_wav_dir(), $_);
		::notify("removing $path");
		#unlink $path;
	} @wavs;
}

sub host	 		{ $::tn{$_[0]->host_track} } # top-level mix track, i.e. 'sax'
sub host_bus 		{ $::Bus::by_name{$_[0]->host_track} }  # top-level bus
sub version_mix     { $::tn{$_[0]->edit_root_name} }        # in top-level bus
sub version_bus     { $::Bus::by_name{$_[0]->edit_root_name} } # version-level bus
sub host_alias_track{ $::tn{$_[0]->host_alias} }            # in version_bus
sub edit_track 		{ $::tn{$_[0]->edit_name} }             # in version_bus

# utility routines

}
# -------- Edit routines; Main Namespace ------
{
package ::;
use v5.36; use Carp;
use ::TimelineAdjustment qw(timeline_adjustment);
use Path::Tiny qw(path);
no warnings 'uninitialized';

our (
	%tn,
	%ti,
	%bn,
	$this_track,
	$this_edit,
);
	

# Capture state is temporary; completed points remain available to new-edit.
my ($edit_marking, $edit_prompt_active);

sub edit_marking_active { defined $edit_marking }

sub initialize_edit_points {
    undef $edit_marking;
    $setup->{edit_points} = [];
    delete $setup->{edit_label};
    delete $setup->{edit_host_track};
    delete $setup->{edit_host_version};
}

sub set_edit_points {
    return if $edit_prompt_active;
    return if ::ChainSetup::really_recording();
    initialize_edit_points();
    ::notify('F3: playback start and name; F4: record start, then record end; Esc: stop and offer to exit.');
}

sub mark_play_start ($name = undef) {
    return if $edit_prompt_active;
    if (::ChainSetup::really_recording()) {
        ::throw('Use playback-only mode to mark edit points.');
        return;
    }
    my $host = $this_track;
    my $version = $host->playback_version;
    unless (defined $version) {
        ::throw('Select a track with a playback version first.');
        return;
    }
    my $time = current_timeline_position();
    my $running = $this_engine->started();
    stop_transport();
    set_timeline_position($time);
    $edit_prompt_active = 1;
    my $accept = sub ($label) {
        if (defined $label and length $label) {
            my $full_name = join '-', $host->name, 'v'.$version, $label;
            unless (valid_track_name($label) and valid_track_name($full_name)) {
                return 0;
            }
        }
        $edit_prompt_active = 0;
        if (defined $label) {
            initialize_edit_points();
            $edit_marking = [$host->name, $version];
            $setup->{edit_host_track} = $host->name;
            $setup->{edit_host_version} = $version;
            $setup->{edit_label} = $label if length $label;
            $setup->{edit_points} = [$time];
            ::notify('Marked playback start at '.d1($time).'; F4 sets record start.');
        }
        start_transport() if $running;
        return 1;
    };
    if (defined $name) {
        $edit_prompt_active = 0 unless $accept->($name);
        return;
    }
    my $ok = eval {
        $ui->prompt_for_text('Edit name? ', sub ($label) {
            $ui->prompt_for_text('Edit name? ', __SUB__) unless $accept->($label);
        });
        1;
    };
    unless ($ok) { $edit_prompt_active = 0; die $@ }
}

sub mark_edit_record_point ($index) {
    return if $edit_prompt_active;
    return if ::ChainSetup::really_recording();
    unless ($edit_marking) {
        ::throw('Set playback start with F3 first.');
        return;
    }
    unless ($this_track->name eq $edit_marking->[0]
            and $this_track->playback_version == $edit_marking->[1]) {
        ::throw('Return to the track and version where edit marking started.');
        return;
    }
    my $points = $setup->{edit_points};
    unless (@$points >= $index) {
        ::throw('Set record start first.');
        return;
    }
    my $time = current_timeline_position();
    unless ($index == 1 ? $time >= $points->[0] : $time > $points->[1]) {
        ::throw('Edit points must satisfy playback start <= record start < record end.');
        return;
    }
    splice @$points, $index;
    $points->[$index] = $time;
    if ($index == 2) {
        stop_transport();
        undef $edit_marking;
        ::notify('Edit points complete. Use new-edit to create the edit.');
    } else {
        ::notify('Marked record start at '.d1($time).'; F4 sets record end.');
    }
}
sub mark_rec_start { mark_edit_record_point(1) }
sub mark_rec_end { mark_edit_record_point(2) }
sub mark_edit_record { mark_edit_record_point(@{$setup->{edit_points} // []} >= 2 ? 2 : 1) }

sub cancel_edit_marking {
    return if $edit_prompt_active;
    return unless edit_marking_active();
    stop_transport();
    $edit_prompt_active = 1;
    $ui->prompt_yn('Exit edit-point capture?', 'no', sub ($yes) {
        $edit_prompt_active = 0;
        initialize_edit_points() if $yes;
    });
}

sub transfer_edit_points {
	::throw("Use 'set_edit_points' command to specify edit region"), return
		 unless scalar $setup->{edit_points}->@*;
	my $edit = shift;
	::Mark->new( name => $edit->play_start_name, time => $setup->{edit_points}->[0]);
	::Mark->new( name => $edit->rec_start_name,  time => $setup->{edit_points}->[1]);
	::Mark->new( name => $edit->rec_end_name,    time => $setup->{edit_points}->[2]);
	initialize_edit_points();
}

sub generate_edit_record_setup { # for current edit
	# set edit track to REC
	# set global region start offset
	# set global region length cutoff
	# set regenerate_setup flag
	# insert host track fades
	# mute edit track
	# schedule unmuting at rec-start point - fade-in
	# schedule muting at rec-end point     - fade-out
}

sub new_edit {

	# abort for many different reasons
	
    my $points = $setup->{edit_points};
    unless (ref $points eq 'ARRAY' and @$points == 3
            and not grep { not defined $_ } @$points) {
        ::throw('Mark playback start, record start and record end before new-edit.');
        return;
    }
    unless ($points->[0] <= $points->[1] and $points->[1] < $points->[2]) {
        ::throw('Edit points must satisfy playback start <= record start < record end.');
        return;
    }
    my $name = $this_track->name;
    my $version = $this_track->playback_version;
    if (defined $setup->{edit_host_track}
            and ($name ne $setup->{edit_host_track}
                or $version != $setup->{edit_host_version})) {
        ::throw('These edit points belong to another track or version.');
        return;
    }
    my @existing = values %::Edit::by_index;
    if (grep { $_->edit_name eq $name } @existing) {
        ::throw("$name: editing of edits is not currently allowed.");
        return;
    }
    unless ($this_track->candidate_play
            or ($this_track->candidate_rec and grep { $_->host_track eq $name } @existing)) {
        ::throw("$name: must be in PLAY mode. Edits apply to the current version.");
        return;
    }
    for my $old (@existing) {
        next unless $old->host_track eq $name and $old->host_version == $version;
        if ($points->[1] < $old->rec_end_time and $old->rec_start_time < $points->[2]) {
            ::throw('Recording interval overlaps edit '.$old->n.'.');
            return;
        }
    }
    my $label = $setup->{edit_label};
    my $track_name = join '-', $name, 'v'.$version, ($label // ('edit'.($::Edit::n + 1)));
    return unless valid_track_name($track_name);

	# create edit
	
	my $v = $this_track->playback_version;
	::notify("$name: creating new edit against version $v");
	my $edit = ::Edit->new(
		host_track 		=> $this_track->name,
		host_version	=> $v,
        (defined $label ? (edit_label => $label) : ()),
	);
	$this_track->current_edit->{$v} = $edit->n;
	$this_edit = $edit;
	transfer_edit_points($edit);
	#select_edit($this_edit->n);
	edit_action('preview_edit_in');
}
{my %edit_actions = 
	(
		record_edit => sub { 
			$this_edit->edit_track->set(rw => REC);
			$this_edit->store_fades(std_host_fades(), edit_fades());
		},
		play_edit => sub {
			$this_edit->edit_track->set(rw => PLAY);
			$this_edit->store_fades(std_host_fades(), edit_fades());
		},
		preview_edit_in => sub {
			$this_edit->edit_track->set(rw => OFF);
			$this_edit->store_fades(std_host_fades());
		},
		preview_edit_out => sub {
			$this_edit->edit_track->set(rw => OFF);
			$this_edit->store_fades(reverse_host_fades());
		},
	);

sub edit_action {
	my $action = shift;
	defined $this_edit or ::throw("Please select an edit and try again."), return;
	return unless set_edit_mode();
	$this_edit->host_alias_track->set(rw => PLAY); # all 
	$edit_actions{$action}->();
	request_setup();

#   TODO: looping
# 	my $is_setup = generate_setup(); 
# 	return unless $is_setup;
# 	if ($action !~ /record/){
# 		$mode->{loop_enable}++;
# 		$setup->{loop_endpoints}->@* = (0,$setup->{audio_length} - 0.05);
# 		#  and transport_start()
# 	}
# 	connect_transport(); 
}
}

sub end_edit_mode  	{ 

	# regenerate fades
	
	$mode->{loop_enable} = 0;
	clear_timeline_adjustment();
	$this_track = $this_edit->host if defined $this_edit;
	undef $this_edit;
	request_setup();
}
sub destroy_edit {
    ::throw('No edit selected'), return unless $this_edit;
    my $edit = $this_edit;
    $ui->prompt_yn('Destroy edit "'.$edit->edit_name.'" and its audio files?', 'no', sub ($yes) {
        return unless $yes;
        $edit->destroy;
        end_edit_mode() if defined $this_edit and $this_edit == $edit;
    });
}
sub set_edit_mode {
	return unless edit_mode_conditions();
	$setup->{timeline_adjustment} = {
		type => 'edit',
		timeline_play_start => $this_edit->play_start_time,
		timeline_play_end => $this_edit->play_end_time,
	};
    return 1;
}
sub edit_mode {
	timeline_adjustment_type() eq 'edit' and defined $this_edit
}
sub edit_mode_conditions {        
	defined $this_edit or ::throw('No edit is defined'), return;
	defined $this_edit->play_start_time or ::throw('No edit points defined'), return;
	$this_edit->host_alias_track->candidate_play
		or ::throw('host alias track : ',$this_edit->host_alias,
				" status must be PLAY"), return;

	# the following conditions should never be triggered 
	
	$this_edit->host_alias_track->playback_version == $this_edit->host_version
		or die('host alias track: ',$this_edit->host_alias,
				" must be set to version ",$this_edit->host_version), return
	1;
}
sub reverse_host_fades { host_fades('in','out') }

sub std_host_fades { host_fades('out','in') }

sub host_fades {
	my ($first,$second) = @_;
	::Fade->new(  type => $first,
					mark1 => $this_edit->rec_start_name,
					duration => $config->{edit_crossfade_time},
					relation => 'fade_from_mark',
					track => $this_edit->host_alias,
	), 
	::Fade->new(  type => $second,
					mark1 => $this_edit->rec_end_name,
					duration => $config->{edit_crossfade_time},
					relation => 'fade_from_mark',
					track => $this_edit->host_alias,
	), 
}
sub edit_fades {
	::Fade->new(  type => 'in',
					mark1 => $this_edit->rec_start_name,
					duration => $config->{edit_crossfade_time},
					relation => 'fade_from_mark',
					track => $this_edit->edit_name,
	), 
	::Fade->new(  type => 'out',
					mark1 => $this_edit->rec_end_name,
					duration => $config->{edit_crossfade_time},
					relation => 'fade_from_mark',
					track => $this_edit->edit_name,
	); 
}
sub timeline_play_start_position {
	return unless timeline_adjustment_active();
	$setup->{timeline_adjustment}->{timeline_play_start}
}
sub timeline_play_end_position {
	return unless timeline_adjustment_active();
	$setup->{timeline_adjustment}->{timeline_play_end}
}
sub adjusted_time_from_timeline_position {
	my $timeline_position = shift;
	return $timeline_position unless timeline_adjustment_active();
	$timeline_position - timeline_play_start_position()
}
sub timeline_position_from_adjusted_time {
	my $adjusted_time = shift;
	return $adjusted_time unless timeline_adjustment_active();
	$adjusted_time + timeline_play_start_position()
}
sub adjusted_playback_position_from_timeline_position {
	my $timeline_position = shift;
	my $adjusted_position = adjusted_time_from_timeline_position(
		$timeline_position
	);
	$adjusted_position < 0 ? 0 : $adjusted_position
}
sub timeline_adjustment_active { defined $setup->{timeline_adjustment} }
sub timeline_adjustment_type {
	return '' unless timeline_adjustment_active();
	$setup->{timeline_adjustment}->{type}
}
sub offset_run_positioning_mark {
	return unless is_offset_run_mode();
	$setup->{timeline_adjustment}->{positioning_mark}
}
sub clear_timeline_adjustment { undef $setup->{timeline_adjustment} }
sub timeline_adjustment_args {
	my $track = shift;
	::throw("track is undefined"), return unless $track;
	{
	trackname      	=> $track->name,
	has_region     	=> $track->is_region,
	playat 			=> $track->timeline_position,
	region_start   	=> $track->startpoint,
	region_end 		=> $track->endpoint,
	timeline_play_start => timeline_play_start_position(),
	timeline_play_end   => timeline_play_end_position(),
	wav_length          => $track->wav_length(),
	}
}

sub list_edits {
	my @edit_data =
		map{ s/^---//; s/...\s$//; $_ } 
		map{ $_->dump }
		sort{$a->n <=> $b->n} 
		values %::Edit::by_index;
	::pager(@edit_data);
}
sub explode_track {
	my $track = shift;
	
	# quit if I am already a mix track

	::throw($track->name,": I am already a mix track. I cannot explode!"),return
		if $track->is_mixer;

	my @versions = $track->versions->@*;

	# quit if I have only one version

	::throw($track->name,": Only one version. Skipping."), return
		if scalar @versions == 1;

	$track->activate_bus;

	my $host = $track->name;
	my @names = map{ "$host-v$_"} @versions;
	my @exists = grep{ $::tn{$_} } @names;
	::throw("@exists: tracks already exist. Aborting."), return if @exists;
	my $wav_dir = path(this_wav_dir())->absolute;
	for my $i (@versions){

		# make a track

		my $name = "$host-v$i";
		::Track->new(
			name 	=> $name, 
			rw		=> MON,
			group	=> $host,
		);

		# symlink the WAV file we want

		symlink $track->targets->{$i}, $wav_dir->child("$name.wav")
            or throw("Cannot link $name.wav: $!");


	}
}	

sub select_edit {
	my $n = shift;
	my ($edit) = grep{ $_->n == $n } values %::Edit::by_name;

	# check that conditions are met
	
	::throw("Edit $n not found. Skipping."),return if ! $edit;
 	::throw( qq(Edit $n applies to track "), $edit->host_track, 
 		 qq(" version ), $edit->host_version, ".
This does does not match the current monitor version (",
$edit->host->playback_version,"). 
Set the correct version and try again."), return
	if $edit->host->playback_version != $edit->host_version;

	# select edit
	
	$this_edit = $edit;

	# turn on top-level bus and mix track
	
	$edit->host->activate_bus;

	# turn off all version level buses/mix_tracks
	
	map{ $tn{$_}->set(rw => OFF);  # version mix tracks
	} $this_edit->host_bus->tracks;  # use same name for track/bus

	# turn on what we want
	
	$edit->version_mix->activate_bus;

	$edit->host_alias_track->set(rw => PLAY);

	$edit->edit_track->set(rw => PLAY);
	
	$this_track = $edit->host;
}
sub disable_edits {

	::throw("Please select an edit and try again."), return
		unless defined $this_edit;
	my $edit = $this_edit;

	$edit->host->set(rw => OFF); # XXX or what it was before??

	$edit->version_mix->set( rw => OFF);

	
}
sub merge_edits {
	my $edit = $this_edit;
	::throw("Please select an edit and try again."), return
		unless defined $edit;
	::throw($edit->host_alias, ": track must be PLAY status.  Aborting."), return
		unless $edit->host_alias_track->candidate_play;
	::throw("Use exit_edit_mode and try again."), return if edit_mode();

	# create merge message
	my $v = $edit->host_version;
    my @edits = sort { $a->n <=> $b->n }
        grep { $_->host_track eq $edit->host_track
            and $_->host_version == $v and $_->edit_track->candidate_play }
        values %::Edit::by_index;
    my $msg = 'merges '.$edit->host_track."_$v.wav w/edits ".
        join ' ', map { $_->edit_name.' v'.$_->edit_track->playback_version } @edits;
	# merges mic_1.wav w/mic-v1-edits 1_2 2_1 
	
	::notify($msg);

	# cache at version_mix level
	
	my $output_wav = cache_track($edit->version_mix);
	unless (defined $output_wav) {
		throw("Cannot merge edits: caching produced no audio file.");
		return;
	}

	# promote to host track

	my $new_version = $edit->host->last + 1;		
	add_system_version_comment($edit->host, $new_version, $msg);
	add_system_version_comment($edit->version_mix, $edit->version_mix->last, $msg);
	my $wav_dir = path(this_wav_dir())->absolute;
	my $new_host_wav = $edit->host_track . "_" .  $new_version . ".wav";
	symlink $output_wav, $wav_dir->child($new_host_wav)
        or do { throw("Cannot link $new_host_wav: $!"); return };

	$edit->host->set(version => undef); # default to latest
	$edit->host->{version_comment}{$new_version}{system} = $msg;
	disable_edits();
	$this_track = $edit->host;
	
}
# offset recording

# Note that although we use ->adjusted_* methods, all are
# executed outside of edit mode, so we get unadjusted values.

sub setup_length {
	my $setup_length;
	map{  my $l = $_->adjusted_timeline_endpoint; $setup_length = $l if $l > $setup_length }
	grep{ $_-> play }
	::ChainSetup::engine_tracks();
	$setup_length
}
sub set_offset_run_mark {
	::throw("This function not available in edit mode.  Aborting."), 
		return if edit_mode();
	my $markname = shift;
	my $timeline_play_start = $::Mark::by_name{$markname}->time;

	# setup_length must be calculated on the unadjusted timeline,
	# including when an existing offset run is being replaced.
	my $timeline_play_end;
	{
		local $setup->{timeline_adjustment};
		$timeline_play_end = setup_length();
	}

	$setup->{timeline_adjustment} = {
		type => 'offset_run',
		timeline_play_start => $timeline_play_start,
		timeline_play_end => $timeline_play_end,
		positioning_mark => $markname,
	};
	undef $this_edit;
	request_setup();
}
sub disable_offset_run_mode {
	return unless is_offset_run_mode();
	clear_timeline_adjustment();
	::request_setup();
}
sub is_offset_run_mode { timeline_adjustment_type() eq 'offset_run' }
	
sub select_edit_track {
	my $track_selector_method = shift;
	::throw("You need to select an edit first (list_edits, select_edit)\n"),
		return unless defined $this_edit;
	$this_track = $this_edit->$track_selector_method; 
	nama_cmd('show_track');
}

} # end package

1;

__END__
