
# ---------- Track -----------
use strict;
package ::Track;
our $VERSION = 1.0;
our ($debug);
local $debug = 0;
#use Exporter qw(import);
#our @EXPORT_OK = qw(track);
use ::Assign qw(join_path);
use Carp;
use IO::All;
use vars qw($n %by_name @by_index %track_names);
use ::Wav;
our @ISA = '::Wav';
$n = 0; 	# incrementing numeric key
@by_index = ();	# return ref to Track by numeric key
%by_name = ();	# return ref to Track by name

# attributes offset, loop, delay for entire setup
# attribute  modifiers
# new attribute will be 
use ::Object qw( 	name
						active

						ch_r 
						ch_m 
						rw

						vol  
						pan 
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
		$debug and carp  ("track name already in use: $vals{name}\n"), return
		 #if $track_names{$vals{name}}; # null name returns false

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
					vol  	=> undef,
					pan 	=> undef,

					modifiers => q(), # start, reverse, audioloop, playat

					
					delay	=> undef, # after how long we start playback
					                  # the term 'offset' is used already
					start_position => undef, # where we start playback from
					length => undef, # how long we play back
					looping => undef, # do we repeat our sound sample

					hide     => undef, # for 'Remove Track' function

					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	$track_names{$vals{name}}++;
	#print "names used: ", ::yaml_out( \%track_names );
	$by_index[$n] = $object;
	$by_name{ $object->name } = $object;
	
	::add_volume_control($n);
	::add_pan_control($n);

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
	my $last = $track->group_last;
	#print "last found is $last\n"; 
	if 	($track->rec_status eq 'REC'){ 
		return $track->name . '_' . ++$last . '.wav'}
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
	my $last = $track->group_last;
	#print "last found is $last\n"; 
	if 	($track->rec_status eq 'REC'){ 
		return $track->name . '_' . ++$last . '.wav'}
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
	my $last = $track->group_last;
	my $status = $track->rec_status;
	#print "last: $last status: $status\n";
	if 	($track->rec_status eq 'REC'){ return ++$last}
	elsif ( $track->rec_status eq 'MON'){ return $track->monitor_version } 
	else { return undef }
}

sub monitor_version {
	my $track = shift;
	my $group = $::Group::by_name{$track->group};
	my $version; 
	if ( $track->active 
			and grep {$track->active == $_ } @{$track->versions}) 
		{ $version = $track->active }
	elsif (	$group->version
			and grep {$group->version  == $_ } @{$track->versions})
		{ $version = $group->version }
	elsif (	$track->last) #  and ! $track->active and ! $group->version )
		{ $version = $track->last }
	else { } # carp "no version to monitor!\n" 
	# print "monitor version: $version\n";
	$version;
}

sub rec_status {
	my $track = shift;
	# print "rec status track: ", $track->name, $/;
	my $group = $::Group::by_name{$track->group};

		
	return 'OFF' if 
		$group->rw eq 'OFF'
		or $track->rw eq 'OFF'
		or $track->rw eq 'MON' and ! $track->monitor_version
		or $track->hide;
		# ! $track->full_path;
		;
	if( 	
		$track->rw eq 'REC'
		 and $group->rw eq 'REC'
		) {

		return 'REC'; # if $track->ch_r;
		#return 'MON' if $track->monitor_version;
		#return 'OFF';
	}
	else { return 'MON' if $track->monitor_version;
			return 'OFF';	
	}
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
	return if qx(which file)
		and -e $track->full_path
		and qx($cmd) =~ /stereo/i;
	" -erc:1,2 "
}
sub pre_multi {
	#$debug2 and print "&pre_multi\n";
	my $track = shift;
	return if ! defined $track->ch_m or $track->ch_m == 1;
	route(2,$track->ch_m); # stereo signal
}

sub rec_route {
	my $track = shift;
	return if ! $track->ch_r;
	return if $track->ch_r == 1 or ! $track->ch_r;
	"-erc:" . $track->ch_r. ",1"; #  -f:$rec_format ";
}
sub route {
	my ($width, $dest) = @_;
	return undef if $dest == 1 or $dest == 0;
	# print "route: width: $width, destination: $dest\n\n";
	my $offset = $dest - 1;
	my $map ;
	for my $c ( map{$width - $_ + 1} 1..$width ) {
		$map .= " -erc:$c," . ( $c + $offset);
		$map .= " -eac:0,"  . $c;
	}
	$map;
}

# The following are not object methods. 

sub all { @by_index[1..scalar @by_index - 1] }

# subclass

package ::SimpleTrack; # used for Master track
our @ISA = '::Track';
use ::Object qw( 	name
						dir
						active

						ch_r 
						ch_m 
						rw

						vol  
						pan 
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
						
						
						);

sub rec_status{

	my $track = shift;
	return 'MON' unless $track->rw eq 'OFF';
	'OFF';

}

sub ch_r {
	my $track = shift;
	return '';
}




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

sub tracks { # returns list of tracks in group 

	# note this contrasts with $track->versions, which is 
	# a array reference.

	my $group = shift;
	my @all = ::Track::all;
	# map {print "type: ", ref $_, $/} ::Track::all; 
	map{ $_->name } grep{ $_->group eq $group->name } ::Track::all();
}


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

__END__
