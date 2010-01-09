# ---------- Track -----------
package ::Track;

# Objects belonging to Track and its subclasses
# have a 'class' field that is set when the 
# object is created, and used when restoring
# the object from a serialized state.
#
# So do not re-bless a Track object into
# a different subclass! 

use Modern::Perl;
use Carp;
use File::Copy qw(copy);
use Memoize qw(memoize unmemoize);
no warnings qw(uninitialized redefine);
our $VERSION = 1.0;
our ($debug);
local $debug = 0;
#use Exporter qw(import);
#our @EXPORT_OK = qw(track);
use ::Assign qw(join_path);
use ::Wav;
use IO::All;
use vars qw($n %by_name @by_index %track_names %by_index @all);
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
	@all = ();
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
sub all { @all }

{ my %non_user = map{ $_, 1} qw( Master Mixdown Eq Low Mid High Boost );
sub user {
	grep{ ! $non_user{$_} } map{$_->name} @all
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
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	if (my $track = $by_name{$vals{name}}){
		#if ($track->hide) { $track->set(hide => 0); } 
		print("track name already in use: $vals{name}\n"); 
		return ; # $track;
	}
	print("reserved track name: $vals{name}\n"), return
	 if  ! $::mastering_mode 
		and grep{$vals{name} eq $_} @::mastering_track_names ; 

	my $n = $vals{n} || idx(); 
	my $object = bless { 


		## 		defaults ##
					class	=> $class,
					name 	=> "Audio_$n", 
					group	=> 'Main', 
		#			rw   	=> 'REC', # ::add_track() sets REC if necessary
					n    	=> $n,
					ops     => [],
					active	=> undef,
					width => 1,
					vol  	=> undef,
					pan 	=> undef,

					modifiers => q(), # start, reverse, audioloop, playat
					
					looping => undef, # do we repeat our sound sample

					source_type => q(soundcard),
					source_id   => 1,

					send_type => undef,
					send_id   => undef,
					inserts => {},
					effect_chain_stack => [],
					cache_map => {},
					

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


### object methods

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
	my $group = $::Group::by_name{$track->group}; 
	#print join " ", 'searching tracks:', $group->tracks, $/;
	$group->last;
}

sub last {
	my $track = shift;
	my @versions;
	@versions =  @{ $track->versions };
	$versions[-1] || 0;
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
	if 	($status eq 'REC'){ return ++$last}
	elsif ( $status eq 'MON'){ return $track->monitor_version } 
	else { return 0 }
}

sub monitor_version {
	my $track = shift;

	my $group = $::Group::by_name{$track->group};
	return $track->active if $track->active 
				and grep {$track->active  == $_ } @{$track->versions} ;
	return $group->version if $group->version 
				and grep {$group->version  == $_ } @{$track->versions};
	return undef if $group->version;
	$track->last;
}


sub maybe_monitor { # ordinary sub, not object method
	my $monitor_version = shift;
	return 'MON' if $monitor_version and ! ($::preview eq 'doodle');
	return 'OFF';
}

sub rec_status {
#	$::debug2 and print "&rec_status\n";
	my $track = shift;
	my $bug = shift;
	local $debug;
	$debug //= $bug;
	
	#my $source_id = $track->source_id;
	my $monitor_version = $track->monitor_version;

	my $group = $::Group::by_name{$track->group};
	$debug and say join " ", "group:",$group->name, $group->rw;
	$debug and print "track: ", $track->name, ", source: ",
		$track->source_id, ", monitor version: $monitor_version\n";

	# first, check for conditions resulting in status 'OFF'

	if ( $group->rw eq 'OFF'
		or $track->rw eq 'OFF'
		# or $track->hide 
		or $::preview eq 'doodle' and $track->rw eq 'REC' and 
			$::duplicate_inputs{$track->name}
	){ 	return			  'OFF' }

	# having reached here, we know $group->rw and $track->rw are REC or MON
	# so the result will be REC or MON if conditions are met

	# second, set REC status if possible
	
	elsif (	$track->rw eq 'REC' and $group->rw eq 'REC') {
		given( $track->source_type){
			when('jack_client'){
				::jack_client($track->source_id,'output')
					?  return 'REC'
					:  return maybe_monitor($monitor_version)
			}
			when('jack_port'){ return 'REC' }
			when('soundcard'){ return 'REC' }
			when('track'){ return 'REC' } # maybe $track->rw ??
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


sub region_start_time {
	my $track = shift;
	::Mark::mark_time( $track->region_start )
}
sub region_end_time {
	my $track = shift;
	return if $track->rec_status ne 'MON';
	if ( $track->region_end eq 'END' ){
		return ::get_length($track->full_path);
	} else {
		::Mark::mark_time( $track->region_end )
	}
}
sub playat_time {
	my $track = shift;
	::Mark::mark_time( $track->playat )
}

sub fancy_ops { # returns list 
	my $track = shift;
	grep{ $_ ne $track->vol and $_ ne $track->pan } @{ $track->ops }
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

		if ($track->source_type =~ /soundcard|jack_client|jack_port/){
			( ::input_node($track->source_type) , $track->name)
		} 

	} elsif($track->rec_status eq 'MON' and $::preview ne 'doodle'){

	# create edge representing WAV file input

		('wav_in', $track->name) 

	}
}


### remove and destroy

sub remove_effect { # doesn't touch %cops or %copp data structures 
	my $track = shift;
	my @ids = @_;
	$track->set(ops => [ grep { my $existing = $_; 
									! grep { $existing eq $_
									} @ids }  
							@{$track->ops} ]);
}
sub remove_insert {
	my $track = shift;
	if ( my $i = $track->inserts){
		map{ $::tn{$_}->remove } @{ $i->{tracks} };
		$track->set(inserts => {});
	}
}

# remove track object and all effects

sub remove {
	my $track = shift;
	my $n = $track->n;
	$::ui->remove_track_gui($n); 
 	$::this_track = $::ti{::Track::idx() - 1};
 	map{ ::remove_effect($_) } @{ $track->ops };
 	delete $by_index{$n};
 	delete $by_name{$track->name};
 	@all = grep{ $_->n != $n} @all;
}

	
	

### object methods for text-based commands 

# Reasonable behavior whether 'source' and 'send' commands 
# are issued in JACK or ALSA mode.

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
				my $client_direction = $direction eq 'source' ? 'output' : 'input';
	
				$track->set($type_field => 'jack_client',
							$id_field   => $id);
				my $name = $track->name;
				my $width = scalar @{ ::jack_client($id, $client_direction) };
				$width or say 
					qq($name: $direction port for JACK client "$id" not found.);
				$width ne $track->width and say 
					$track->name, ": track set to ", ::width($track->width),
					qq(, but JACK source "$id" is ), ::width($width), '.';
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

	#say "set source";
	#say "track: ",$track->name;
	#say "source: $source";

# Special handling for 'null', used for non-input (i.e. metronome) tracks

	if ($source eq 'null'){
		$track->set(group => 'null');
		return
	}
	if( $source eq 'jack'){
 		$track->set(source_type => 'jack_port',
 					source_id => $track->name);
 		say $track->name, ": JACK input port is ",$track->source_id,"_in",
 		". Make connections manually or set up a ports list.";
 		return;
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

sub import_audio  { 
	my $track = shift;
	my ($path, $frequency) = @_; 
	$path = expand_tilde($path);
	#say "path: $path";
	my $version  = ${ $track->versions }[-1] + 1;
	if ( ! -r $path ){
		print "$path: non-existent or unreadable file. No action.\n";
		return;
	}
	my ($depth,$width,$freq) = split ',', ::get_format($path);
	say "format: ", ::get_format($path);
	$frequency ||= $freq;
	if ( ! $frequency ){
		say "Cannot detect sample rate of $path. Skipping.";
		say "Use 'import_audio <path> <frequency>' if possible.";
		return 
	}
	my $desired_frequency = ::freq( $::raw_to_disk_format );
	my $destination = join_path(::this_wav_dir(),$track->name."_$version.wav");
	#say "destination: $destination";
	if ( $frequency == $desired_frequency and $path =~ /.wav$/i){
		say "copying $path to $destination";
		copy($path, $destination) or die "copy failed: $!";
	} else {	
		my $format = ::signal_format($::raw_to_disk_format, $width);
		say "importing $path as $destination, converting to $format";
		my $cmd = qq(ecasound -f:$format -i:resample-hq,$frequency,$path -o:$destination);
		#say $cmd;
		system($cmd) == 0 or say("Ecasound exited with error: ", $?>>8), return;
	} 
	::rememoize() if $::opts{R}; # usually handled by reconfigure_engine() 
}

sub port_name { $_[0]->target || $_[0]->name } 

# subclasses

package ::SimpleTrack; # used for Master track
use Modern::Perl;
no warnings qw(uninitialized redefine);
our @ISA = '::Track';

sub rec_status{

#	$::debug2 and print "&rec_status (SimpleTrack)\n";
	my $track = shift;
	return 'MON' unless $track->rw eq 'OFF';
	'OFF';

}
package ::MasteringTrack; # used for mastering chains 
use Modern::Perl;
no warnings qw(uninitialized redefine);
our @ISA = '::SimpleTrack';

sub rec_status{
	my $track = shift;
	$::mastering_mode ? 'MON' :  'OFF';
}
sub group_last {0}
sub version {0}

package ::SlaveTrack; # for instrument monitor bus
use Modern::Perl;
no warnings qw(uninitialized redefine);
our @ISA = '::Track';
sub width { $::tn{$_[0]->target}->width }
sub rec_status { $::tn{$_[0]->target}->rec_status }
sub full_path { $::tn{$_[0]->target}->full_path} 
sub monitor_version { $::tn{$_[0]->target}->monitor_version} 
#sub inserts { $::tn{$_[0]->target}->inserts} 
sub source_type { $::tn{$_[0]->target}->source_type}
sub source_id { $::tn{$_[0]->target}->source_id}
sub source_status { $::tn{$_[0]->target}->source_status }
sub send_type { $::tn{$_[0]->target}->send_type}
sub send_id { $::tn{$_[0]->target}->send_id}
sub dir { $::tn{$_[0]->target}->dir }

package ::CacheRecTrack; # for graph generation
our @ISA = qw(::SlaveTrack ::Wav);
sub current_version {
	my $track = shift;
	my $target = $::tn{$track->target};
		$target->last + 1
# 	if ($target->rec_status eq 'MON'
# 		or $target->rec_status eq 'REC' and $::Group::by_name{$track->target}){
# 	}
}
sub current_wav {
	my $track = shift;
		$::tn{$track->target}->name . '_' . $track->current_version . '.wav'
}
sub full_path { my $track = shift; ::join_path( $track->dir, $track->current_wav) }

1;
__END__


