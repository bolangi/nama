# ---------- Track -----------
#
package ::;
{
package ::Track;
use ::Globals qw(:all);
use ::Log qw(logpkg logsub);
use List::MoreUtils qw(first_index);
# Objects belonging to Track and its subclasses
# have a 'class' field that is set when the 
# object is created, and used when restoring
# the object from a serialized state.

# the ->set_track_class() method re-blesses
# the object to a different subclass when necessary
# changing the 'class' field as well as the object
# class affiliation
#
# the ->as_hash() method (in Object.p) 
# used to serialize will
# sync the class field to the current object 
# class, hopefully saving a painful error

use Modern::Perl;
use Carp qw(carp cluck croak);
use File::Copy qw(copy);
use File::Slurp;
use Memoize qw(memoize unmemoize);
no warnings qw(uninitialized redefine);
our $VERSION = 1.0;

use ::Util qw(freq input_node dest_type dest_string join_path);
use vars qw($n %by_name @by_index %track_names %by_index);
our @ISA = '::Wav';
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
sub all { sort{$a->n <=> $b->n } values %by_name }

sub rec_hookable { grep{ $_->group ne 'Temp' and $_->group ne 'Insert' } all() }

{ my %system_track = map{ $_, 1} qw( Master Mixdown Eq Low Mid High Boost );
sub user {
	grep{ ! $system_track{$_} } map{$_->name} all();
}
sub is_user_track   { !  $system_track{$_[0]->name} } 
sub is_system_track {    $system_track{$_[0]->name} } 
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
		#			rw   	=> 'REC', # ::add_track() sets REC if necessary
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

	#print "object class: $class, object type: ", ref $object, $/;
	$track_names{$vals{name}}++;
	#print "names used: ", ::json_out( \%track_names );
	$by_index{$n} = $object;
	$by_name{ $object->name } = $object;
	::add_pan_control($n);
	::add_volume_control($n);

	$::this_track = $object;
	$object;
	
}


### object methods

# TODO these conditional clauses should be separated
# into classes 
sub dir {
	my $self = shift;
	 $self->project  
		? join_path(::project_root(), $self->project, '.wav')
		: ::this_wav_dir();
}

sub basename {
	my $self = shift;
	$self->target || $self->name
}

sub full_path { my $track = shift; join_path($track->dir, $track->current_wav) }

sub group_last {
	my $track = shift;
	my $bus = $bn{$track->group}; 
	#print join " ", 'searching tracks:', $bus->tracks, $/;
	$bus->last;
}

sub last { $_[0]->versions->[-1] || 0 }

sub current_wav {
	my $track = shift;
	my $last = $track->current_version;
	#print "last found is $last\n"; 
	if 	($track->rec_status eq 'REC'){ 
		$track->name . '_' . $last . '.wav'
	} elsif ( $track->rec_status eq 'PLAY'){ 
		my $filename = $track->targets->{ $track->monitor_version } ;
		$filename
	} else {
		logpkg('debug', "track ", $track->name, ": no current version") ;
		undef; 
	}
}

sub current_version {	
	my $track = shift;
	my $status = $track->rec_status;
	#logpkg('debug', "last: $last status: $status");

	# two possible version numbers, depending on REC/PLAY status
	
	if 	($status eq 'REC')
	{ 
		my $last = $config->{use_group_numbering} 
					? ::Bus::overall_last()
					: $track->last;
		return ++$last
	}
	elsif ( $status eq 'PLAY'){ return $track->monitor_version } 
	else { return 0 }
}

sub monitor_version {
	my $track = shift;

	my $bus = $bn{$track->group};
	return $track->version if $track->version 
				and grep {$track->version  == $_ } @{$track->versions} ;
	$track->last;
}

sub maybe_monitor { # ordinary sub, not object method
	my $monitor_version = shift;
	return 'PLAY' if $monitor_version and ! $mode->doodle;
	return 'OFF';
}

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

	# first, check for conditions resulting in status 'OFF'

	if ( $bus->rw eq 'OFF'
		or $track->rw eq 'OFF'
		or $mode->doodle and ! $mode->eager and $track->rw eq 'REC' and 
			$setup->{tracks_with_duplicate_inputs}->{$track->name}
		or $track->engine_group ne $::this_engine->name
	){ 	return			  'OFF' }

	# having reached here, we know $bus->rw and $track->rw are REC or PLAY
	# so the result will be REC or PLAY if conditions are met

	# second, set REC status if possible
	
	if( $track->rw eq 'REC'){

		my $source_type = $track->source_type;
		if ($source_type eq 'track' or $source_type eq 'loop'){ return 'REC' }
		elsif ($source_type eq 'jack_client'){

				# we expect an existing JACK client that
				# *outputs* a signal for our track input
				
				::jack_client_array($track->source_id,'output')
					?  return 'REC'
					:  return 'OFF'
			}
		elsif ($source_type eq 'jack_manual'){ return 'REC' }
		elsif ($source_type eq 'jack_ports_list'){ return 'REC' }
		elsif ($source_type eq 'null')	{ return 'REC' }
		elsif ($source_type eq 'rtnull')	{ return 'REC' }
		elsif ($source_type eq 'soundcard'){ return 'REC' }
		elsif ($source_type eq 'bus')	{ return 'REC' } # maybe $track->rw ??
		else { return 'OFF' }
	}
	elsif( $track->rw eq 'MON'){ 'MON' }

	# set PLAY status if possible
	
	else { 			maybe_monitor($monitor_version)

	}
}
sub rec_status_display {
	my $track = shift;
	my $status = $track->rec_status;
	my $setting = $track->rw;
	$status .= lc " ($setting)" if $status ne $setting;  
	$status .= " v".$track->current_version if $status eq 'REC';
	$status
}
# these settings will only affect WAV playback

sub region_start_time {
	my $track = shift;
	#return if $track->rec_status ne 'PLAY';
	carp $track->name, ": expected PLAY status" if $track->rec_status ne 'PLAY';
	::Mark::time_from_tag( $track->region_start )
}
sub region_end_time {
	my $track = shift;
	#return if $track->rec_status ne 'PLAY';
	carp $track->name, ": expected PLAY status" if $track->rec_status ne 'PLAY';
	if ( $track->region_end eq 'END' ){
		return $track->wav_length;
	} else {
		::Mark::time_from_tag( $track->region_end )
	}
}
sub playat_time {
	my $track = shift;
	carp $track->name, ": expected PLAY status" if $track->rec_status ne 'PLAY';
	#return if $track->rec_status ne 'PLAY';
	::Mark::time_from_tag( $track->playat )
}

# the following methods adjust
# region start and playat values during edit mode

sub shifted_region_start_time {
	my $track = shift;
	return $track->region_start_time unless $mode->{offset_run};
	::new_region_start(::edit_vars($track));
	
}
sub shifted_playat_time { 
	my $track = shift;
	return $track->playat_time unless $mode->{offset_run};
	::new_playat(::edit_vars($track));
}
sub shifted_region_end_time {
	my $track = shift;
	return $track->region_end_time unless $mode->{offset_run};
	::new_region_end(::edit_vars($track));
}

sub region_is_out_of_bounds {
	return unless $mode->{offset_run};
	my $track = shift;
	::case(::edit_vars($track)) =~ /out_of_bounds/
}

sub fancy_ops { # returns list 
	my $track = shift;
	my @skip = 	grep {::fxn($_)}  # must exist
				map { $track->{$_} } qw(vol pan fader latency_op );

	# make a dictionary of ops to exclude
	# that includes utility ops and their controllers
	
	my %skip;

	map{ $skip{$_}++ } @skip, ::expanded_ops_list(@skip);

	grep{ ! $skip{$_} } @{ $track->{ops} || [] };
}
sub fancy_ops_o {
	my $track = shift;
	map{ ::fxn($_) } fancy_ops();
}
		
sub snapshot {
	my $track = shift;
	my $fields = shift;
	my %snap; 
	my $i = 0;
	for(@$fields){
		$snap{$_} = $track->$_;
		#say "key: $_, val: ",$track->$_;
	}
	\%snap;
}


# create an edge representing sound source

sub input_path { 

	my $track = shift;

	# the corresponding bus handles input routing for mix tracks
	
	# bus mix tracks don't usually need to be connected
	return() if $track->is_mix_track and $track->rec_status ne 'PLAY';

	# the track may route to:
	# + another track
	# + an external source (soundcard or JACK client)
	# + a WAV file

	if($track->source_type eq 'track'){ ($track->source_id, $track->name) } 

	elsif($track->rec_status =~ /REC|MON/){ 
		(input_node($track->source_type), $track->name) } 

	elsif($track->rec_status eq 'PLAY' and ! $mode->doodle){
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

### object methods for text-based commands 

# Reasonable behavior whether 'source' and 'send' commands 
# are issued in JACK or ALSA mode.

sub soundcard_channel { $_[0] // 1 }

sub set_io {
	my $track = shift;
	my ($direction, $id, $type) = @_;
	# $direction: send | source
	
	# unless we are dealing with a simple query,
	# by the end of this routine we are going to assign
	# the following fields using the values in the 
	# $type and $id variables:
	#
	#    source_type
	#    source_id
	#
	#    -OR-
	#
	#    send_type
	#    send_id
	
	
	my $type_field = $direction."_type";
	my $id_field   = $direction."_id";

	# respond to query
	if ( ! $id ){ return $track->$type_field ? $track->$id_field : undef }

	# set values, returning new setting
	$type ||= dest_type( $id );
	
	if( $type eq 'track')		{}
	elsif( $type eq 'soundcard'){} # no changes needed 
	elsif( $type eq 'bus')     	{} # -ditto-
	#elsif( $type eq 'loop')    {}  # unused at present

	# don't allow user to set JACK I/O unless JACK server is running
	
	elsif( $type =~ /jack/ ){
		say("JACK server not running! "
			,"Cannot set JACK client or port as track source."), 
				return unless $jack->{jackd_running};

		if( $type eq 'jack_manual'){

			my $port_name = $track->jack_manual_port($direction);

			say $track->name, ": JACK $direction port is $port_name. Make connections manually.";
			$id = 'manual';
			$id = $port_name;
			$type = 'jack_manual';
		}
		elsif( $type eq 'jack_client'){
			my $client_direction = $direction eq 'source' ? 'output' : 'input';

			my $name = $track->name;
			my $width = scalar @{ ::jack_client_array($id, $client_direction) };
			$width or say 
				qq($name: $direction port for JACK client "$id" not found.);
			$width or return;
			$width ne $track->width and say 
				$track->name, ": track set to ", ::width($track->width),
				qq(, but JACK source "$id" is ), ::width($width), '.';
		}
		elsif( $type eq 'jack_ports_list' ){
			$id =~ /(\w+)\.ports/;
			my $ports_file_name = ($1 || $track->name) .  '.ports';
			$id = $ports_file_name;
			# warn if ports do not exist
			say($track->name, qq(: ports file "$id" not found in ),::project_root(),". Skipping."), 
				return unless -e join_path( ::project_root(), $id );
			# check if ports file parses
		}
	}
	$track->set($type_field => $type);
	$track->set($id_field => $id);
} 
sub source { # command for setting, showing track source
	my $track = shift;
	my ($id, $type) = @_;
	$track->set_io( 'source', $id, $type);
}
sub send { # command for setting, showing track source
	my $track = shift;
	my ($id, $type) = @_;
	$track->set_io( 'send', $id, $type);
}
sub set_source {
	my $track = shift;
	my ($source, $type) = @_;
	my $old_source = $track->input_object_text;
	$track->set_io('source',$source, $type);
	my $new_source = $track->input_object_text;;
	my $object = $new_source;
	if ( $old_source  eq $new_source ){
		::pager_join($track->name, ": input unchanged, $object");
	} else {
		::pager_join("Track ",$track->name, ": source set to $object");
		::pager_join("Track ",$track->name, ": record enabled"), 
	}
}
{
my $null_re = /^(rt)?null$/;
sub transition_from_null {
	my ($old, $new) = @_;
	$old =~ /$null_re/ and $new !~ /$null_re/
}
sub transition_to_null {
	my ($old, $new) = @_;
	$old !~ /$null_re/ and $new =~ /$null_re/
}
}


sub set_version {
	my ($track, $n) = @_;
	my $name = $track->name;
	if ($n == 0){
		print "$name: following bus default\n";
		$track->set(version => $n)
	} elsif ( grep{ $n == $_ } @{$track->versions} ){
		print "$name: anchoring version $n\n";
		$track->set(version => $n)
	} else { 
		print "$name: version $n does not exist, skipping.\n"
	}
}

sub set_send {
	my $track = shift;
	my ($output, $type) = @_;
	my $old_send = $track->output_object_text;
	logpkg('debug', "send was $old_send");
	$track->send($output, $type);
	my $new_send = $track->output_object_text;
	logpkg('debug', "send is now $new_send");
	my $object = $track->output_object_text;
	if ( $old_send  eq $new_send ){
		::pager_join("Track ",$track->name, ": send unchanged, ",
			( $object ?  $object : 'off'));
	} else {
		::pager_join("Track ",$track->name, ": ", 
		$object 
			? "$object is now a send target" 
			: "send target is turned off.");
	}
}

{
my %object_to_text = (
	soundcard 		=> 'soundcard channel',
	jack_client 	=> 'JACK client',
	jack_manual     => 'JACK manual port',
	jack_port   	=> 'JACK manual port',
	loop 			=> 'loop device',
	jack_ports_list => "JACK ports list",
	bus				=> "bus",
);
sub object_as_text {
	my ($track, $direction) = @_; # $direction: source | send
	my $type_field = $direction."_type";
	my $id_field   = $direction."_id";
	my $text = $object_to_text{$track->$type_field};
	$text .= ' ';
	$text .= $track->$id_field
}
}

sub input_object_text { # for text display
	my $track = shift;
	$track->object_as_text('source');
}

sub output_object_text {   # text for user display
	my $track = shift;
	$track->object_as_text('send');

}
sub bus_name { 
	my $track = shift;
	return unless $track->is_mix_track;
	$track->name eq 'Master' 
		? 'Main'
		: $track->name
}
sub source_status {
	my $track = shift;
	return $track->current_wav if $track->rec_status eq 'PLAY' ;
	#return $track->name eq 'Master' ? $track->bus_name : '' if $track->is_mix_track;
	return $track->bus_name . " bus" if $track->is_mix_track;
	return $track->source_id unless $track->source_type eq 'soundcard';
	my $ch = $track->source_id;
	my @channels;
	push @channels, $_ for $ch .. ($ch + $track->width - 1);
	join '/', @channels
}
sub destination {
	my $track = shift;
	# display logic 
	# always show the bus
	# except for tracks that belongs to the bus null.
	# in that case, show the specific source.
	#
	# for these mix tracks, we use the
	# track's own send_type/send_id
	
	my $out;
	$out .= $track->group unless $track->group =~ /^(null|Master)$/;
	my $send_id = $track->send_id;
	#say "send type: $send_type, send id: $send_id";
	my $send_type = $track->send_type;
	return $out if ! $send_type;
	$out .=	', ' if $out;
	$out .= dest_string($send_type, $send_id, $track->width);
	$out
}
sub set_rec {
	my $track = shift;
	if (my $t = $track->target){
		my  $msg  = $track->name;
			$msg .= qq( is an alias to track "$t");
			$msg .=  q( in project ") . $track->project . q(") 
				if $track->project;
			$msg .= qq(.\n);
			$msg .= "Can't set a track alias to REC.\n";
		print $msg;
		return;
	}
	$track->set_rw('REC');
}
sub set_play {
	my $track = shift;
	$track->set_rw('PLAY');
}
sub set_mon {
	my $track = shift;
	$track->set_rw('MON');
}
sub set_off {
	my $track = shift;
	$track->set_rw('OFF');
}

=comment
mix
self bus      brothers
REC  PLAY 
PLAY  OFF
OFF  OFF

member
REC  REC      REC->PLAY
PLAY  OFF->PLAY REC/PLAY->OFF
OFF  --       --

=cut
	
sub set_rw {
	my ($track, $setting) = @_;
	#my $already = $track->rw eq $setting ? " already" : "";
	$track->set(rw => $setting);
	my $status = $track->rec_status();
	say $track->name, " set to $setting", 
		($status ne $setting ? ", but current status is $status" : "");

}
	

# Operations performed by track objects

sub normalize {
	my $track = shift;
	if ($track->rec_status ne 'PLAY'){
		print $track->name, ": You must set track to PLAY before normalizing, skipping.\n";
		return;
	} 
	# track version will exist if PLAY status
	my $cmd = 'ecanormalize ';
	$cmd .= $track->full_path;
	print "executing: $cmd\n";
	system $cmd;
}
sub fixdc {
	my $track = shift;
	if ($track->rec_status ne 'PLAY'){
		print $track->name, ": You must set track to PLAY before fixing dc level, skipping.\n";
		return;
	} 

	my $cmd = 'ecafixdc ';
	$cmd .= $track->full_path;
	print "executing: $cmd\n";
	system $cmd;
}
sub wav_length {
	my $track = shift;
	::wav_length($track->full_path)
}
sub wav_format{
	my $track = shift;
	::wav_format($track->full_path)
}

	
sub mute {
	package ::;
	my $track = shift;
	my $nofade = shift;
	# do nothing if already muted
	return if defined $track->old_vol_level();
	if ( $fx->{params}->{$track->vol}[0] != $track->mute_level
		and $fx->{params}->{$track->vol}[0] != $track->fade_out_level){   
		$track->set(old_vol_level => $fx->{params}->{$track->vol}[0]);
		fadeout( $track->vol ) unless $nofade;
	}
	$track->set_vol($track->mute_level);
}
sub unmute {
	package ::;
	my $track = shift;
	my $nofade = shift;
	# do nothing if we are not muted
	return if ! defined $track->old_vol_level;
	if ( $nofade ){
		$track->set_vol($track->old_vol_level);
	} 
	else { 
		$track->set_vol($track->fade_out_level);
		fadein($track->vol, $track->old_vol_level);
	}
	$track->set(old_vol_level => undef);
}

sub mute_level {
	my $track = shift;
	$config->{mute_level}->{$track->vol_type}
}
sub fade_out_level {
	my $track = shift;
	$config->{fade_out_level}->{$track->vol_type}
}
sub set_vol {
	my $track = shift;
	my $val = shift;
	::effect_update_copp_set($track->vol, 0, $val);
}
sub vol_type {
	my $track = shift;
	$fx->{applied}->{$track->vol}->{type}
}
sub import_audio  { 
	my $track = shift;
	my ($path, $frequency) = @_; 
	$path = ::expand_tilde($path);
	#say "path: $path";
	my $version  = $track->last + 1;
	if ( ! -r $path ){
		print "$path: non-existent or unreadable file. No action.\n";
		return;
	}
	my ($depth,$width,$freq) = split ',', ::wav_format($path);
	say "format: ", ::wav_format($path);
	$frequency ||= $freq;
	if ( ! $frequency ){
		say "Cannot detect sample rate of $path. Skipping.";
		say "Use 'import_audio <path> <frequency>' if possible.";
		return 
	}
	my $desired_frequency = freq( $config->{raw_to_disk_format} );
	my $destination = join_path(::this_wav_dir(),$track->name."_$version.wav");
	#say "destination: $destination";
	if ( $frequency == $desired_frequency and $path =~ /.wav$/i){
		say "copying $path to $destination";
		copy($path, $destination) or die "copy failed: $!";
	} else {	
		my $format = ::signal_format($config->{raw_to_disk_format}, $width);
		say "importing $path as $destination, converting to $format";
		::teardown_setup();
		my $ecs = qq(-f:$format -i:resample-hq,$frequency,"$path" -o:$destination);
		my $path = join_path(::project_dir()."convert.ecs");
		write_file($path, $ecs);
		load_ecs($path) or ::throw("$path: load failed, aborting"), return;
		eval_iam('start');
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
sub busify {
	my $track = shift;
	::add_sub_bus($track->name) unless $track->is_system_track;
}
sub unbusify {
	my $track = shift;
	return if $track->is_system_track;
	$track->set( rw => 'PLAY');
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

sub version_comment {
	my ($track, $v) = @_;
	return unless $project->{track_version_comments}->{$track->name}{$v};
	my $text   = $project->{track_version_comments}->{$track->name}{$v}{user};
	$text .= " " if $text;
	my $system = $project->{track_version_comments}->{$track->name}{$v}{system};
	$text .= "* $system" if $system;
	"$v: $text\n" if $text;
}
# Modified from Object.p to save class
sub as_hash {
	my $self = shift;
	my $class = ref $self;
	bless $self, 'HASH'; # easy magic
	#print json_out $self; return;
	my %guts = %{ $self };
	$guts{class} = $class; # make sure we save the correct class name
	#print join " ", %guts; return;
	#my @keys = keys %guts;
	#map{ $output->{$_} or $output->{$_} = '~'   } @keys; 
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

sub set_comment {
	my ($track, $comment) = @_;
	$project->{track_comments}->{$track->name} = $comment
}
sub comment { $project->{track_comments}->{$_[0]->name} }

sub show_version_comments {
	my ($t, @v) = @_;
	return unless @v;
	::pager(map{ $t->version_comment($_) } @v);
}
sub add_version_comment {
	my ($t,$v,$text) = @_;
	$t->targets->{$v} or say("$v: no such version"), return;	
	$project->{track_version_comments}->{$t->name}{$v}{user} = $text;
	$t->version_comment($v);
}
sub add_system_version_comment {
	my ($t,$v,$text) = @_;
	$t->targets->{$v} or say("$v: no such version"), return;	
	$project->{track_version_comments}{$t->name}{$v}{system} = $text;
	$t->version_comment($v);
}
sub remove_version_comment {
	my ($t,$v) = @_;
	$t->targets->{$v} or say("$v: no such version"), return;	
	delete $project->{track_version_comments}{$t->name}{$v}{user};
	$t->version_comment($v) || "$v: [comment deleted]\n";
}
sub remove_system_version_comment {
	my ($t,$v) = @_;
	delete $project->{track_version_comments}{$t->name}{$v}{system} if
		$project->{track_version_comments}{$t->name}{$v}
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

sub first_effect_of_type {
	my $track = shift;
	my $type = shift;
	for my $op ( @{$track->ops} ){
		my $FX = ::fxn($op);
		return $FX if $type eq $FX->type
	}
}
sub is_mix_track {
	my $track = shift;
	($bn{$track->name} or $track->name eq 'Master') and $track->rw eq 'MON'
}
sub bus { $bn{$_[0]->group} }
	
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
 	$track->rw ne 'OFF' ? 'MON' : 'OFF' 
}
sub destination {
	my $track = shift; 
	$track->SUPER() if $track->rec_status ne 'OFF'
}
#sub rec_status_display { $_[0]->rw ne 'OFF' ? 'PLAY' : 'OFF' }
sub busify {}
sub unbusify {}
}
{
package ::MasteringTrack; # used for mastering chains 
use ::Globals qw(:all);
use Modern::Perl; use ::Log qw(logpkg);
no warnings qw(uninitialized redefine);
our @ISA = '::SimpleTrack';

sub rec_status{
	my $track = shift;
 	return 'OFF' if $track->engine_group ne $this_engine->name;
	$mode->{mastering} ? 'MON' :  'OFF';
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
package ::BoostTrack; # for instrument monitor bus
use ::Globals qw(:all);
use Modern::Perl; use ::Log qw(logpkg);
no warnings qw(uninitialized redefine);
our @ISA = '::SlaveTrack';
sub rec_status{
	my $track = shift;
	$mode->{mastering} ? 'MON' :  'OFF';
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
# 	if ($target->rec_status eq 'PLAY'
# 		or $target->rec_status eq 'REC' and $bn{$track->target}){
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
	if 	($status eq 'REC'){ return ++$last}
	elsif ( $status eq 'PLAY'){ return $track->monitor_version } 
	else { return 0 }
}
sub source_status { 
	my $track = shift; 
	return 'Master' if $track->rec_status eq 'REC';
	my $super = $track->super('source_status');
	$super->($track)
}
sub destination {
	my $track = shift; 
	$tn{Master}->destination if $track->rec_status eq 'PLAY'
}
sub rec_status {
	my $track = shift;
	return 'REC' if $track->rw eq 'REC';
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
	if 	($status eq 'REC'){ return ++$last}
	elsif ( $status eq 'PLAY'){ return $track->monitor_version } 
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
sub rec_status { 'OFF' }
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

# ----------- Track_subs -------------
{
package ::;
use Modern::Perl;
use ::Effects qw(:all);

# usual track

sub add_track {

	logsub("&add_track");
	#return if transport_running();
	my ($name, @params) = @_;
	my %vals = (name => $name, @params);
	my $class = $vals{class} // '::Track';
	{ no warnings 'uninitialized';	
	logpkg('debug', "name: $name, ch_r: $gui->{_chr}, ch_m: $gui->{_chm}");
	}	
	say("$name: track name already in use. Skipping."), return 
		if $tn{$name};
	say("$name: reserved track name. Skipping"), return
	 	if grep $name eq $_, @{$mastering->{track_names}}; 

	# in order to increment serially
	::ChainSetup::remove_temporary_tracks();

	my $track = $class->new(%vals);
	return if ! $track; 
	logpkg('debug', "ref new track: ", ref $track); 
	$track->source($gui->{_chr}) if $gui->{_chr};
#		$track->send($gui->{_chm}) if $gui->{_chm};

	my $bus = $bn{$track->group}; 
	process_command('for mon; mon') if $mode->{preview} and $bus->rw eq 'MON';
	# TODO ???
	$bus->set(rw => 'MON') unless $track->target; # not if is alias

	# normal tracks default to 'MON'
	# track aliases default to 'PLAY'
	$track->set(rw => $track->target
					?  'PLAY'
					:  'MON') ;
	$gui->{_track_name} = $gui->{_chm} = $gui->{_chr} = undef;

	set_current_bus();
	$ui->track_gui($track->n);
	logpkg('debug', "Added new track!\n", sub{$track->dump});
	$track;
}

# create read-only track pointing at WAV files of specified
# name in current project

sub add_track_alias {
	my ($name, $track) = @_;
	my $target; 
	if 		( $tn{$track} ){ $target = $track }
	elsif	( $ti{$track} ){ $target = $ti{$track}->name }
	add_track(  $name, target => $target );
}
# create read-only track pointing at WAV files of specified
# track name in a different project

sub add_track_alias_project {
	my ($name, $track, $project_name) = @_;
	$project_name //= $::project->{name}; 
	my $dir =  join_path(project_root(), $project_name, '.wav'); 
	if ( -d $dir ){
		if ( glob "$dir/$track*.wav"){
			print "Found target WAV files.\n";
			my @params = (target => $track, project => $project_name);
			add_track( $name, @params );
		} else { print "$project_name:$track - No WAV files found.  Skipping.\n"; return; }
	} else { 
		print("$project_name: project does not exist.  Skipping.\n");
		return;
	}
}

# vol/pan requirements of mastering and mixdown tracks

# called from Track_subs, Graphical_subs
{ my %volpan = (
	Eq => {},
	Low => {},
	Mid => {},
	High => {},
	Boost => {vol => 1},
	Mixdown => {},
);

sub need_vol_pan {

	# this routine used by 
	#
	# + add_track() to determine whether a new track _will_ need vol/pan controls
	# + add_track_gui() to determine whether an existing track needs vol/pan  
	
	my ($track_name, $type) = @_;

	# $type: vol | pan
	
	# Case 1: track already exists
	
	return 1 if $tn{$track_name} and $tn{$track_name}->$type;

	# Case 2: track not yet created

	if( $volpan{$track_name} ){
		return($volpan{$track_name}{$type}	? 1 : 0 )
	}
	return 1;
}
}

# track width in words

sub width {
	my $count = shift;
	return 'mono' if $count == 1;
	return 'stereo' if $count == 2;
	return "$count channels";
}


sub add_volume_control {
	my $n = shift;
	return unless need_vol_pan($ti{$n}->name, "vol");
	
	my $vol_id = effect_init({
				chain => $n, 
				type => $config->{volume_control_operator},
				effect_id => $ti{$n}->vol, # often undefined
				});
	
	$ti{$n}->set(vol => $vol_id);  # save the id for next time
	$vol_id;
}
sub add_pan_control {
	my $n = shift;
	return unless need_vol_pan($ti{$n}->name, "pan");

	my $pan_id = effect_init({
				chain => $n, 
				type => 'epp',
				effect_id => $ti{$n}->pan, # often undefined
				});
	
	$ti{$n}->set(pan => $pan_id);  # save the id for next time
	$pan_id;
}
sub rename_track {
	use Cwd;
	use File::Slurp;
	my ($oldname, $newname, $statefile, $dir) = @_;
	save_state();
	my $old_dir = cwd();
	chdir $dir;

	# rename audio files
	
	qx(rename 's/^$oldname(?=[_.])/$newname/' *.wav);


	# rename in State.json when candidate key
	# is part of the specified set and the value 
	# exactly matches $oldname
	
	my $state = read_file($statefile);

	$state =~ s/
		"					# open quote
		(track| 		# one of specified fields
		name| 
		group| 
		source| 
		send_id| 
		target| 
		current_edit| 
		send_id| 
		return_id| 
		wet_track| 
		dry_track| 
		track| 
		host_track)
		"				# close quote
		\ 				# space
		:				# colon
		\ 				# space
		"$oldname"/"$1" : "$newname"/gx;

	write_file($statefile, $state);
	my $msg = "Rename track $oldname -> $newname";
	git_commit($msg);
	pager($msg);
	load_project(name => $::project->{name});
}
} # end package

1;
__END__


