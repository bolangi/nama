package ::TrackIO;
use Role::Tiny;
use Modern::Perl;
use ::Globals qw(:all);
use File::Slurp qw(write_file);
use File::Copy;
use ::Util qw(dest_string dest_type join_path freq);
use ::Log qw(logpkg logsub);

sub rec_status {
#	logsub("&rec_status");
	my $track = shift;
	
	#my $source_id = $track->source_id;
	my $playback_version = $track->playback_version;

	my $bus = $bn{$track->group};
	#logpkg('debug', join " ", "bus:",$bus->name, $bus->rw);
	{
	no warnings 'uninitialized';
	logpkg('debug', "track: $track->{name}, source: $track->{source_id}, monitor version: $playback_version");
	}
	#logpkg('debug', "track: ", $track->name, ", source: ",
	#	$track->source_id, ", monitor version: $playback_version");

	# first, check for conditions resulting in status OFF

	no warnings 'uninitialized';
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
	
	else { 			maybe_monitor($playback_version)

	}
}

sub maybe_monitor { # ordinary sub, not object method
	my $playback_version = shift;
	return PLAY if $playback_version and ! $mode->doodle;
	return OFF;
}

sub rec_status_display {
	my $track = shift;
	my $rs = $track->rec_status;
	my $status;
	$status .= $rs;
	$status .= ' v'.$track->current_version if $rs eq REC;
	$status
}
### object methods for text-based commands 

# Reasonable behavior whether 'source' and 'send' commands 
# are issued in JACK or ALSA mode.

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
		::throw("JACK server not running! "
			,"Cannot set JACK client or port as track source."), 
				return unless $jack->{jackd_running};

		if( $type eq 'jack_manual'){

			my $port_name = $track->jack_manual_port($direction);

			::pager($track->name, ": JACK $direction port is $port_name. Make connections manually.");
			$id = 'manual';
			$id = $port_name;
			$type = 'jack_manual';
		}
		elsif( $type eq 'jack_client'){
			my $client_direction = $direction eq 'source' ? 'output' : 'input';

			my $name = $track->name;
			my $width = scalar @{ ::jack_client_array($id, $client_direction) };
			$width or ::pager(
				qq(Track $name: $direction port for JACK client "$id" not found.));
			$width or return;
			$width ne $track->width and ::pager(
				"Track $name set to ", ::width($track->width),
				qq(, but JACK source "$id" is ), ::width($width), '.');
		}
		elsif( $type eq 'jack_ports_list' ){
			$id =~ /(\w+)\.ports/;
			my $ports_file_name = ($1 || $track->name) .  '.ports';
			$id = $ports_file_name;
			# warn if ports do not exist
			::throw($track->name, qq(: ports file "$id" not found in ),::project_root(),". Skipping."), 
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
		::pager($track->name, ": input unchanged, $object");
	} else {
		::pager("Track ",$track->name, ": source set to $object");
		if (transition_to_null($old_source, $new_source))
		{
			::pager("Track ",$track->name, ": null input, toggling to MON");
			$track->set(rw => MON) if $track->rw eq REC;		
		}
	}
}
{
my $null_re = qr/^\s*(rt)?null\s*$/;
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
		::pager("$name: following bus default\n");
		$track->set(version => $n)
	} elsif ( grep{ $n == $_ } @{$track->versions} ){
		::pager("$name: anchoring version $n\n");
		$track->set(version => $n)
	} else { 
		::throw("$name: version $n does not exist, skipping.\n")
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
		::pager("Track ",$track->name, ": send unchanged, ",
			( $object ?  $object : 'off'));
	} else {
		::pager("Track ",$track->name, ": ", 
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
	midi			=> 'MIDI input channel',
);
sub object_as_text {
	my ($track, $direction) = @_; # $direction: source | send
	my $type_field = $direction."_type";
	my $id_field   = $direction."_id";
	{
	no warnings 'uninitialized';
	my $text = $object_to_text{$track->$type_field};
	$text .= ' ';
	$text .= $track->$id_field
	}
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
sub source_status {
	my $track = shift;
	no warnings 'uninitialized';
	return $track->current_wav if $track->play ;
	return $track->name . " bus" if $track->is_mix_track;
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
	$out .= $track->group unless $track->group =~ /^(Aux|Null)$/;
	my $send_id = $track->send_id;
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
		::throw($msg);
		return;
	}
	$track->set_rw(REC);
}
sub set_play {
	my $track = shift;
	$track->set_rw(PLAY);
}
sub set_mon {
	my $track = shift;
	$track->set_rw(MON);
}
sub set_off {
	my $track = shift;
	$track->set_rw(OFF);
}

sub set_rw {
	my ($track, $setting) = @_;
	#my $already = $track->rw eq $setting ? " already" : "";
	$track->set(rw => $setting);
	my $status = $track->rec_status();
	::pager("Track ",$track->name, " set to $setting", 
		($status ne $setting ? ", but current status is $status" : ""));

}
sub has_insert  { $_[0]->prefader_insert or $_[0]->postfader_insert }

sub prefader_insert { ::Insert::get_id($_[0],'pre') }
sub postfader_insert { ::Insert::get_id($_[0],'post') }
sub inserts {  [  # return array ref
					map{ $::Insert::by_index{$_} }grep{$_} 
					map{ ::Insert::get_id($_[0],$_)} qw(pre post) 
				]
}
sub soundcard_channel { $_[0] // 1 }


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
		::ecasound_iam('start');
		::sleeper(0.2); sleep 1 while ::ecasound_engine_running();
	} 
	::restart_wav_memoize() if $config->{opts}->{R}; # usually handled by reconfigure_engine() 
}

sub port_name { $_[0]->target || $_[0]->name } 
sub jack_manual_port {
	my ($track, $direction) = @_;
	$track->port_name . ($direction =~ /source|input/ ? '_in' : '_out');
}

## rw_set() for managing bus-level REC/MON/PLAY/OFF settings
## in response to user commands rec/mon/play/off affecting
## the current track.

{
my %bus_logic = ( 
	mix_track =>
	{

	# setting mix track to REC
	
		REC => sub
		{
			my ($bus, $track) = @_;
			$track->set_rec;
		},

	# setting a mix track to PLAY
	
		PLAY => sub
		{
			my ($bus, $track) = @_;
			$track->set_play;
		},

	# setting a mix track to MON
	
		MON => sub
		{
			my ($bus, $track) = @_;
			$track->set_mon;
		},

	# setting mix track to OFF
	
		OFF => sub
		{
			my ($bus, $track) = @_;

			$track->set_off;

			# with the mix track off, 
			# the member tracks get pruned 
			# from the graph 
		}
	},
	member_track =>
	{

	# setting member track to REC
	
		REC => sub 
		{ 
			my ($bus, $track) = @_;

			$track->set_rec() or return;

			$bus->set(rw => MON);
			
			# we assume the bus is connected to a track,
			# so it's send_id field is the track name.
			
			$tn{$bus->send_id}->activate_bus 
				if $bus->send_type eq 'track' and $tn{$bus->send_id};
			
		},

	# setting member track to MON 
	
		MON => sub
		{ 
			my ($bus, $track) = @_;
			$bus->set(rw => MON) if $bus->rw eq 'OFF';
			$track->set_mon;
		},

	# setting member track to PLAY
	
		PLAY => sub
		{ 
			my ($bus, $track) = @_;
			$bus->set(rw => MON) if $bus->rw eq 'OFF';
			$track->set_play;

		},
	# setting member track to OFF 

		OFF => sub
		{
			my ($bus, $track) = @_;
			$track->set_off;
		},
	},
);
# for track commands 'rec', 'mon','off' we 
# may toggle rw state of the bus as well
#

sub rw_set {
	my $track = shift;
	logsub("&rw_set");
	my ($bus, $rw) = @_;
	my $type = $bn{$track->name} # should be $track->is_ mix_track
		? 'mix_track'
		: 'member_track';
	$bus_logic{$type}{uc $rw}->($bus,$track);
}
}

1;
	
