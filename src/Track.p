
# ---------- Track -----------
use strict;
package ::Track;
our $VERSION = 1.0;
our ($debug);
local $debug = 0;
#use Exporter qw(import);
#our @EXPORT_OK = qw(track);
use ::Assign qw(join_path);
use ::Wav;
#use Memoize qw(memoize unmemoize);
#memoize('rec_status');
use Carp;
use IO::All;
use vars qw($n %by_name @by_index %track_names);
our @ISA = '::Wav';
$n = 0; 	# incrementing numeric key
@by_index = ();	# return ref to Track by numeric key
%by_name = ();	# return ref to Track by name

# attributes offset, loop, delay for entire setup
# attribute  modifiers
# new attribute will be 
use ::Object qw( 		name
						active

						ch_r 
						ch_m 
						ch_count
						
						rw

						vol  
						pan 
						latency

						old_vol_level
						old_pan_level
						ops 
						offset 

						n 
						group 

						
						delay
						start_position
						length
						looping

						hide
						modifiers

						jack_source
						jack_send
						source_select
						send_select
						
						);

# Note that ->vol return the effect_id 
# ->old_volume_level is the level saved before muting
# ->old_pan_level is the level saved before pan full right/left
# commands

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
			# print $track->name, " hide: ", $track->hide, $/;
			if ($track->hide) {
				$track->set(hide => 0);
				return $track;

			} else {
		carp  ("track name already in use: $vals{name}\n"), return
		 if $track_names{$vals{name}}; 

		}
	}
	my $n = $vals{n} ? $vals{n} : ++$n; 
	my $object = bless { 


		## 		defaults ##

					name 	=> "Audio_$n", 
					group	=> 'Tracker', 
					rw   	=> 'REC', 
					n    	=> $n,
					ops     => [],
					active	=> undef,
					ch_r 	=> undef,
					ch_m 	=> undef,
					ch_count => 1,
					vol  	=> undef,
					pan 	=> undef,

					modifiers => q(), # start, reverse, audioloop, playat

					
					delay	=> undef, # after how long we start playback
					                  # the term 'offset' is used already
					start_position => undef, # where we start playback from
					length => undef, # how long we play back
					looping => undef, # do we repeat our sound sample

					hide     => undef, # for 'Remove Track' function
					source_select => q(soundcard),
					send_select => undef,

					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	$track_names{$vals{name}}++;
	#print "names used: ", ::yaml_out( \%track_names );
	$by_index[$n] = $object;
	$by_name{ $object->name } = $object;
	::add_latency_compensation($n);	
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


sub dir { ::this_wav_dir() } # replaces dir field

sub full_path { my $track = shift; join_path $track->dir , $track->current }

sub group_last {
	my $track = shift;
	my $group = $::Group::by_name{$track->group}; 
	#print join " ", 'searching tracks:', $group->tracks, $/;
	my $max = 0;
	map{ 
		my $track = $_;
		my $last;
		$last = $track->last ? $track->last : 0;
		#print "track: ", $track->name, ", last: $last\n";

		$max = $last if $last > $max;

	}	map { $by_name{$_} } $group->tracks;
	$max;
}

sub current {	 # depends on ewf status
	my $track = shift;
	my $last = $track->current_version;
	#print "last found is $last\n"; 
	if 	($track->rec_status eq 'REC'){ 
		return $track->name . '_' . $last . '.wav'}
	elsif ( $track->rec_status eq 'MON'){ 

	# here comes the logic that enables .ewf support, 
	# using conditional $track->delay or $track->length or $track->start_position ;
	# to decide whether to rewrite file name from .wav to .ewf
	
		no warnings;
		my $filename = $track->targets->{ $track->monitor_version } ;
		use warnings;
		return $filename  # setup directly refers to .wav file
		  unless $track->delay or $track->length or $track->start_position ;

		  # setup uses .ewf parameters, expects .ewf file to
		  # be written

		#filename in chain setup now point to .ewf file instead of .wav
		
		$filename =~ s/\.wav$/.ewf/;
		return $filename;
	} else {
		$debug and print "track ", $track->name, ": no current version\n" ;
		return undef;
	}
}

sub full_wav_path {  # independent of ewf status
	my $track = shift; 
	join_path $track->dir , $track->current_wav
}

sub current_wav {	# independent of ewf status
	my $track = shift;
	my $last = $track->current_version;
	#print "last found is $last\n"; 
	if 	($track->rec_status eq 'REC'){ 
		return $track->name . '_' . $last . '.wav'}
	elsif ( $track->rec_status eq 'MON'){ 
		no warnings;
		my $filename = $track->targets->{ $track->monitor_version } ;
		use warnings;
		return $filename;
	} else {
		# print "track ", $track->name, ": no current version\n" ;
		return undef;
	}
}
sub write_ewf {
	$::debug2 and print "&write_ewf\n";
	my $track = shift;
	my $wav = $track->full_wav_path;
	my $ewf = $wav;
	$ewf =~ s/\.wav$/.ewf/;
	#print "wav: $wav\n";
	#print "ewf: $ewf\n";

	my $maybe_ewf = $track->full_path; 
	$wav eq $maybe_ewf and unlink( $ewf), return; # we're not needed
	$ewf = File::Spec::Link->resolve_all( $ewf );
	carp("no ewf parameters"), return 0 if !( $track->delay or $track->start_position or $track->length);

	my @lines;
	push @lines, join " = ", "source", $track->full_wav_path;
	map{ push @lines, join " = ", $_, eval qq(\$track->$_) }
	grep{ eval qq(\$track->$_)} qw(delay start_position length);
	my $content = join $/, @lines;
	#print $content, $/;
	$content > io($ewf) ;
	return $content;
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
# sub monitor_version {
# 	my $track = shift;
# 	$track->active ? $track->active : $track->last;
# }

sub rec_status {
#	$::debug2 and print "&rec_status\n";
	my $track = shift;
	my $monitor_version = $track->monitor_version;
	my $source = $track->source;
	my $group = $::Group::by_name{$track->group};
	$debug and print "rec status track: ", $track->name, 
		" group: $group, source: $source, monitor version: $monitor_version\n";

	if ( $group->rw eq 'OFF'
		or $track->rw eq 'OFF'
		or $track->rw eq 'MON' and ! $monitor_version 
		or $track->hide 
		# ! $track->full_path;
		
	){ 				  'OFF' }

	# When we reach here, $group->rw and $track->rw are REC or MON
	# so the result will be REC or MON if conditions are met

	# first case, possible REC status
	
	elsif (	$track->rw eq 'REC' 
				and $group->rw eq 'REC') {

		if ( $source =~ /\D/ ){ # jack client
				::jack_client($source,'output')
					?  'REC'
					:  maybe_monitor($monitor_version)
		} elsif ( $source =~ /\d/ ){ # soundcard channel
					   'REC'
		} else { 	  maybe_monitor($monitor_version)  }
		
			
	}
	# second case, possible MON status
	
	else { 			maybe_monitor($monitor_version)

	}
}

sub maybe_monitor {
	my $monitor_version = shift;
	return 'MON' if $monitor_version and $::mon_setup->status;
	return 'OFF';
}

# the following methods handle effects
sub remove_effect {
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
	return if $track->source_select eq 'jack';

	# no need to route a signal at channel 1
	return if ! $track->ch_r or $track->ch_r == 1; 
	
	my $route = "-chmove:" . $track->ch_r . ",1"; 
	if ( $track->ch_count == 2){
		$route .= " -chmove:" . ($track->ch_r + 1) . ",2";
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
	 
	return q() if $track->send_select eq 'jack'  or ! $track->aux_output;           
	route(2,$track->aux_output); # stereo signal
}

# The following subroutine is not an object method.

sub all { @by_index[1..scalar @by_index - 1] }


### Commands and their support functions

sub source { # command for setting, showing track source
	my ($track, $source) = @_;

	if ( ! $source ){
		if ( 	$track->source_select eq 'jack'
				and $track->jack_source ){
			$track->jack_source
		} elsif ( $track->source_select eq 'soundcard') { 
			$track->input 
		} else { undef }
	} elsif ( $source =~ m(\D) ){
		if ( $::jack_running ){
			$track->set(source_select => "jack");
			$track->set(jack_source => $source);
			my $name = $track->name;
			print <<CLIENT if ! ::jack_client($source, 'output');
$name: output port for JACK client "$source" not found. 
Cannot set "$name" to REC.
CLIENT
		} else {
			print "JACK server not running.\n";
			$track->source;
		} 
	} else {  # must be numerical
		$track->set(ch_r => $source);
		$track->set(source_select =>'soundcard');
		$track->input;
	}
} 

sub set_source { # called from parser 
	my $track = shift;
	my $source = shift;
	if ($source eq 'null'){
		$track->set(group => 'null');
		return
	}
	my $old_source = $track->source;
	my $new_source = $track->source($source);
	my $object = input_object( $new_source );
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

sub set_send {
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
sub send {
	my ($track, $send) = @_;
	if ( ! defined $send ){
		if ( $track->send_select eq 'jack'
			 and $track->jack_send  ) { $track->jack_send } 
		elsif ( $track->send_select eq 'soundcard' ){ $track->aux_output }
		else { undef }
	} elsif ( $send eq 'off'  or $send eq '0') { 
		$track->set(send_select => 'off');
		undef;
	} elsif ( $send =~ m(\D) ){ ## non-digit, indicating jack client name
		if ( $::jack_running ){
			$track->set(jack_send => $send);
			$track->set(send_select => 'jack');
			$track->jack_send
		} else {
			print $track->name, 
			": cannot send to JACK client. jackd is not running\n";
			$track->source;
		} 
	} else {  # must be numerical
		if ( $send > 2){ 
			$track->set(ch_m => $send);
			$track->set(send_select =>'soundcard');
		} else { 
		print "All sends must go to soundcard channel 3 or higher. Skipping.\n";
		}
		$track->aux_output;
	}
} 

sub send_output {  # for io lists / chain setup

					# assumes $track->send exists
					
	my $track = shift;
	if ( $track->send_select eq 'soundcard' ){ 
		if ($::jack_running ){
			[qw(jack system)]
		} else {
			['device', $::playback_device ]
		}
	} elsif ( $track->send_select eq 'jack' ) {
		if ( $::jack_running ){
			['jack', $track->send]
		} else {
			print $track->name, 
q(: auxilary send to JACK client specified, but jackd is not running.
Skipping.
);
			[qw(skip skip)]; 
		}
	} else { 
				print q(: unexpected send_select value: "), 
				$track->send_select, qq("\n);
			[qw(skip skip)]; 
	}
}

sub source_input { # for io lists / chain setup
	my $track = shift;
	if ( $track->source_select eq 'soundcard' ){ 
		::input_type_object()
	}
	elsif ( $track->source_select eq 'jack' ){
		if ($::jack_running ){
			['jack', $track->source ]
		} else { 
			#print $track->name, ": no JACK client found\n";
			[qw(lost lost)]
		}
    } else { 
			print $track->name, ": missing source_select: \"",
					$track->source_select, qq("\n);
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
	$track->ch_m > 2 ? $track->ch_m : undef 
}

sub input_object { # for text display
	my $source = shift; # string
	if ( $source =~ /\D/ ){
		qq(JACK client "$source")
	} elsif ( $source =~ /\d/ ){
		qq(soundcard channel $source)
	} 
}

sub output_object {   # text for user display
	my $track = shift;
	my $send = $track->send;
	return unless $send;
	$send =~ /\D/ 
		? qq(JACK client "$send")
		: qq(soundcard channel $send);
}
sub client_status {
	my ($track_status, $client, $direction) = @_;
	if ($client =~ /\D/){
		if(::jack_client($client, $direction) and $track_status eq 'REC' )
			{ $client }
		else { "[$client]" }
	} elsif ($client =~ /\d+/ ){ 
		if ( $track_status eq 'REC'){ $client }
		else { "[$client]" }
	} else { q() }
}
sub source_status {
	my $track = shift;
	client_status($track->rec_status, $track->source, 'output')
}
sub send_status {
	my $track = shift;
	client_status('REC', $track->send, 'input')
}

sub set_rec {
	my $track = shift;
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
			effect_update_copp_set($track->n, $track->vol, 0, 0  );
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
		effect_update_copp_set($track->n, $track->vol, 0, $track->old_vol_level);
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
# subclass


package ::SimpleTrack; # used for Master track
our @ISA = '::Track';
use ::Object qw( 		name
						active

						ch_r 
						ch_m 
						ch_count
						
						rw

						vol  
						pan 
						latency

						old_vol_level
						old_pan_level
						ops 
						offset 

						n 
						group 

						
						delay
						start_position
						length
						looping

						hide
						modifiers

						jack_source
						jack_send
						source_select
						send_select
						
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




# ---------- Group -----------

package ::Group;
our $VERSION = 1.0;
#use Exporter qw(import);
#our @EXPORT_OK =qw(group);
use Carp;
use vars qw(%by_name @by_index $n);
our @ISA;
$n = 0; 
@by_index = ();
%by_name = ();

use ::Object qw( 	name
					rw
					version 
					n	
					);

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
	my $n = $vals{n} ? $vals{n} : ++$n; 
	my $object = bless { 	
		name 	=> "Group $n", # default name
		rw   	=> 'REC', 
		n => $n,
		@_ 			}, $class;
	#return $object if $skip_index;
	#print "object type: ", ref $object, $/;
	$by_index[$n] = $object;
	$by_name{ $object->name } = $object;
	$object;
}


sub tracks { # returns list of track names in group 

	my $group = shift;
	my @all = ::Track::all;
	# map {print "type: ", ref $_, $/} ::Track::all; 
	map{ $_->name } grep{ $_->group eq $group->name } ::Track::all();
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
