# ---------- Track -----------
#
package ::;
{
package ::Track;
use Role::Tiny::With;
with '::Wav';
with '::WavModify';
with '::TrackRegion';
with '::TrackSetIO';
with '::TrackComment';
with '::TrackEffect';
use ::Globals qw(:all);
use ::Log qw(logpkg logsub);
use ::Effect  qw(fxn);
use List::MoreUtils qw(first_index);
use Try::Tiny;
use Modern::Perl;
use Carp qw(carp cluck croak);
use File::Copy qw(copy);
use File::Slurp;
use Memoize qw(memoize unmemoize);
no warnings qw(uninitialized redefine);
our $VERSION = 1.0;

use ::Util qw(freq input_node dest_type dest_string join_path);
use ::Assign qw(json_out);
use vars qw($n %by_name @by_index %track_names %by_index);
use ::Object qw(
[% qx(./strip_all ./track_fields) %]
);

# Note that ->vol return the effect_id 
# ->old_volume_level is the level saved before muting
# ->old_pan_level is the level saved before pan full right/left
# commands

initialize();

### class subroutines



sub initialize {
	$n = 0; 	# incrementing numeric key
	%by_index = ();	# return ref to Track by numeric key
	%by_name = ();	# return ref to Track by name
	%track_names = (); 
}

sub idx { # return first free track index
	my $n = 0;
	while (++$n){
		return $n if not $by_index{$n}
	}
}
sub new {
	# returns a reference to an object 
	#
	# tracks are indexed by:
	# (1) name and 
	# (2) by an assigned index that is used as chain_id
	#     the index may be supplied as a parameter
	#
	# 

	my $class = shift;
	my %vals = @_;
	my $novol = delete $vals{novol};
	my $nopan = delete $vals{nopan};
	my $restore = delete $vals{restore};
	say "restoring track $vals{name}" if $restore;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	
	# silently return if track already exists
	
	return if $by_name{$vals{name}};

	my $n = $vals{n} || idx(); 
	my $object = bless { 


		## 		defaults ##
					class	=> $class,
					name 	=> "Audio_$n", 
					group	=> 'Main', 
					n    	=> $n,
					ops     => [],
					width => 1,
					vol  	=> undef,
					pan 	=> undef,

					modifiers 		=> q(), # start, reverse, audioloop, playat
					looping 		=> undef, # do we repeat our sound sample
					source_type 	=> q(soundcard),
					source_id   	=> "1",
					send_type 		=> undef,
					send_id   		=> undef,
					old_vol_level	=> undef,

					@_ 			}, $class;

	$track_names{$vals{name}}++;
	$by_index{$n} = $object;
	$by_name{ $object->name } = $object;
	::add_pan_control($n) unless $nopan or $restore;
	::add_volume_control($n) unless $novol or $restore;

	$::this_track = $object;
	$::ui->track_gui($object->n) unless $object->hide;
	logpkg('debug',$object->name, ": ","newly created track",$/,json_out($object->as_hash));
	$object;
}


### object methods

# TODO these conditional clauses should be separated
# into classes 



# if you belong to a bus with an opinion, go that way
sub engine_group {
	my $track = shift;
	my $bus = $bn{$track->group};
	$bus->engine_group || $track->{engine_group} || 'Nama'
}
sub engine {
	my $track = shift;
	$en{$track->engine_group}
}
sub rec_status {
#	logsub("&rec_status");
	my $track = shift;
	
	#my $source_id = $track->source_id;
	my $monitor_version = $track->monitor_version;

	my $bus = $bn{$track->group};
	#logpkg('debug', join " ", "bus:",$bus->name, $bus->rw);
	logpkg('debug', "track: $track->{name}, source: $track->{source_id}, monitor version: $monitor_version");
	#logpkg('debug', "track: ", $track->name, ", source: ",
	#	$track->source_id, ", monitor version: $monitor_version");

	# first, check for conditions resulting in status OFF

	if ( $bus->rw eq OFF
		or $track->rw eq OFF
		or $mode->doodle and ! $mode->eager and $track->rw eq REC and 
			$setup->{tracks_with_duplicate_inputs}->{$track->name}
		or $track->engine_group ne $::this_engine->name
	){ 	return			  OFF }

	# having reached here, we know $bus->rw and $track->rw are REC or PLAY
	# so the result will be REC or PLAY if conditions are met

	# second, set REC status if possible
	
	if( $track->rw eq REC){

		my $source_type = $track->source_type;
		if ($source_type eq 'track' or $source_type eq 'loop'){ return REC }
		elsif ($source_type eq 'jack_client'){

				# we expect an existing JACK client that
				# *outputs* a signal for our track input
				
				::jack_client_array($track->source_id,'output')
					?  return REC
					:  return OFF
			}
		elsif ($source_type eq 'jack_manual'){ return REC }
		elsif ($source_type eq 'jack_ports_list'){ return REC }
		elsif ($source_type eq 'null')	{ return REC }
		elsif ($source_type eq 'rtnull')	{ return REC }
		elsif ($source_type eq 'soundcard'){ return REC }
		elsif ($source_type eq 'bus')	{ return REC } # maybe $track->rw ??
		else { return OFF }
	}
	elsif( $track->rw eq MON){ MON }

	# set PLAY status if possible
	
	else { 			maybe_monitor($monitor_version)

	}
}
sub rec_status_display {
	my $track = shift;
	my $rs = $track->rec_status;
	my $status;
	$status .= $rs;
	$status .= ' v'.$track->current_version if $rs eq REC;
	$status
}
sub snapshot {
	my $track = shift;
	my $fields = shift;
	my %snap; 
	my $i = 0;
	for(@$fields){
		$snap{$_} = $track->$_;
	}
	\%snap;
}


# create an edge representing sound source

sub input_path { 

	my $track = shift;

	# the corresponding bus handles input routing for mix tracks
	
	# bus mix tracks don't usually need to be connected
	return() if $track->is_mix_track and $track->rec_status ne PLAY;

	# the track may route to:
	# + another track
	# + an external source (soundcard or JACK client)
	# + a WAV file

	if($track->source_type eq 'track'){ ($track->source_id, $track->name) } 

	elsif($track->rec_status =~ /REC|MON/){ 
		(input_node($track->source_type), $track->name) } 

	elsif($track->rec_status eq PLAY and ! $mode->doodle){
		('wav_in', $track->name) 
	}
}


sub has_insert  { $_[0]->prefader_insert or $_[0]->postfader_insert }

sub prefader_insert { ::Insert::get_id($_[0],'pre') }
sub postfader_insert { ::Insert::get_id($_[0],'post') }
sub inserts {  [  # return array ref
					map{ $::Insert::by_index{$_} }grep{$_} 
					map{ ::Insert::get_id($_[0],$_)} qw(pre post) 
				]
}

# remove track object and all effects

sub remove {
	my $track = shift;
	my $n = $track->n;
	$ui->remove_track_gui($n); 
	# remove corresponding fades
	map{ $_->remove } grep { $_->track eq $track->name } values %::Fade::by_index;
	# remove effects
 	map{ ::remove_effect($_) } @{ $track->ops };
 	delete $by_index{$n};
 	delete $by_name{$track->name};
}

sub soundcard_channel { $_[0] // 1 }


# Operations performed by track objects
sub wav_length {
	my $track = shift;
	::wav_length($track->full_path)
}
sub wav_format{
	my $track = shift;
	::wav_format($track->full_path)
}

	
sub mute {
	
	my $track = shift;
	my $nofade = shift;

	# do nothing if track is already muted
	return if defined $track->old_vol_level();

	# do nothing if track has no volume operator
	my $vol = $track->vol_o;
	return unless $vol;

	# store vol level for unmute
	$track->set(old_vol_level => $vol->params->[0]);
	
	$nofade 
		? $vol->_modify_effect(1, $vol->mute_level)
		: $vol->fadeout
}
sub unmute {
	my $track = shift;
	my $nofade = shift;

	# do nothing if we are not muted
	return if ! defined $track->old_vol_level;

	$nofade
		? $track->vol_o->_modify_effect(1, $track->old_vol_level)
		: $track->vol_o->fadein($track->old_vol_level);

	$track->set(old_vol_level => undef);
}
sub import_audio  { 
	my $track = shift;
	::throw($track->name.": Cannot import audio to system track"), 
		return if ! $track->is_user_track;
	my ($path, $frequency) = @_; 
	$path = ::expand_tilde($path);
	my $version  = $track->last + 1;
	if ( ! -r $path ){
		::throw("$path: non-existent or unreadable file. No action.\n");
		return;
	}
	my ($depth,$width,$freq) = split ',', ::wav_format($path);
	::pager_newline("format: ", ::wav_format($path));
	$frequency ||= $freq;
	if ( ! $frequency ){
		::throw("Cannot detect sample rate of $path. Skipping.",
		"Maybe 'import_audio <path> <frequency>' will help.");
		return 
	}
	my $desired_frequency = freq( $config->{raw_to_disk_format} );
	my $destination = join_path(::this_wav_dir(),$track->name."_$version.wav");
	if ( $frequency == $desired_frequency and $path =~ /.wav$/i){
		::pager_newline("copying $path to $destination");
		copy($path, $destination) or die "copy failed: $!";
	} else {	
		my $format = ::signal_format($config->{raw_to_disk_format}, $width);
		::pager_newline("importing $path as $destination, converting to $format");
		::teardown_engine();
		my $ecs = qq(-f:$format -i:resample-hq,$frequency,"$path" -o:$destination);
		my $path = join_path(::project_dir()."convert.ecs");
		write_file($path, $ecs);
		::load_ecs($path) or ::throw("$path: load failed, aborting"), return;
		::eval_iam('start');
		::sleeper(0.2); sleep 1 while ::engine_running();
	} 
	::restart_wav_memoize() if $config->{opts}->{R}; # usually handled by reconfigure_engine() 
}

sub port_name { $_[0]->target || $_[0]->name } 
sub jack_manual_port {
	my ($track, $direction) = @_;
	$track->port_name . ($direction =~ /source|input/ ? '_in' : '_out');
}

sub bus_tree { # for solo function to work in sub buses
	my $track = shift;
	my $mix = $track->group;
	return if $mix eq 'Main';
	($mix, $tn{$mix}->bus_tree);
}

sub version_has_edits { 
	my ($track) = @_;
	grep
		{ 		$_->host_track eq $track->name
     		and $_->host_version == $track->monitor_version
		} values %::Edit::by_name;
}	
# current operator and current parameter for the track
sub op { $project->{current_op}->{$_[0]->name} //= $_[0]->{ops}->[-1] }

sub param { $project->{current_param}->{$_[0]->op} //= 1 }

sub stepsize {
	$project->{current_stepsize}->{$_[0]->op}->[$_[0]->param] //= 0.01 
	# TODO use hint if available
}
sub pos {
	my $track = shift;
	first_index{$_ eq $track->op} @{$track->ops};
}

sub set_track_class {
	my ($track, $class) = @_;
	bless $track, $class;
	$track->set(class => $class);
}
sub activate_bus {
	my $track = shift;
	::add_bus($track->name) unless $track->is_system_track;
}
sub deactivate_bus {
	my $track = shift;
	return if $track->is_system_track;
	$track->set( rw => PLAY);
}

sub shifted_length {
	my $track = shift;
	my $setup_length;
	if ($track->region_start){
		$setup_length = 	$track->shifted_region_end_time
				  - $track->shifted_region_start_time
	} else {
		$setup_length = 	$track->wav_length;
	}
	$setup_length += $track->shifted_playat_time;
}

# Modified from Object.p to save class
# should this be used in other classes?
sub as_hash {
	my $self = shift;
	my $class = ref $self;
	bless $self, 'HASH'; # easy magic
	my %guts = %{ $self };
	$guts{class} = $class; # make sure we save the correct class name
	bless $self, $class; # restore
	return \%guts;
}
sub latency_offset {
	my $track = shift;
	no warnings 'uninitialized';
	$setup->{latency}->{sibling}->{$track->name} 
		- $setup->{latency}->{track}->{$track->name}->{total};
}


sub input_object {
	my $track = shift;
	$::IO::by_name{$track->name}->{input}
}
sub output_object {
	my $track = shift;
	$::IO::by_name{$track->name}->{output}
}
sub capture_latency {
	my $track = shift;
	my $io = $track->input_object;
	return $io->capture_latency if ref $io;
}
sub playback_latency {
	my $track = shift;
	my $io = $track->input_object;
	return $io->playback_latency if ref $io;
}
sub sibling_latency {
	my $track = shift;
	$setup->{latency}->{sibling}->{$track->name}
}
sub sibling_count {
	my $track = shift;
	$setup->{latency}->{sibling_count}->{$track->name}
}

sub rec_setup_script { 
	my $track = shift;
	join_path(::project_dir(), $track->name."-rec-setup.sh")
}
sub rec_cleanup_script { 
	my $track = shift;
	join_path(::project_dir(), $track->name."-rec-cleanup.sh")
}
sub is_region { defined $_[0]->{region_start} }

sub current_edit { $_[0]->{current_edit}//={} }
sub is_mix_track {
	my $track = shift;
	($bn{$track->name} or $track->name eq 'Master') and $track->rw eq MON
}
sub bus { $bn{$_[0]->group} }

{ my %system_track = map{ $_, 1} qw( Master Mixdown Eq Low
Mid High Boost );
sub is_user_track { ! $system_track{$_[0]->name} }
sub is_system_track { $system_track{$_[0]->name} } 
}
sub is_comment {
	my $self = shift;
	$::project->{track_comments}->{$self->name}	
}
sub is_version_comment {
	my $self = shift;
	my $version = shift;
	my $comments = $project->{track_version_comments}->{$self->name}->{$version};
	$comments and $comments->{user}
}
} # end package


# subclasses


{
package ::SimpleTrack; # used for Master track
use ::Globals qw(:all);
use Modern::Perl; use Carp; use ::Log qw(logpkg);
use SUPER;
no warnings qw(uninitialized redefine);
our @ISA = '::Track';
sub rec_status {
	my $track = shift;
 	$track->rw ne OFF ? MON : OFF 
}
sub destination {
	my $track = shift; 
	return 'Mixdown' if $tn{Mixdown}->rec_status eq REC;
	return $track->SUPER() if $track->rec_status ne OFF
}
#sub rec_status_display { $_[0]->rw ne OFF ? PLAY : OFF }
sub activate_bus {}
sub deactivate_bus {}
}
{
package ::MasteringTrack; # used for mastering chains 
use ::Globals qw(:all);
use Modern::Perl; use ::Log qw(logpkg);
no warnings qw(uninitialized redefine);
our @ISA = '::SimpleTrack';

sub rec_status{
	my $track = shift;
 	return OFF if $track->engine_group ne $this_engine->name;
	$mode->{mastering} ? MON :  OFF;
}
sub source_status {}
sub group_last {0}
sub version {0}
}
{
package ::EarTrack; # for submix helper tracks
use ::Globals qw(:all);
use ::Util qw(dest_string);
use Modern::Perl; use ::Log qw(logpkg);
use SUPER;
no warnings qw(uninitialized redefine);
our @ISA = '::SlaveTrack';
sub destination {
	my $track = shift;
	my $bus = $track->bus;
	dest_string($bus->send_type,$bus->send_id, $track->width);
}
sub source_status { $_[0]->target }
sub rec_status { $_[0]->{rw} }
sub width { $_[0]->{width} }
}
{
package ::SlaveTrack; # for instrument monitor bus
use ::Globals qw(:all);
use Modern::Perl; use ::Log qw(logpkg);
no warnings qw(uninitialized redefine);
our @ISA = '::Track';
sub width { $tn{$_[0]->target}->width }
sub rec_status { $tn{$_[0]->target}->rec_status }
sub full_path { $tn{$_[0]->target}->full_path} 
sub monitor_version { $tn{$_[0]->target}->monitor_version} 
sub source_type { $tn{$_[0]->target}->source_type}
sub source_id { $tn{$_[0]->target}->source_id}
sub source_status { $tn{$_[0]->target}->source_status }
sub send_type { $tn{$_[0]->target}->send_type}
sub send_id { $tn{$_[0]->target}->send_id}
sub dir { $tn{$_[0]->target}->dir }
}
{
package ::BoostTrack; 
#
# this subclass, intended for the single track "Boost",
# disables routing of the mastering network
# when the mastering mode is disabled.

use ::Globals qw(:all);
use Modern::Perl; use ::Log qw(logpkg);
no warnings qw(uninitialized redefine);
our @ISA = '::SlaveTrack';
sub rec_status{
	my $track = shift;
	$mode->{mastering} ? MON :  OFF;
}
}
{
package ::CacheRecTrack; # for graph generation
use ::Globals qw(:all);
use ::Log qw(logpkg);
our @ISA = qw(::SlaveTrack);
sub current_version {
	my $track = shift;
	my $target = $tn{$track->target};
		$target->last + 1
# 	if ($target->rec_status eq PLAY
# 		or $target->rec_status eq REC and $bn{$track->target}){
# 	}
}
sub current_wav {
	my $track = shift;
		$tn{$track->target}->name . '_' . $track->current_version . '.wav'
}
sub full_path { my $track = shift; ::join_path( $track->dir, $track->current_wav) }
}
{
package ::MixDownTrack; 
use ::Globals qw(:all);
use ::Log qw(logpkg);
use SUPER;
our @ISA = qw(::Track);
sub current_version {	
	my $track = shift;
	my $last = $track->last;
	my $status = $track->rec_status;
	#logpkg('debug', "last: $last status: $status");
	if 	($status eq REC){ return ++$last}
	elsif ( $status eq PLAY){ return $track->monitor_version } 
	else { return 0 }
}
sub source_status { 
	my $track = shift; 
	return 'Master' if $track->rec_status eq REC;
	my $super = $track->super('source_status');
	$super->($track)
}
sub destination {
	my $track = shift; 
	$tn{Master}->destination if $track->rec_status eq PLAY
}
sub rec_status {
	my $track = shift;
	return REC if $track->rw eq REC;
	::Track::rec_status($track);
}
sub forbid_user_ops { 1 }
}
{
package ::EditTrack; use Carp qw(carp cluck);
use ::Globals qw(:all);
use ::Log qw(logpkg);
our @ISA = '::Track';
our $AUTOLOAD;
sub AUTOLOAD {
	my $self = shift;
	logpkg('debug', $self->name, ": args @_");
    # get tail of method call
    my ($call) = $AUTOLOAD =~ /([^:]+)$/;
	$::Edit::by_name{$self->name}->$call(@_);
}
sub DESTROY {}
sub current_version {	
	my $track = shift;
	my $last = $track->last;
	my $status = $track->rec_status;
	#logpkg('debug', "last: $last status: $status");
	if 	($status eq REC){ return ++$last}
	elsif ( $status eq PLAY){ return $track->monitor_version } 
	else { return 0 }
}
sub playat_time {
	logpkg('logcluck',$_[0]->name . "->playat_time");
	$_[0]->play_start_time
}
}
{
package ::VersionTrack;
use ::Globals qw(:all);
use ::Log qw(logpkg);
our @ISA ='::Track';
sub set_version {}
sub versions { [$_[0]->version] }
}
{
package ::Clip;

# Clips are the units of audio used to 
#  to make sequences. 

# A clip is created from a track. Clips extend the Track
# class in providing a position which derives from the
# object's ordinal position in an array (clips attribute) of
# the parent sequence object.
 
# Clips differ from tracks in that clips
# their one-based position (index) in the sequence items array.
# index is one-based.

use ::Globals qw(:all);
use ::Log qw(logpkg);
our @ISA = qw( ::VersionTrack ::Track );

sub sequence { my $self = shift; $::bn{$self->group} };

sub index { my $self = shift; my $i = 0;
	for( @{$self->sequence->items} ){
		$i++;
		return $i if $self->name eq $_
	}
}
sub predecessor {
	my $self = shift;
	$self->sequence->clip($self->index - 1)
}
sub duration {
	my $self = shift;
	$self->{duration} 
		? ::Mark::duration_from_tag($self->{duration})
		: $self->is_region 
			? $self->region_end_time - $self->region_start_time 
			: $self->wav_length;
}
sub endpoint { 
	my $self = shift;
	$self->duration + ( $self->predecessor ?  $self->predecessor->endpoint : 0 )
}
sub playat_time {
	my $self = shift;
	my $previous = $self->predecessor;
	$previous ? $previous->endpoint : 0
}

# we currently are not compatible with offset run mode
# perhaps we can enforce OFF status for clips under 
# offset run mode

} # end package
{ 
package ::Spacer;
our @ISA = '::Clip';
use SUPER;
use ::Object qw(duration);
sub rec_status { OFF }
sub new { 
	my ($class,%args) = @_;

	# remove args we will process
	my $duration = delete $args{duration};

	# give the remainder to the superclass constructor
	@_ = ($class, %args);
	my $self = super();
	#logpkg('debug',"new object: ", json_out($self->as_hash));
	#logpkg('debug', "items: ",json_out($items));

	# set the args removed above
	$self->{duration} = $duration;
	$self;
}
} # end package
{ 
package ::WetTrack; # for inserts
use ::Globals qw(:all);
use Modern::Perl; use ::Log qw(logpkg);
our @ISA = '::SlaveTrack';
}

{
package ::MidiTrack; 
use ::Globals qw(:all);
use ::Log qw(logpkg);
our @ISA = qw(::Track);
}

1;
__END__


