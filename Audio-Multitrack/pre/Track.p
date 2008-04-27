use lib qw(.. .); # for testing
use strict;
our ($debug);
$debug = 1;

# ---------- Track -----------

package ::Track;
#use Exporter qw(import);
#our @EXPORT_OK = qw(track);
use ::Assign qw(join_path);
use Carp;
use vars qw($n %by_name @by_index %track_names);
use ::Wav;
our @ISA = '::Wav';
$n = 0; 	# incrementing numeric key
@by_index = ();	# return ref to Track by numeric key
%by_name = ();	# return ref to Track by name
%track_names = (); 

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
						duration
						
						
						);
sub new {
	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	# The indexing is bypassed and an object returned 
	# if an index n is supplied as  a parameter
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	carp  "track name already in use: $vals{name}\n"
		 if $track_names{$vals{name}}; # null name returns false
	my $add_index = ! $vals{n};
	my $n = $vals{n} ? $vals{n} : ++$n; 
	my $object = bless { 


		## 		defaults ##

					name 	=> "Audio_$n", 
					group	=> 'Tracker', 
					dir     => '.',
					rw   	=> 'REC', 
					n    	=> $n,
					ops     => [],
					active	=> undef,
					ch_r 	=> undef,
					ch_m 	=> undef,
					vol  	=> undef,
					pan 	=> undef,
					offset 	=> 0,    # used for interface with Ecasound
					delay	=> undef, # when we start the playback
					duration => undef, # how long we play back

					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	$track_names{$vals{name}}++;
	$by_index[$n] = $object;
	$by_name{ $object->name } = $object;
	
	::add_volume_control($n);
	::add_pan_control($n);

	#my $group = $::Group::by_name{ $object->group }; 

	# create group if necessary
	#defined $group or $group = ::Group->new( name => $object->group );
	#my @existing = $group->tracks ;
	#$group->set( tracks => [ @existing, $object->name ]);
	$object;
	
}

sub full_path {
	my $track = shift; 
	join_path(
		$track->dir ? $track->dir : "." , $track->current 
	)	
}
sub group_last {
	my $track = shift;
	my $group = $::Group::by_name{$track->group}; 
	#print join " ", 'searching tracks:', $group->tracks, $/;
	my $max = 0;
	map{ 
		my $track = $_;
		my $last = $track->last;
		#print "track: ", $track->name, ", last: $last\n";

		$max = $last if $last > $max;

	}	map { $by_name{$_} } $group->tracks;
	$max;
}

sub current {	
	my $track = shift;
	my $last = $track->group_last;
	#print "last found is $last\n"; 
	if 	($track->rec_status eq 'REC'){ 
		return $track->name . '_' . ++$last . '.wav'}
	elsif ( $track->rec_status eq 'MON'){ 
		return $track->targets->{ $track->monitor_version } 
	} else {
		print "track ", $track->name, ": no current version found\n" ;
		return undef;
	}
}
sub current_version {	
	my $track = shift;
	my $last = $track->group_last;
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
	else { carp "no version to monitor!\n" }
	print "monitor version: $version\n";
	$version;
}

sub rec_status {
	my $track = shift;
	print "rec status track: ", $track->name, $/;
	my $group = $::Group::by_name{$track->group};

		
	return 'MUTE' if 
		$group->rw eq 'MUTE'
		or $track->rw eq 'MUTE'
		or $track->rw eq 'MON' and ! $track->monitor_version;
		# ! $track->full_path;
		;
	if( 	
		$track->rw eq 'REC'
		 and $group->rw eq 'REC'
		) {

		return 'REC'; # if $track->ch_r;
		#return 'MON' if $track->monitor_version;
		#return 'MUTE';
	}
	else { return 'MON' if $track->monitor_version;
			return 'MUTE';	
	}
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
	return if $track->ch_r == 1 or ! $track->ch_r;
	"-erc:" . $track->ch_r. ",1"; #  -f:$rec_format ";
}
sub route {
	my ($width, $dest) = @_;
	return undef if $dest == 1 or $dest == 0;
	print "route: width: $width, destination: $dest\n\n";
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

package ::SimpleTrack;
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
						duration
						
						
						);

sub rec_status{

	my $track = shift;
	$track->rw;

}

sub ch_r {
	my $track = shift;
	return '';
}

=comment
# subclass

package ::MixTrack;
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
						duration
						
						
						);

sub rec_status{

	my $track = shift;
	$track->rw;

}

sub ch_r {
	my $track = shift;
	return '';
}


=cut
	



# ---------- Group -----------

package ::Group;
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
	print "ttype: ", ref $group, $/;
	my @all = ::Track::all;
	map {print "type: ", ref $_, $/} ::Track::all; 
	print "all, length: ", scalar @all, $/;
	map{ $_->name } grep{ $_->group eq $group->name } ::Track::all();
}


sub all { @by_index[1..scalar @by_index - 1] }

=comment
sub group {
	my ($id, $method, @vals) = @_;
	my $group =  $::Group::by_name{$id};
	#print "group:: id: $id, method: $method\n";
	my $command = qq(\$group->$method(\@vals));
	#print $command, $/;
	eval $command;
}
=cut
 
# ---------- Op -----------

package ::Op;
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
