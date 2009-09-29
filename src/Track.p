
# ---------- Track -----------
use feature ":5.10";
use strict;
package ::Track;
our $VERSION = 1.0;
our ($debug);
local $debug = 0;
#use Exporter qw(import);
#our @EXPORT_OK = qw(track);
use ::Assign qw(join_path);
use ::Wav;
#use Memoize;
#memoize ('get_length'); # subroutine, not object method
#memoize('rec_status');
use Carp;
use IO::All;
use vars qw($n %by_name @by_index %track_names %by_index @all);
our @ISA = '::Wav';

initialize();

# attributes offset, loop, delay for entire setup
# attribute  modifiers
# new attribute will be 
use ::Object qw(

[% qx(cat ./track_fields) %]

);
# Note that ->vol return the effect_id 
# ->old_volume_level is the level saved before muting
# ->old_pan_level is the level saved before pan full right/left
# commands

sub initialize {
	$n = 0; 	# incrementing numeric key
	@all = ();
	%by_index = ();	# return ref to Track by numeric key
	%by_name = ();	# return ref to Track by name
	%track_names = (); 
}

sub new {
	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	# The indexing is bypassed and an object returned 
	# if an index n is supplied as  a parameter
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	#print "test 1\n";
	if ($by_name{$vals{name}}){
	#print "test 2\n";
	my $track = $by_name{$vals{name}};
		# print $track->}ame, " hide: ", $track->hide, $/;
		if ($track->hide) {
			$track->set(hide => 0);
			return $track;

		} else {
		print("track name already in use: $vals{name}\n"), return
		 if $track_names{$vals{name}}; 
		}
	}
	print("reserved track name: $vals{name}\n"), return
	 if  ! $::mastering_mode 
		and grep{$vals{name} eq $_} @::mastering_track_names ; 

	my $n = $vals{n} ? $vals{n} : ++$n; 
	my $object = bless { 


		## 		defaults ##

					name 	=> "Audio_$n", 
					group	=> 'Main', 
		#			rw   	=> 'REC', # ::add_track() sets REC if necessary
					n    	=> $n,
					ops     => [],
					active	=> undef,
					ch_count => 1,
					vol  	=> undef,
					pan 	=> undef,

					modifiers => q(), # start, reverse, audioloop, playat
					
					looping => undef, # do we repeat our sound sample

					source_type => q(soundcard),
					source_id   => 1,

					send_type => undef,
					send_id   => undef,

					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	$track_names{$vals{name}}++;
	#print "names used: ", ::yaml_out( \%track_names );
	$by_index{$n} = $object;
	$by_name{ $object->name } = $object;
	push @all, $object;
	#::add_latency_compensation($n);	
	::add_pan_control($n);
	::add_volume_control($n);

	#my $group = $::Group::by_name{ $object->group }; 

	# create group if necessary
	#defined $group or $group = ::Group->new( name => $object->group );
	#my @existing = $group->tracks ;
	#$group->set( tracks => [ @existing, $object->name ]);
	$::this_track = $object;
	$object;
	
}


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

sub full_path { my $track = shift; join_path $track->dir, $track->current_wav }

sub group_last {
	my $track = shift;
	my $group = $::Group::by_name{$track->group}; 
	#print join " ", 'searching tracks:', $group->tracks, $/;
	$group->last;
}

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
		$debug and print "track ", $track->name, ": no current version\n" ;
		undef; 
	}
}

sub full_wav_path {  
	my $track = shift; 
	join_path $track->dir, $track->current_wav
}

sub current_version {	
	my $track = shift;
	my $last = $::use_group_numbering 
					? $track->group_last
					: $track->last;
	my $status = $track->rec_status;
	#$debug and print "last: $last status: $status\n";
	if 	($track->rec_status eq 'REC'){ return ++$last}
	elsif ( $track->rec_status eq 'MON'){ return $track->monitor_version } 
	else { return undef }
}

sub monitor_version {
	my $track = shift;

	my $group = $::Group::by_name{$track->group};
	return $track->active if $track->active;
	return $group->version if $group->version 
				and grep {$group->version  == $_ } @{$track->versions};
	return undef if $group->version;
	$track->last;
}

sub rec_status {
#	$::debug2 and print "&rec_status\n";
	my $track = shift;
	
	#my $source_id = $track->source_id;
	my $monitor_version = $track->monitor_version;

	my $group = $::Group::by_name{$track->group};
	$debug and print "track: ", $track->name, ", source: ",
		$track->source_id, ", monitor version: $monitor_version\n";

	# first, check for conditions resulting in status 'OFF'

	if ( $group->rw eq 'OFF'
		or $track->rw eq 'OFF'
		or $track->hide 
	){ 	return			  'OFF' }

	# having reached here, we know $group->rw and $track->rw are REC or MON
	# so the result will be REC or MON if conditions are met

	# second, set REC status if possible
	
	elsif (	$track->rw eq 'REC' and $group->rw eq 'REC') {
		given( $track->source_type){
			when('jack_client'){
				::jack_client($track->source_id,'output')
					?  'REC'
					:  maybe_monitor($monitor_version)
			}
			when('soundcard'){ return 'REC' }
			when('loop'){ return 'REC' }

			default { croak $track->name. ": missing source type" }
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
	$track->rec_defeat ? "[$status]" : $status;
}

sub maybe_monitor {
	my $monitor_version = shift;

	# I don't want the dependency on $::raw_monitor_input status
	# although it could be helpful for diagnostic and UI purposes
	return 'MON' if $monitor_version and $::raw_monitor_input->status;
	return 'OFF';
}

# the following methods handle effects
sub remove_effect { # doesn't touch %cops or %copp data structures 
	my $track = shift;
	my @ids = @_;
	$track->set(ops => [ grep { my $existing = $_; 
									! grep { $existing eq $_
									} @ids }  
							@{$track->ops} ]);
}

# the following methods are for channel routing

sub mono_to_stereo { 
	my $track = shift;
	my $cmd = "file " .  $track->full_path;
	if ( 	$track->ch_count == 2 and $track->rec_status eq 'REC'
		    or  -e $track->full_path
				and qx(which file)
				and qx($cmd) =~ /stereo/i ){ 
		return q(); 
	} elsif ( $track->ch_count == 1 and $track->rec_status eq 'REC'
				or  -e $track->full_path
				and qx(which file)
				and qx($cmd) =~ /mono/i ){ 
		return " -chcopy:1,2 " 
	} else { # do nothing for higher channel counts
	} # carp "Track ".$track->name.": Unexpected channel count\n"; 
}

sub rec_route {
	no warnings qw(uninitialized);
	my $track = shift;
	
	# no need to route a jack client
	return if $track->source_type eq 'jack_client';
	return if $track->source_type eq 'loop';

	# no need to route a signal at channel 1
	return if ! $track->source_id or $track->source_id == 1; 
	
	my $route = "-chmove:" . $track->source_id . ",1"; 
	if ( $track->ch_count == 2){
		$route .= " -chmove:" . ($track->source_id + 1) . ",2";
	}
	return $route;
	
}
sub route {

	# routes signals 1,2,3,...$width to $dest + 0, $dest + 1, $dest + 2,... 
	
	my ($width, $dest) = @_;
	return undef if $dest == 1 or $dest == 0;
	# print "route: width: $width, destination: $dest\n\n";
	my $offset = $dest - 1;
	my $map ;
	for my $c ( map{$width - $_ + 1} 1..$width ) {
		$map .= " -chmove:$c," . ( $c + $offset);
		#$map .= " -eac:0,"  . $c;
	}
	$map;
}

# channel shifting for multi rule 
#
sub pre_send {
	#$debug2 and print "&pre_send\n";
	my $track = shift;

	# we channel shift only to soundcard channel numbers higher than 3,
	# not when the send is to a jack client
	 
	return q() if $track->send_type eq 'jack_client'  or ! $track->aux_output;           
	route(2,$track->aux_output); # stereo signal
}

sub remove {
	my $track = shift;
#	$::ui->remove_track_gui($track->n); TODO
	map{ ::remove_effect($_) } @{ $track->ops };
	delete $by_index{$track->n};
	delete $by_name{$track->name};
	@all = grep{ $_->n != $track->n} @all;
}


# The following two subroutines are not object methods.

sub all { @all }

{ my %non_user = map{ $_, 1} qw( Master Mixdown Eq Low Mid High Boost );
sub user {
	grep{ ! $non_user{$_} } map{$_->name} @all
}
}
	

### Commands and their support functions

# The conditional-laced code allows user to use 'source'
# and 'send' commands in JACK and ALSA modes.

sub soundcard_channel { $_[0] // 1 }
sub set_io {
	my ($track, $direction, $id) = @_;
	# $direction: send | source
	
	# these are the field names
	my $type_field = $direction."_type";
	my $id_field   = $direction."_id";

	# respond to a query (no argument)
	if ( ! $id ){ return $track->$type_field ? $track->$id_field : undef }

	
	# set values, returning new setting
	
	given ( ::dest_type( $id ) ){
		when ('jack_client'){
			if ( $::jack_running ){
				$track->set($type_field => 'jack_client',
							$id_field   => $id);
				my $name = $track->name;
				print <<CLIENT if ! ::jack_client($id, 'output');
$name: $direction port for JACK client "$id" not found. 
CLIENT
				return $track->source_id;
			} else {
		say "JACK server not running! Cannot set JACK client as track source.";
				return $track->source_id;
			} 
		}

		when('soundcard'){ 
			$track->set( $id_field => $id, 
						 $type_field => 'soundcard');
			return soundcard_channel( $id )
		}
		when('loop'){ 
			$track->set( $id_field => $id, 
						 $type_field => 'loop');
			return $id;
		}
	}
} 

# the following subroutines support IO objects

sub soundcard_input {
	my $track = shift;
	if ($::jack_running) {
		my $start = track->source_id;
		my $end   = $start + $track->ch_count - 1;
		['jack_multi' , join q(,),q(jack_multi),
			map{"system:capture_$_"} $start..$end]
	} else { ['device' , $::capture_device] }
}
sub soundcard_output {
 	$::jack_running 
		? [qw(jack_client system)]  
		: ['device', $::alsa_playback_device] 
}
sub source_input {
	my $track = shift;
	given ( $track->source_type ){
		when ( 'soundcard'  ){ return $track->soundcard_input }
		when ( 'jack_client'){
			if ( $::jack_running ){ return ['jack_client', $track->source_id] }
			else { 	carp($track->name. ": cannot set source ".$track->source_id
				.". JACK not running."); return [undef, undef] }
		}
		when ( 'loop'){ return ['loop',$track->source_id ] } 
	}
}

sub send_output {
	my $track = shift;
	given ($track->send_type){
		when ( 'soundcard' ){ 
			if ($::jack_running) {
				my $start = $track->send_id; # Assume channel will be 3 or greater
				my $end   = $start + 1; # Assume stereo
				return ['jack_multi', join q(,),q(jack_multi),
					map{"system:playback_$_"} $start..$end]
			} else {return [ 'device', $::alsa_playback_device] }
		}
		when ('jack_client') { 
			if ($::jack_running){return [ 'jack_client', $track->send_id] }
			else { carp $track->name . 
					q(: auxilary send to JACK client specified,) .
					q( but jackd is not running.  Skipping.);
					return [qw(undef, undef)];
			}
		}
		when ('loop') { return [ 'loop', $track->send_id ] }
			
		carp $track->name, ": missing or illegal send_type: ", 
			$track->send_type, $/;
	}
 };

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
	my $source = shift;

# Special handling for 'null', used for non-input (i.e. metronome) tracks

	if ($source eq 'null'){
		$track->set(group => 'null');
		return
	}

	my $old_source = $track->source;
	my $new_source = $track->source($source);
	my $object = $track->input_object;
	if ( $old_source  eq $new_source ){
		print $track->name, ": input unchanged, $object\n";
	} else {
		print $track->name, ": input set to $object\n";
	}
}

sub set_version {
	my ($track, $n) = @_;
	my $name = $track->name;
	if ($n == 0){
		print "$name: following latest version\n";
		$track->set(active => $n)
	} elsif ( grep{ $n == $_ } @{$track->versions} ){
		print "$name: anchoring version $n\n";
		$track->set(active => $n)
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

# input channel number, may not be used in current setup


sub input {   	
	my $track = shift;
	$track->ch_r ? $track->ch_r : 1
}

# send channel number, may not be used in current setup

sub aux_output { 
	my $track = shift;
	$track->send_id > 2 ? $track->send_id : undef 
}

sub object_as_text {
	my ($track, $direction) = @_; # $direction: source | send
	my $type_field = $direction."_type";
	my $id_field   = $direction."_id";
	
	my $output;
	given ($track->$type_field){
		when('soundcard')  { $output = "soundcard channel "}
		when('jack_client'){ $output = "JACK client "}
		when('loop')       { $output = "loop device "}
	}
	$output .= $track->$id_field
}

sub input_object { # for text display
	my $track = shift;
	$track->object_as_text('source');
}

sub output_object {   # text for user display
	my $track = shift;
	$track->object_as_text('send');

}
sub client_status {
	my ($track_status, $client, $direction) = @_;
	my $type = ::dest_type($client);
	if ($type eq 'loop'){
		my ($bus) =  $client =~ /loop,(\w+)/;
		$track_status eq 'REC' ? $bus : undef;  
	}
	elsif ($track_status eq 'OFF') {"[$client]"}
	elsif ($type eq 'jack_client'){ 
		::jack_client($client, $direction) 
			? $client 
			: "[$client]" 
	} elsif ($type eq 'soundcard'){ 
		$client 
			?  ($track_status eq 'REC' 
				?  $client 
				: "[$client]")
			: undef
	} else { q() }
}
sub source_status {
	my $track = shift;
	return if (ref $track) =~ /MasteringTrack/;
	client_status($track->rec_status, $track->source, 'output')
}
sub send_status {
	my $track = shift;
	client_status('REC', $track->send, 'input')
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
	$track->set(rw => 'REC');
	$track->rec_status eq 'REC'	or print $track->name, 
		": set to REC, but current status is ", $track->rec_status, "\n";
}
sub set_mon {
	my $track = shift;
	$track->set(rw => 'MON');
	$track->rec_status eq 'MON'	or print $track->name, 
		": set to MON, but current status is ", $track->rec_status, "\n";
}
sub set_off {
	my $track = shift;
	$track->set(rw => 'OFF');
	print $track->name, ": set to OFF\n";
}

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
sub mute {
	package ::;
	my $track = shift;
	my $nofade = shift;
	$track or $track = $::this_track;
	# do nothing if already muted
	return if $track->old_vol_level();

	# mute if non-zero volume
	if ( $::copp{$track->vol}[0]){   
		$track->set(old_vol_level => $::copp{$track->vol}[0]);
		if ( $nofade ){ 
			effect_update_copp_set( $track->vol, 0, 0  );
		} else { 
			fadeout( $track->vol );
		}
	}
}
sub unmute {
	package ::;
	my $track = shift;
	my $nofade = shift;
	$track or $track = $::this_track;

	# do nothing if we are not muted
#	return if $::copp{$track->vol}[0]; 
	return if ! $track->old_vol_level;

	if ( $nofade ){ 
		effect_update_copp_set($track->vol, 0, $track->old_vol_level);
	} else { 
		fadein( $track->vol, $track->old_vol_level);
	}
	$track->set(old_vol_level => 0);
}

sub ingest  {
	my $track = shift;
	my ($path, $frequency) = @_;
	my $version  = ${ $track->versions }[-1] + 1;
	if ( ! -r $path ){
		print "$path: non-existent or unreadable file. No action.\n";
		return;
	} else {
		my $type = qx(file $path);
		my $channels;
		if ($type =~ /mono/i){
			$channels = 1;
		} elsif ($type =~ /stereo/i){
			$channels = 2;
		} else {
			print "$path: unknown channel count. Assuming mono. \n";
			$channels = 1;
		}
	my $format = ::signal_format($::raw_to_disk_format, $channels);
	my $cmd = qq(ecasound -f:$format -i:resample-hq,$frequency,$path -o:).
		join_path(::this_wav_dir(),$track->name."_$version.wav\n");
		print $cmd;
		system $cmd or print "error: $!\n";
	} 
}

sub playat_output {
	my $track = shift;
	if ( $track->playat ){
		"playat" , $track->playat
	}
}

sub select_output {
	my $track = shift;
	if ( $track->region_start and $track->region_end){
		my $end = $track->region_ending;
		my $start = $track->region_start;
		my $length = $end - $start;
		"select", $start, $length
	}
}

# the following subroutines support IO objects


sub modify_rules_list {
	my $track = shift;
	my @rules = @_;
	my %have;
	map { $have{$_}++ } @rules;
	map { push @rules, $_ unless $have{$_} } $track->rules_add;
	my %skip;
	map { $skip{$_}++ } $track->rules_skip;
	grep { ! $skip{$_} } @rules;
}

sub region_start {
	my $track = shift;
	::Mark::mark_time( $track->{region_start} )
}
sub region_ending {
	my $track = shift;
	if ( $track->{region_end} eq 'END' ){
		return get_length($track->full_path);
	} else {
		::Mark::mark_time( $track->{region_end} )
	}
}
sub playat {
	my $track = shift;
	::Mark::mark_time( $track->{playat} )
}

# subroutine, not object method

sub get_length { 
	
	#$debug2 and print "&get_length\n";
	
	#print "evaluating....\n";
	#carp "my call chain\n";
	my $path = shift;
	package ::;
	eval_iam('cs-disconnect');
	#print "path: $path\n";
	eval_iam('cs-add gl');
	#print eval_iam('cs-selected');
	eval_iam('c-add g');
	#print eval_iam('c-selected');
	eval_iam('ai-add ' . $path);
	eval_iam('ao-add null');
	eval_iam('cs-connect');
	eval_iam('engine-launch');
	eval_iam('ai-select '. $path);
	#print eval_iam('ai-selected');
	my $length = eval_iam('ai-get-length');
	eval_iam('cs-disconnect');
	#print "length: $length\n";
	$length;
}
	
# subclass

package ::SimpleTrack; # used for Master track
our @ISA = '::Track';
use ::Object qw(

[% qx(cat ./track_fields) %]

						);

sub rec_status{

#	$::debug2 and print "&rec_status (SimpleTrack)\n";
	my $track = shift;
	return 'MON' unless $track->rw eq 'OFF';
	'OFF';

}
no warnings;
sub ch_r {
	my $track = shift;
	return '';
}
use warnings;

package ::MasteringTrack; # used for mastering chains 
our @ISA = '::SimpleTrack';
use ::Object qw( 

[% qx(cat ./track_fields) %]
						
						);

sub rec_status{
	my $track = shift;
	$::mastering_mode ? 'MON' :  'OFF';
}
no warnings;
sub group_last {0}
sub version {0}
sub monitor_version {0}
use warnings;

package ::SlaveTrack; # for instrument monitor bus
our @ISA = '::SimpleTrack';
use ::Object qw( 

[% qx(cat ./track_fields) %]
						
						);
sub rec_status {
	my $track = shift;
	$::tn{$track->target}->rec_status ne 'OFF' ? 'MON' : 'OFF';
}
sub monitor_version { undef }

# ---------- Group -----------

package ::Group;
our $VERSION = 1.0;
#use Exporter qw(import);
#our @EXPORT_OK =qw(group);
use Carp;
use vars qw(%by_name @by_index $n);
our @ISA;
initialize();

use ::Object qw( 	name
					rw
					version 
					n	
					);

sub initialize {
	$n = 0; 
	@by_index = ();
	%by_name = ();
}

sub new {

	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	# The indexing is bypassed and an object returned 
	# if an index is given
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak "name missing" unless $vals{name};
	(carp "group name already in use: $vals{name}\n"), 
		return ($by_name{$vals{name}}) if $by_name{$vals{name}};
	#my $skip_index = $vals{n};
	my $n_;
	if ( $vals{n} ){
		$n_ = $vals{n};
		$n = $n_ 
	} else { $n_ = ++$n }; 
	my $object = bless { 	
		name 	=> "Group $n", # default name
		rw   	=> 'REC', 
		n => $n_,
		@_ 			}, $class;
	#return $object if $skip_index;
	#print "object type: ", ref $object, $/;
	$by_index[$n_] = $object;
	$by_name{ $object->name } = $object;
	$object;
}


sub tracks { # returns list of track names in group 

	my $group = shift;
	my @all = ::Track::all;
	# map {print "type: ", ref $_, $/} ::Track::all; 
	map{ $_->name } grep{ $_->group eq $group->name } ::Track::all();
}

sub last {
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


# all groups

sub all { @by_index[1..scalar @by_index - 1] }

# ---------- Op -----------

package ::Op;
our $VERSION = 0.5;
our @ISA;
use ::Object qw(	op_id 
					chain_id 
					effect_id
					parameters
					subcontrollers
					parent
					parent_parameter_target
					
					);


1;

# We will treat operators and controllers both as Op
# objects. Subclassing so controller has special
# add_op  and remove_op functions. 
# 

__END__
