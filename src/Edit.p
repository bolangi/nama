{
package ::Edit;
use ::Globals qw(:singletons);

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
	%by_index = ();
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
	$by_index{ $self->n } = $self;

	#print "self class: $class, self type: ", ref $self, $/;

	my $name = $self->host_track;
	my $host = $::tn{$name};
	confess( ::project_dir().": missing host_track".  $::this_track->dump. $self->dump. ::process_command("dumpa")) if !$host;

# Routing:
#
#    sax-v5-original --+
#                      |
#    sax-v5-edit1 -----+--- sax-v5 (bus/track) --- sax (bus/track) ----- 


	# prepare top-level bus and mix track
	
	$host->busify;     # i.e. sax (bus/track)
	
	# create the version-level bus and mix track
	# i.e. sax-v5 (bus/track)

	# (maybe it already exists)
	
	my $version_mix = ::Track->new(

		name 		=> $self->edit_root_name, # i.e. sax-v5
	#	rw			=> 'REC',                 # set by ->busify
		source_type => 'bus',
		source_id 	=> 'bus',
		width		=> 2,                     # default to stereo 
	#	rec_defeat 	=> 1,                     # set by ->busify
		group   	=> $self->host_track,     # i.e. sax
		hide		=> 1,
	); 
	$version_mix->busify;

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
			hide 	=> 1,
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
		hide		=> 1,
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
sub remove_fades {
	my $edit = shift;
	map{ $_->remove } map{ $::Fade::by_index{$_} } @{$edit->fades};
	$edit->set(fades => []);
}

sub destroy {
	my $edit = shift;

	# remove object from index hash
	delete $by_index{$edit->n};
	delete $by_name{$edit->edit_name};

	# list edit track WAV files
	my @wavs = values %{$edit->edit_track->targets};

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
		say "removing $path";
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
use Modern::Perl; use Carp;
no warnings 'uninitialized';

our (
	%tn,
	%ti,
	%bn,
	$this_track,
	$this_edit,
);
	

sub detect_keystroke_p {
	$engine->{events}->{stdin} = AE::io(*STDIN, 0, sub {
		&{$text->{term_attribs}->{'callback_read_char'}}();
		
		abort_set_edit_points(), return
			if $text->{term_attribs}->{line_buffer} eq "q"
			or $text->{term_attribs}->{line_buffer} eq "Q";

		if (   $text->{term_attribs}->{line_buffer} eq "p"
			or $text->{term_attribs}->{line_buffer} eq "P"){ get_edit_mark()}
		else{ reset_input_line() }
	});
}

sub reset_input_line {
	$text->{term_attribs}->{line_buffer} = q();
	$text->{term_attribs}->{point} 		= 0;
	$text->{term_attribs}->{end}   		= 0;
}


{ my $p;
  my @_edit_points; 
  my @names = qw(dummy play-start rec-start rec-end);

sub initialize_edit_points {
	$p = 0;
    @_edit_points = ();
}
sub abort_set_edit_points {
	say "...Aborting!";
	reset_input_line();
	eval_iam('stop');
	initialize_edit_points();
	detect_spacebar();
}

sub get_edit_mark {
	$p++;
	if($p <= 3){  # record mark
		my $pos = eval_iam('getpos');
		push @_edit_points, $pos;
		say " got $names[$p] position ".d1($pos);
		reset_input_line();
		if( $p == 3){ complete_edit_points() }
		else{
			$text->{term}->stuff_char(10);
			&{$text->{term_attribs}->{'callback_read_char'}}();
		}
	}
}
sub complete_edit_points {
	@{$setup->{edit_points}} = @_edit_points; # save to global
	eval_iam('stop');
	say "\nEngine is stopped\n";
	detect_spacebar();
	print prompt(), " ";
}
}
sub set_edit_points {
	$tn{$this_edit->edit_name}->set(rw => 'OFF') if defined $this_edit;
	say("You must use a playback-only mode to setup edit marks. Aborting"), 
		return 1 if ::ChainSetup::really_recording();
	say("You need stop the engine first. Aborting"), 
		return 1 if engine_running();
	say "Ready to set edit points!";
	sleeper(0.2);
	say q(Press the "P" key three times to mark positions for:
    + play-start
    + record-start
    + record-end

	say q(Press "Q" to quit.)

Engine will start in 2 seconds.);
	initialize_edit_points();
 	$engine->{events}->{set_edit_points} = AE::timer(2, 0, 
	sub {
		reset_input_line();
		detect_keystroke_p();
		eval_iam('start');
		say "\n\nEngine is running\n";
		print prompt();
	});
}
sub transfer_edit_points {
	say("Use 'set_edit_points' command to specify edit region"), return
		 unless scalar @{$setup->{edit_points}};
	my $edit = shift;
	::Mark->new( name => $edit->play_start_name, time => $setup->{edit_points}->[0]);
	::Mark->new( name => $edit->rec_start_name,  time => $setup->{edit_points}->[1]);
	::Mark->new( name => $edit->rec_end_name,    time => $setup->{edit_points}->[2]);
	@{$setup->{edit_points}} = ();
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
	
	say("You must use 'set_edit_points' before creating a new edit. Aborting."),
		return unless @{$setup->{edit_points}};
	my $overlap = grep { 
		my $fail;
		my $rst = $_->rec_start_time;
		my $ret = $_->rec_end_time;
		my $nst = $setup->{edit_points}->[1];
		my $net = $setup->{edit_points}->[2];
		my $rst1 = d1($rst);
		my $ret1 = d1($ret);
		my $nst1 = d1($nst);
		my $net1 = d1($net);
		say("New rec-start time $nst1 conflicts with Edit ",
			$_->n, ": $rst1 < $nst1 < $ret1"), $fail++
			if $rst < $nst and $nst < $ret;
		say("New rec-end time $net1 conflicts with Edit ",
			$_->n, ": $rst1 < $net1 < $ret1"), $fail++
			if $rst < $net and $net < $ret;
		say("New rec interval $nst1 - $net1 conflicts with Edit ",
			$_->n, ": $rst1 - $ret1"), $fail++
			if $nst < $rst and $ret < $net;
		$fail
	} grep{ $_->host_track eq $this_track->name} 
		values %Audio::Nama::Edit::by_name;
	say("Aborting."), return if $overlap;
	my $name = $this_track->name;
	my $editre = qr($name-v\d+-edit\d+);
	say("$name: editing of edits is not currently allowed."),
		return if $name =~ /-v\d+-edit\d+/;
	say("$name: must be in MON mode.
Edits will be applied against current version"), 
		return unless $this_track->rec_status eq 'MON' 
			or $this_track->rec_status eq 'REC' and
			grep{ /$editre/ } keys %::Track::by_name;

	# create edit
	
	my $v = $this_track->monitor_version;
	say "$name: creating new edit against version $v";
	my $edit = ::Edit->new(
		host_track 		=> $this_track->name,
		host_version	=> $v,
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
			$this_edit->edit_track->set(rw => 'REC');
			$this_edit->store_fades(std_host_fades(), edit_fades());
		},
		play_edit => sub {
			$this_edit->edit_track->set(rw => 'MON');
			$this_edit->store_fades(std_host_fades(), edit_fades());
		},
		preview_edit_in => sub {
			$this_edit->edit_track->set(rw => 'OFF');
			$this_edit->store_fades(std_host_fades());
		},
		preview_edit_out => sub {
			$this_edit->edit_track->set(rw => 'OFF');
			$this_edit->store_fades(reverse_host_fades());
		},
	);

sub edit_action {
	my $action = shift;
	defined $this_edit or say("Please select an edit and try again."), return;
	set_edit_mode();
	$this_edit->host_alias_track->set(rw => 'MON'); # all 
	$edit_actions{$action}->();
	request_setup();

#   TODO: looping
# 	my $is_setup = generate_setup(); 
# 	return unless $is_setup;
# 	if ($action !~ /record/){
# 		$mode->{loop_enable}++;
# 		@{$setup->{loop_endpoints}} = (0,$setup->{audio_length} - 0.05);
# 		#  and transport_start()
# 	}
# 	connect_transport(); 
}
}

sub end_edit_mode  	{ 

	# regenerate fades
	
	$mode->{offset_run} = 0; 
	$mode->{loop_enable} = 0;
	offset_run_mode(0);	
	$this_track = $this_edit->host if defined $this_edit;
	undef $this_edit;
	request_setup();
}
sub destroy_edit {
	say("no edit selected"), return unless $this_edit;
	my $reply = $text->{term}->readline('destroy edit "'.$this_edit->edit_name.
		qq(" and all its WAV files?? [n] ));
	if ( $reply =~ /y/i ){
		say "permanently removing edit";
		$this_edit->destroy;
	}
	$text->{term}->remove_history($text->{term}->where_history);
	$this_track = $this_edit->host;
	end_edit_mode();
}
sub set_edit_mode 	{ $mode->{offset_run} = edit_mode_conditions() ?  1 : 0 }
sub edit_mode		{ $mode->{offset_run} and defined $this_edit}
sub edit_mode_conditions {        
	defined $this_edit or say('No edit is defined'), return;
	defined $this_edit->play_start_time or say('No edit points defined'), return;
	$this_edit->host_alias_track->rec_status eq 'MON'
		or say('host alias track : ',$this_edit->host_alias,
				" status must be MON"), return;

	# the following conditions should never be triggered 
	
	$this_edit->host_alias_track->monitor_version == $this_edit->host_version
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

### edit region computations

{
# use internal lexical values for the computations

# track values
my( $trackname, $playat, $region_start, $region_end, $setup_length);

# edit values
my( $edit_play_start, $edit_play_end);

# dispatch table
my( %playat, %region_start, %region_end);

# test variables
# my ($index, $new_playat, $new_region_start, $new_region_end);



%region_start = (
    out_of_bounds_near				=> sub{ "*" },
    out_of_bounds_far				=> sub{ "*" },	

	play_start_during_playat_delay	=> sub {$region_start },
	no_region_play_start_during_playat_delay => sub { 0 },

	play_start_within_region 
				=> sub {$region_start + $edit_play_start - $playat },
	no_region_play_start_after_playat_delay
				=> sub {$region_start + $edit_play_start - $playat },
);
%playat = (
    out_of_bounds_near				=> sub{ "*" },
    out_of_bounds_far				=> sub{ "*" },	

	play_start_during_playat_delay	=> sub{ $playat - $edit_play_start },
	no_region_play_start_during_playat_delay
									=> sub{ $playat - $edit_play_start },

	play_start_within_region   				=> sub{ 0 },
	no_region_play_start_after_playat_delay => sub{ 0 },

);
%region_end = (
    out_of_bounds_near				=> sub{ "*" },
    out_of_bounds_far				=> sub{ "*" },	

	play_start_during_playat_delay	
		=> sub { $region_start + $edit_play_end - $playat },
	no_region_play_start_during_playat_delay 
		=> sub {                 $edit_play_end - $playat },

	play_start_within_region 
		=> sub { $region_start + $edit_play_end - $playat },
	no_region_play_start_after_playat_delay
		=> sub {                 $edit_play_end - $playat },
);

sub new_playat       {       $playat{edit_case()}->() };
sub new_region_start { $region_start{edit_case()}->() };
sub new_region_end   
	{   
		my $end = $region_end{edit_case()}->();
		return $end if $end eq '*';
		$end < $setup_length ? $end : $setup_length
	};
# the following value will always allow enough time
# to record the edit. it may be longer than the 
# actual WAV file in some cases. (I doubt that
# will be a problem.)

sub edit_case {

	# logic for no-region case
	
    if ( ! $region_start and ! $region_end  )
	{
		if( $edit_play_end < $playat)
			{ "out_of_bounds_near" }
		elsif( $edit_play_start > $playat + $setup_length)
			{ "out_of_bounds_far" }
		elsif( $edit_play_start >= $playat)
			{"no_region_play_start_after_playat_delay"}
		elsif( $edit_play_start < $playat and $edit_play_end > $playat )
			{ "no_region_play_start_during_playat_delay"}
	} 
	# logic for region present case
	
	elsif ( defined $region_start and defined $region_end )
	{ 
		if ( $edit_play_end < $playat)
			{ "out_of_bounds_near" }
		elsif ( $edit_play_start > $playat + $region_end - $region_start)
			{ "out_of_bounds_far" }
		elsif ( $edit_play_start >= $playat)
			{ "play_start_within_region"}
		elsif ( $edit_play_start < $playat and $playat < $edit_play_end)
			{ "play_start_during_playat_delay"}
		else {carp "$trackname: fell through if-then"}
	}
	else { carp "$trackname: improperly defined region" }
}

sub set_edit_vars {
	my $track = shift;
	$trackname      = $track->name;
	$playat 		= $track->playat_time;
	$region_start   = $track->region_start_time;
	$region_end 	= $track->region_end_time;
	$edit_play_start= play_start_time();
	$edit_play_end	= play_end_time();
	$setup_length 		= wav_length($track->full_path);
}
sub play_start_time {
	defined $this_edit 
		? $this_edit->play_start_time 
		: $setup->{offset_run}->{start_time} # zero unless offset run mode
}
sub play_end_time {
	defined $this_edit 
		? $this_edit->play_end_time 
		: $setup->{offset_run}->{end_time}   # undef unless offset run mode
}
sub set_edit_vars_testing {
	($playat, $region_start, $region_end, $edit_play_start, $edit_play_end, $setup_length) = @_;
}
}

sub list_edits {
	my @edit_data =
		map{ s/^---//; s/...\s$//; $_ } 
		map{ $_->dump }
		sort{$a->n <=> $b->n} 
		values %::Edit::by_index;
	pager(@edit_data);
}
sub explode_track {
	my $track = shift;
	
	# quit if I am already a mix track

	say($track->name,": I am already a mix track. I cannot explode!"),return
		if $track->is_mix_track;

	my @versions = @{ $track->versions };

	# quit if I have only one version

	say($track->name,": Only one version. Skipping."), return
		if scalar @versions == 1;

	$track->busify;

	my $host = $track->name;
	my @names = map{ "$host-v$_"} @versions;
	my @exists = grep{ $::tn{$_} } @names;
	say("@exists: tracks already exist. Aborting."), return if @exists;
	my $current = cwd;
	chdir this_wav_dir();
	for my $i (@versions){

		# make a track

		my $name = "$host-v$i";
		::Track->new(
			name 	=> $name, 
			rw		=> 'MON',
			group	=> $host,
		);

		# symlink the WAV file we want

		symlink $track->targets->{$i}, "$name.wav";


	}
	chdir $current;
}	

sub select_edit {
	my $n = shift;
	my ($edit) = grep{ $_->n == $n } values %::Edit::by_name;

	# check that conditions are met
	
	say("Edit $n not found. Skipping."),return if ! $edit;
 	say( qq(Edit $n applies to track "), $edit->host_track, 
 		 qq(" version ), $edit->host_version, ".
This does does not match the current monitor version (",
$edit->host->monitor_version,"). 
Set the correct version and try again."), return
	if $edit->host->monitor_version != $edit->host_version;

	# select edit
	
	$this_edit = $edit;

	# turn on top-level bus and mix track
	
	$edit->host_bus->set(rw => 'REC');

	$edit->host->busify;

	# turn off all version level buses/mix_tracks
	
	map{ $tn{$_}->set(rw => 'OFF');  # version mix tracks
	      $bn{$_}->set(rw => 'OFF'); # version buses
	} $this_edit->host_bus->tracks;  # use same name for track/bus

	# turn on what we want
	
	$edit->version_bus->set(rw => 'REC');

	$edit->version_mix->busify;

	$edit->host_alias_track->set(rw => 'MON');

	$edit->edit_track->set(rw => 'MON');
	
	$this_track = $edit->host;
}
sub disable_edits {

	say("Please select an edit and try again."), return
		unless defined $this_edit;
	my $edit = $this_edit;

	$edit->host_bus->set( rw => 'OFF');

	$edit->version_bus->set( rw => 'OFF');

	# reset host track
	
	$edit->host->unbusify;
	
}
sub merge_edits {
	my $edit = $this_edit;
	say("Please select an edit and try again."), return
		unless defined $edit;
	say($edit->host_alias, ": track must be MON status.  Aborting."), return
		unless $edit->host_alias_track->rec_status eq 'MON';
	say("Use exit_edit_mode and try again."), return if edit_mode();

	# create merge message
	my $v = $edit->host_version;
	my %edits = 
		map{ my ($edit) = $tn{$_}->name =~ /edit(\d+)$/;
			 my $ver  = $tn{$_}->monitor_version;
			 $edit => $ver
		} grep{ $tn{$_}->name =~ /edit\d+$/ and $tn{$_}->rec_status eq 'MON'} 
		$edit->version_bus->tracks; 
	my $msg = "merges ".$edit->host_track."_$v.wav w/edits ".
		join " ",map{$_."v$edits{$_}"} sort{$a<=>$b} keys %edits;
	# merges mic_1.wav w/mic-v1-edits 1_2 2_1 
	
	say $msg;

	# cache at version_mix level
	
	my $output_wav = cache_track($edit->version_mix);

	# promote to host track

	my $new_version = $edit->host->last + 1;		
	add_system_version_comment($edit->host, $new_version, $msg);
	add_system_version_comment($edit->version_mix, $edit->version_mix->last, $msg);
	my $old = cwd();
	chdir this_wav_dir();
	my $new_host_wav = $edit->host_track . "_" .  $new_version . ".wav";
	symlink $output_wav, $new_host_wav;

	$edit->host->set(version => undef); # default to latest
	$edit->host->{version_comment}{$new_version}{system} = $msg;
	chdir $old;
	disable_edits();
	$this_track = $edit->host;
	
}
# offset recording

# Note that although we use ->adjusted_* methods, all are
# executed outside of edit mode, so we get unadjusted values.

sub setup_length {
	my $setup_length;
	map{  my $l = $_->adjusted_length; $setup_length = $l if $l > $setup_length }
	grep{ $_-> rec_status eq 'MON' }
	::ChainSetup::engine_tracks();
	$setup_length
}
sub offset_run {
	say("This function not available in edit mode.  Aborting."), 
		return if edit_mode();
	my $markname = shift;
	
	$setup->{offset_run}->{start_time} = $::Mark::by_name{$markname}->time;
	$setup->{offset_run}->{end_time}   = setup_length();
	$setup->{offset_run}->{mark} = $markname;
	offset_run_mode(1);
	request_setup();
}
sub clear_offset_run_vars {
	$setup->{offset_run}->{start_time} = 0;
	$setup->{offset_run}->{end_time}   = undef;
	$setup->{offset_run}->{mark} 		   = undef;
}
sub offset_run_mode {
	my $set = shift;
	if ($set == 1){
		undef $this_edit; 
		$mode->{offset_run}++
	} elsif ($set == 0) {
			undef $mode->{offset_run};
			clear_offset_run_vars();
			::request_setup();
	}
	$mode->{offset_run} and ! defined $this_edit
}
	
sub select_edit_track {
	my $track_selector_method = shift;
	print("You need to select an edit first (list_edits, select_edit)\n"),
		return unless defined $this_edit;
	$this_track = $this_edit->$track_selector_method; 
	process_command('show_track');
}

} # end package

1;

__END__
