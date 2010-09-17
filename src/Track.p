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
use ::Assign qw(join_path);
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
		return # $track;
	}
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

	#my $group = $::Bus::by_name{ $object->group }; 

	# create group if necessary
	#defined $group or $group = ::Group->new( name => $object->group );
	#my @existing = $group->tracks ;
	#$group->set( tracks => [ @existing, $object->name ]);
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
	my $group = $::Bus::by_name{$track->group}; 
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
					? ::Bus::overall_last()
					: $track->last;
	my $status = $track->rec_status;
	#$debug and print "last: $last status: $status\n";
	if 	($status eq 'REC'){ return ++$last}
	elsif ( $status eq 'MON'){ return $track->monitor_version } 
	else { return 0 }
}

sub monitor_version {
	my $track = shift;

	my $group = $::Bus::by_name{$track->group};
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

	my $group = $::Bus::by_name{$track->group};
	#$debug and say join " ", "bus:",$group->name, $group->rw;
	$debug and print "track: ", $track->name, ", source: ",
		$track->source_id, ", monitor version: $monitor_version\n";

	# first, check for conditions resulting in status 'OFF'

	if ( $group->rw eq 'OFF'
		or $track->rw eq 'OFF'
		or $::preview eq 'doodle' and $track->rw eq 'REC' and 
			$::duplicate_inputs{$track->name}
	){ 	return			  'OFF' }

	# having reached here, we know $group->rw and $track->rw are REC or MON
	# so the result will be REC or MON if conditions are met

	# second, set REC status if possible

		# we allow a mix track to be REC, even if the 
		# bus it belongs to is set to MON
			
	# for null tracks
	elsif (	$track->rw eq 'REC' and ($group->rw eq 'REC'
				or $::Bus::by_name{$track->name}
					and $track->rec_defeat) ){
		given( $track->source_type){
			when('jack_client'){
				::jack_client($track->source_id,'output')
					?  return 'REC'
					:  return maybe_monitor($monitor_version)
			}
			when('jack_port'){ return 'REC' }
			when('null'){ return 'REC' }
			when('soundcard'){ return 'REC' }
			when('bus'){ return 'REC' } # maybe $track->rw ??
			default { return 'OFF' }
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
	grep{ 		$_ ne $track->vol 
			and $_ ne $track->pan 
			and (! $track->fader or $_ ne $track->fader) 
	} @{ $track->ops }
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

		if ($track->source_type =~ /soundcard|jack_client|jack_port|null/){
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
	return unless $track->has_insert;
	my $i = $track->inserts;
	map{ $::tn{$_}->remove } @{ $i->{tracks} };
	$track->set(inserts => {});
}
sub has_insert  { my $i = $_[0]->inserts; exists $i->{tracks} and @{ $i->{tracks} } }

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
	
	# set $type and $id variables for assignment 
	# to track source_* or send_* fields
	
	# these are the field names
	my $type_field = $direction."_type";
	my $id_field   = $direction."_id";

	# respond to a query (no argument)
	if ( ! $id ){ return $track->$type_field ? $track->$id_field : undef }

	# set null values if we receive 'off' from track send/source widgets
	# UNUSED???
	if ( $id eq 'off'){ 
		die $track->name. ": $direction\_id: off not expected";
		$track->set($type_field => undef);
		$track->set($id_field => undef);
		say $track->name, ": disabling $direction.";
		return;
	}
	
	# set values, returning new setting
	my $type = ::dest_type( $id );
	given ($type){
		when ( /jack/ ){
			say("JACK server not running! Cannot set JACK client or port as track source."), 
				return unless $::jack_running;
			continue;
		} 
		when ('jack_manual'){
			my $port_name = $track->name . ($direction eq 'source' ? "_in" : "_out" );

 			say $track->name, ": JACK $direction port is $port_name. Make connections manually.";
			$id = 'manual';
			$id = $port_name;
			$type = 'jack_port';
		}
		when ('jack_client'){
			my $client_direction = $direction eq 'source' ? 'output' : 'input';

			my $name = $track->name;
			my $width = scalar @{ ::jack_client($id, $client_direction) };
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
			say("$id: ports file not found in ",project_root(),". Skipping."), 
				return unless -e join_path( project_root(), $id );
			# check if ports file parses
		}
	#	when('soundcard'){ }
	#	when('loop'){ }
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
	my $source = shift;
	my $old_source = $track->input_object;
	$track->set_io('source',$source);
	my $new_source = $track->input_object;
	my $object = $new_source;
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
	
	my $text;
	given ($track->$type_field){
		when('soundcard')  		{ $text = "soundcard channel "}
		when('jack_client')		{ $text = "JACK client "}
		when('loop')       		{ $text = "loop device "}
		when('jack_ports_list') { $text = "JACK ports list "}
		when('bus') 			{ $text = "bus "}
	}
	$text .= $track->$id_field
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
sub mute {
	package ::;
	my $track = shift;
	my $nofade = shift;
	# do nothing if already muted
	return if defined $track->old_vol_level();
	if ( $::copp{$track->vol}[0] != $track->mute_level
		and $::copp{$track->vol}[0] != $track->fade_out_level){   
		$track->set(old_vol_level => $::copp{$track->vol}[0]);
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
	$::mute_level{$track->vol_type}
}
sub fade_out_level {
	my $track = shift;
	$::fade_out_level{$track->vol_type}
}
sub set_vol {
	my $track = shift;
	my $val = shift;
	::effect_update_copp_set($track->vol, 0, $val);
}
sub vol_type {
	my $track = shift;
	$::cops{$track->vol}->{type}
}
sub import_audio  { 
	my $track = shift;
	my ($path, $frequency) = @_; 
	$path = ::expand_tilde($path);
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

sub bus_tree { # for solo function to work in sub buses
	my $track = shift;
	my $mix = $track->group;
	return if $mix eq 'Main';
	($mix, $::tn{$mix}->bus_tree);
}

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
sub source_status {}
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
our @ISA = qw(::SlaveTrack);
sub current_version {
	my $track = shift;
	my $target = $::tn{$track->target};
		$target->last + 1
# 	if ($target->rec_status eq 'MON'
# 		or $target->rec_status eq 'REC' and $::Bus::by_name{$track->target}){
# 	}
}
sub current_wav {
	my $track = shift;
		$::tn{$track->target}->name . '_' . $track->current_version . '.wav'
}
sub full_path { my $track = shift; ::join_path( $track->dir, $track->current_wav) }
package ::MixDownTrack; 
our @ISA = qw(::Track);
sub current_version {	
	my $track = shift;
	my $last = $track->last;
	my $status = $track->rec_status;
	#$debug and print "last: $last status: $status\n";
	if 	($status eq 'REC'){ return ++$last}
	elsif ( $status eq 'MON'){ return $track->monitor_version } 
	else { return 0 }
}
sub rec_status {
	my $track = shift;
	return 'REC' if $track->rw eq 'REC';
	::Track::rec_status($track);
}
1;
__END__


