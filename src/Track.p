# ---------- Track -----------
#
# give all classes (packages) access to global vars 

package ::;
our (
	[% join qq(,\n\t), split " ", qx(cat 	./singletons.pl ./globals.pl  ./serialize.pl ) %]
);
{
package ::Track;
use ::Log qw(logit);

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

use ::Util qw(freq input_node dest_type join_path);
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
					source_id   	=> 1,
					send_type 		=> undef,
					send_id   		=> undef,
					effect_chain_stack => [],
					cache_map 		=> {},
					current_edit 	=> {},
					version_comment => {},

					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	$track_names{$vals{name}}++;
	#print "names used: ", ::yaml_out( \%track_names );
	$by_index{$n} = $object;
	$by_name{ $object->name } = $object;
	::add_pan_control($n);
	::add_volume_control($n);

	$this_track = $object;
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
# look at "ancestors" of track to get basename

# overrides default Object::Tiny accessor (returning $self->{target})
sub target {
	my $self = shift;
	my $parent = $tn{$self->{target}};
	defined $parent && $parent->target || $self->{target};
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
	} elsif ( $track->rec_status eq 'MON'){ 
		my $filename = $track->targets->{ $track->monitor_version } ;
		$filename
	} else {
		logit('::Track','debug', "track ", $track->name, ": no current version") ;
		undef; 
	}
}

sub current_version {	
	my $track = shift;
	my $status = $track->rec_status;
	#logit('::Track','debug', "last: $last status: $status");

	# two possible version numbers, depending on REC/MON status
	
	if 	($status eq 'REC' and ! $track->rec_defeat)
	{ 
		my $last = $config->{use_group_numbering} 
					? ::Bus::overall_last()
					: $track->last;
		return ++$last
	}
	elsif ( $status eq 'MON'){ return $track->monitor_version } 
	else { return 0 }
}

sub monitor_version {
	my $track = shift;

	my $bus = $bn{$track->group};
	return $track->version if $track->version 
				and grep {$track->version  == $_ } @{$track->versions} ;
	return $bus->version if $bus->version 
				and grep {$bus->version  == $_ } @{$track->versions};
	return undef if $bus->version;
	$track->last;
}

sub maybe_monitor { # ordinary sub, not object method
	my $monitor_version = shift;
	return 'MON' if $monitor_version and ! ($mode->{preview} eq 'doodle');
	return 'OFF';
}

sub rec_status {
#	logsub("&rec_status");
	my $track = shift;
	
	#my $source_id = $track->source_id;
	my $monitor_version = $track->monitor_version;

	my $bus = $bn{$track->group};
	#logit('::Track','debug', join " ", "bus:",$bus->name, $bus->rw);
	logit('::Track','debug', "track: ", $track->name, ", source: ",
		$track->source_id, ", monitor version: $monitor_version");

	# first, check for conditions resulting in status 'OFF'

	if ( $bus->rw eq 'OFF'
		or $track->rw eq 'OFF'
		or $mode->{preview} eq 'doodle' and $track->rw eq 'REC' and 
			$setup->{tracks_with_duplicate_inputs}->{$track->name}
	){ 	return			  'OFF' }

	# having reached here, we know $bus->rw and $track->rw are REC or MON
	# so the result will be REC or MON if conditions are met

	# second, set REC status if possible
	
	if( $track->rw eq 'REC'){

		given( $track->source_type){
			# XXX if no jack client , play WAV file??
			when('jack_client'){

				# we expect an existing JACK client that
				# *outputs* a signal for our track input
				
				::jack_client_array($track->source_id,'output')
					?  return 'REC'
					:  return maybe_monitor($monitor_version)
			}
			when('jack_manual')		{ return 'REC' }
			when('jack_ports_list')	{ return 'REC' }
			when('null')			{ return 'REC' }
			when('soundcard')		{ return 'REC' }
			when('bus')				{ return 'REC' } # maybe $track->rw ??
			default 				{ return 'OFF' }
			#default { croak $track->name. ": missing source type" }
			# fall back to MON
			#default {  maybe_monitor($monitor_version)  }
		}
	}
	# third, set MON status if possible
	
	else { 			maybe_monitor($monitor_version)

	}
}
sub rec_status_display {
	my $track = shift;
	my $status = $track->rec_status;
	($track->rw eq 'REC' and $track->rec_defeat) ? "($status)" : $status;
}

# these settings will only affect WAV playback

sub region_start_time {
	my $track = shift;
	#return if $track->rec_status ne 'MON';
	carp $track->name, ": expected MON status" if $track->rec_status ne 'MON';
	::Mark::unadjusted_mark_time( $track->region_start )
}
sub region_end_time {
	my $track = shift;
	#return if $track->rec_status ne 'MON';
	carp $track->name, ": expected MON status" if $track->rec_status ne 'MON';
	if ( $track->region_end eq 'END' ){
		return $track->wav_length;
	} else {
		::Mark::unadjusted_mark_time( $track->region_end )
	}
}
sub playat_time {
	my $track = shift;
	carp $track->name, ": expected MON status" if $track->rec_status ne 'MON';
	#return if $track->rec_status ne 'MON';
	::Mark::unadjusted_mark_time( $track->playat )
}

# the following methods adjust
# region start and playat values during edit mode

sub adjusted_region_start_time {
	my $track = shift;
	return $track->region_start_time unless $mode->{offset_run};
	::set_edit_vars($track);
	::new_region_start();
	
}
sub adjusted_playat_time { 
	my $track = shift;
	return $track->playat_time unless $mode->{offset_run};
	::set_edit_vars($track);
	::new_playat();
}
sub adjusted_region_end_time {
	my $track = shift;
	return $track->region_end_time unless $mode->{offset_run};
	::set_edit_vars($track);
	::new_region_end();
}

sub region_is_out_of_bounds {
	return unless $mode->{offset_run};
	my $track = shift;
	::set_edit_vars($track);
	::case() =~ /out_of_bounds/
}

sub fancy_ops { # returns list 
	my $track = shift;
	my @skip = grep {$_} map { $track->$_ } qw(vol pan fader);
	my %skip;
	map{ $skip{$_}++ } ::expanded_ops_list(@skip);
	grep{ ! $skip{$_} } @{ $track->ops };
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


# for graph-style routing

sub input_path { # signal path, not file path

	my $track = shift;

	# create edge representing live sound source input
	
	if($track->rec_status eq 'REC'){

			# we skip the source if the track is a 'mix track'
			# i.e. it gets input from other tracks, not 
			# the specified source, if any.
			
			return () if $track->is_mix_track;

			# comment: individual tracks of a sub bus
			# connect their outputs to the mix track
			# (the $bus->apply method takes care of this)
			#
			# subtrack ---> mix_track
			#
			# later:
			#  
			#  subtrack --> mix_track_in --> mix_track

			( input_node($track->source_type) , $track->name)
	} elsif($track->rec_status eq 'MON' and $mode->{preview} ne 'doodle'){

	# create edge representing WAV file input

		('wav_in', $track->name) 

	}
}

### remove and destroy

sub remove_effect_from_track { # doesn't touch $fx->{applied} or $fx->{params} data structures 
	my $track = shift;
	my @ids = @_;
	$track->set(ops => [ grep { my $existing = $_; 
									! grep { $existing eq $_
									} @ids }  
							@{$track->ops} ]);
}
sub has_insert  { $_[0]->prefader_insert or $_[0]->postfader_insert }

sub prefader_insert { ::Insert::get_id($_[0],'pre') }
sub postfader_insert { ::Insert::get_id($_[0],'post') }

# remove track object and all effects

sub remove {
	my $track = shift;
	my $n = $track->n;
	$ui->remove_track_gui($n); 
 	$this_track = $ti{::Track::idx() - 1};
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
	my ($track, $direction, $id) = @_;
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

	# respond to a query (no argument)
	if ( ! $id ){ return $track->$type_field ? $track->$id_field : undef }

	# set values, returning new setting
	my $type = dest_type( $id );
	given ($type){
	
		# no data changes needed for some settings

		when('soundcard'){}
		when ('bus')     {}
		#when('loop')     {}  # unused at present

		# rec_defeat tracks with 'null' input

		when ('null'){ 
			$track->set(rec_defeat => 1);
			say $track->name, ": recording disabled by default for 'null' input.";
			say "Use 'rec_enable' if necessary";
		}

		# don't allow user to set JACK I/O unless JACK server is running
		
 		when ( /jack/ ){
			say("JACK server not running! "
				,"Cannot set JACK client or port as track source."), 
					return unless $jack->{jackd_running};

			continue; # don't break out of given/when chain
		} 

		when ('jack_manual'){

			my $port_name = $track->jack_manual_port($direction);

 			say $track->name, ": JACK $direction port is $port_name. Make connections manually.";
			$id = 'manual';
			$id = $port_name;
			$type = 'jack_manual';
		}
		when ('jack_client'){
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
		when( 'jack_ports_list' ){
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
	my ($track, $id) = @_;
	$track->set_io( 'source', $id);
}
sub send { # command for setting, showing track source
	my ($track, $id) = @_;
	$track->set_io( 'send', $id);
}
sub set_source { # called from parser 
	my $track = shift;
	my ($source, $type) = @_;
	my $old_source = $track->input_object;
	$track->set_io('source',$source, $type);
	my $new_source = $track->input_object;
	my $object = $new_source;
	if ( $old_source  eq $new_source ){
		print $track->name, ": input unchanged, $object\n";
	} else {
		print $track->name, ": input set to $object\n";
		# re-enable recording of null-source tracks
		# TODO: does null source really get recorded?
		say($track->name, ": record enabled"),
		$track->set(rec_defeat => 0) if $old_source eq 'null';
	}
}

sub set_version {
	my ($track, $n) = @_;
	my $name = $track->name;
	if ($n == 0){
		print "$name: following latest version\n";
		$track->set(version => $n)
	} elsif ( grep{ $n == $_ } @{$track->versions} ){
		print "$name: anchoring version $n\n";
		$track->set(version => $n)
	} else { 
		print "$name: version $n does not exist, skipping.\n"
	}
}

sub set_send { # wrapper
	my ($track, $output) = @_;
	my $old_send = $track->send;
	my $new_send = $track->send($output);
	my $object = $track->output_object;
	if ( $old_send  eq $new_send ){
		print $track->name, ": send unchanged, ",
			( $object ?  $object : 'off'), "\n";
	} else {
		print $track->name, ": aux output ",
		($object ? "to $object" : 'is off.'), "\n";
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

sub input_object { # for text display
	my $track = shift;
	$track->object_as_text('source');
}

sub output_object {   # text for user display
	my $track = shift;
	$track->object_as_text('send');

}
sub source_status {
	my $track = shift;
	my $id = $track->source_id;
	return unless $id;
	$track->rec_status eq 'REC' ? $id : "[$id]"
	
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
sub set_mon {
	my $track = shift;
	$track->set_rw('MON');
}
sub set_off {
	my $track = shift;
	$track->set_rw('OFF');
}
sub is_mix_track { ref $_[0] =~ /MixTrack/ }

=comment
mix
self bus      brothers
REC  MON 
MON  OFF
OFF  OFF

member
REC  REC      REC->MON
MON  OFF->MON REC/MON->OFF
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
	if ($track->rec_status ne 'MON'){
		print $track->name, ": You must set track to MON before normalizing, skipping.\n";
		return;
	} 
	# track version will exist if MON status
	my $cmd = 'ecanormalize ';
	$cmd .= $track->full_path;
	print "executing: $cmd\n";
	system $cmd;
}
sub fixdc {
	my $track = shift;
	if ($track->rec_status ne 'MON'){
		print $track->name, ": You must set track to MON before fixing dc level, skipping.\n";
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
		my $cmd = qq(ecasound -f:$format -i:resample-hq,$frequency,"$path" -o:$destination);
		#say $cmd;
		system($cmd) == 0 or say("Ecasound exited with error: ", $?>>8), return;
	} 
	::rememoize() if $config->{opts}->{R}; # usually handled by reconfigure_engine() 
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
#### UNUSED 
sub edits_enabled {
	my $track = shift;
	my $bus;
	$bus = $bn{$track->name}
	and $bus->rw ne 'OFF'
	and $track->rec_status eq 'REC' 
	and $track->rec_defeat
	and $track->is_mix_track
}
##### 

sub set_track_class {
	my ($track, $class) = @_;
	bless $track, $class;
	$track->set(class => $class);
}


sub busify {

	# does not set an existing bus to REC or MON!
	
	my $track = shift;
	my $name = $track->name;

	# create the bus if needed
	# create or convert named track to mix track
	
	::add_sub_bus($name) unless $track->is_system_track;

}
sub unbusify {
	my $track = shift;
	return if $track->is_system_track;
	$track->set( rw => 'MON',
                 rec_defeat => 0);
	$track->set_track_class($track->was_class // '::Track');
}

sub adjusted_length {
	my $track = shift;
	my $setup_length;
	if ($track->region_start){
		$setup_length = 	$track->adjusted_region_end_time
				  - $track->adjusted_region_start_time
	} else {
		$setup_length = 	$track->wav_length;
	}
	$setup_length += $track->adjusted_playat_time;
}

sub version_comment {
	my ($track, $v) = @_;
	my $text   = $track->{version_comment}{$v}{user};
	$text .= " " if $text;
	my $system = $track->{version_comment}{$v}{system};
	$text .= "* $system" if $system;
	"$v: $text\n" if $text;
}
# Modified from Object.p to save class
sub as_hash {
	my $self = shift;
	my $class = ref $self;
	bless $self, 'HASH'; # easy magic
	#print yaml_out $self; return;
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


sub capture_latency {
	my $track = shift;
	if (my $io = $::IO::by_name{$track->name}->{input}){
		$io->capture_latency()
	}
	else { logit('::Track','logconfess',"didn't get IO object, got $io")}

}
sub playback_latency {
	my $track = shift;
	if (my $io = $::IO::by_name{$track->name}->{output}){
		$io->playback_latency()
	}
	else { logit('::Track','logconfess',"didn't get IO object, got $io")}
}
} # end package

# subclasses


{
package ::SimpleTrack; # used for Master track
use Modern::Perl; use Carp; use ::Log qw(logit);
no warnings qw(uninitialized redefine);
our @ISA = '::Track';
sub rec_status { $_[0]->rw ne 'OFF' ? 'REC' : 'OFF' }
#sub rec_status_display { $_[0]->rw ne 'OFF' ? 'MON' : 'OFF' }
sub busify {}
sub unbusify {}
}
{
package ::MasteringTrack; # used for mastering chains 
use Modern::Perl; use ::Log qw(logit);
no warnings qw(uninitialized redefine);
our @ISA = '::SimpleTrack';

sub rec_status{
	my $track = shift;
	$mode->{mastering} ? 'MON' :  'OFF';
}
sub source_status {}
sub group_last {0}
sub version {0}
}
{
package ::SlaveTrack; # for instrument monitor bus
use Modern::Perl; use ::Log qw(logit);
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
package ::CacheRecTrack; # for graph generation
use ::Log qw(logit);
our @ISA = qw(::SlaveTrack);
sub current_version {
	my $track = shift;
	my $target = $tn{$track->target};
		$target->last + 1
# 	if ($target->rec_status eq 'MON'
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
use ::Log qw(logit);
our @ISA = qw(::Track);
sub current_version {	
	my $track = shift;
	my $last = $track->last;
	my $status = $track->rec_status;
	#logit('::Track','debug', "last: $last status: $status");
	if 	($status eq 'REC'){ return ++$last}
	elsif ( $status eq 'MON'){ return $track->monitor_version } 
	else { return 0 }
}
sub rec_status {
	my $track = shift;
	return 'REC' if $track->rw eq 'REC';
	::Track::rec_status($track);
}
}
{
package ::EditTrack; use Carp qw(carp cluck);
use ::Log qw(logit);
our @ISA = '::Track';
our $AUTOLOAD;
sub AUTOLOAD {
	my $self = shift;
	logit('::Track','debug', $self->name, ": args @_");
    # get tail of method call
    my ($call) = $AUTOLOAD =~ /([^:]+)$/;
	$::Edit::by_name{$self->name}->$call(@_);
}
sub DESTROY {}
sub current_version {	
	my $track = shift;
	my $last = $track->last;
	my $status = $track->rec_status;
	#logit('::Track','debug', "last: $last status: $status");
	if 	($status eq 'REC' and ! $track->rec_defeat){ return ++$last}
	elsif ( $status eq 'MON'){ return $track->monitor_version } 
	else { return 0 }
}
sub playat_time {
	logit('::Track','logcluck',$_[0]->name . "->playat_time");
	$_[0]->play_start_time
}
}
{
package ::VersionTrack;
use ::Log qw(logit);
our @ISA ='::Track';
sub set_version {}
sub versions { [$_[0]->version] }
}
{
package ::MixTrack;
use ::Log qw(logit);
our @ISA ='::Track';
# as a mix track, I have no sources of my own
# when status is REC
sub input_path { 
	my $track = shift;
	return $track->rec_status eq 'MON'
		?  $track->SUPER::input_path()	
		:  ()
}
}


# ----------- Track_subs -------------
{
package ::;
use Modern::Perl;

# usual track

sub add_track {

	logsub("&add_track");
	#return if transport_running();
	my ($name, @params) = @_;
	my %vals = (name => $name, @params);
	my $class = $vals{class} // '::Track';
	{ no warnings 'uninitialized';	
	logit('::Track','debug', "name: $name, ch_r: $gui->{_chr}, ch_m: $gui->{_chm}");
	}	
	say("$name: track name already in use. Skipping."), return 
		if $tn{$name};
	say("$name: reserved track name. Skipping"), return
	 	if grep $name eq $_, @{$mastering->{track_names}}; 

	my $track = $class->new(%vals);
	return if ! $track; 
	$this_track = $track;
	logit('::Track','debug', "ref new track: ", ref $track); 
	$track->source($gui->{_chr}) if $gui->{_chr};
#		$track->send($gui->{_chm}) if $gui->{_chm};

	my $bus = $bn{$track->group}; 
	command_process('for mon; mon') if $mode->{preview} and $bus->rw eq 'MON';
	$bus->set(rw => 'REC') unless $track->target; # not if is alias

	# normal tracks default to 'REC'
	# track aliases default to 'MON'
	$track->set(rw => $track->target
					?  'MON'
					:  'REC') ;
	$gui->{_track_name} = $gui->{_chm} = $gui->{_chr} = undef;

	set_current_bus();
	$ui->track_gui($track->n);
	logit('::Track','debug', "Added new track!\n", sub{$track->dump});
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
	my $dir =  join_path(project_root(), $project_name, '.wav'); 
	if ( -d $dir ){
		if ( glob "$dir/$track*.wav"){
			print "Found target WAV files.\n";
			my @params = (target => $track, project => $project_name);
			add_track( $name, @params );
		} else { print "No WAV files found.  Skipping.\n"; return; }
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
	
	my $vol_id = cop_add({
				chain => $n, 
				type => $config->{volume_control_operator},
				cop_id => $ti{$n}->vol, # often undefined
				});
	
	$ti{$n}->set(vol => $vol_id);  # save the id for next time
	$vol_id;
}
sub add_pan_control {
	my $n = shift;
	return unless need_vol_pan($ti{$n}->name, "pan");

	my $pan_id = cop_add({
				chain => $n, 
				type => 'epp',
				cop_id => $ti{$n}->pan, # often undefined
				});
	
	$ti{$n}->set(pan => $pan_id);  # save the id for next time
	$pan_id;
}

} # end package

1;
__END__


