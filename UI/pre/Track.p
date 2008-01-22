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
use vars qw(%by_name @by_index);
use ::Wav;
our @ISA = '::Wav';
{my $n = 0; 	# incrementing numeric key
@by_index = ();	# return ref to Track by numeric key
%by_name = ();	# return ref to Track by name
my %track_names; 

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
						group );
sub new {
	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	# The indexing is bypassed and an object returned 
	# if an index n is supplied as  a parameter
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak  "track name already in use: $vals{name}\n"
		 if $track_names{$vals{name}}; # null name returns false
	my $add_index = ! $vals{n};
	my $n = $vals{n} ? $vals{n} : ++$n; 
	my $object = bless { 	name 	=> "Audio_$n", # default name
					group	=> 'Tracker',  # default 
					dir     => '.',
					rw   	=> 'REC', 
					n    	=> $n,
					@_ 			}, $class;

	#print "object class: $class, object type: ", ref $object, $/;
	$track_names{$vals{name}}++;
	if ( $add_index ) {
		$by_index[$n] = $object;
		$by_name{ $object->name } = $object;
		
	}
	my $group = $::Group::by_name{ $object->group }; 

	# create group if necessary
	
	defined $group or $group = ::Group->new( name => $object->group );
	my @existing = $group->tracks ;
	$group->set( tracks => [ @existing, $object->name ]);
	$object;
	
}

} # for private variables

sub full_path {
	my $track = shift; 
	join_path(
		$track->dir ? $track->dir : "." , 
			$track->name . "_" .  $track->current . '.wav'
	)	
}

sub very_last {
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
	# my %vals = @_; # 
	my $last = $track->very_last;
	#print "last found is $last\n"; 
	if 		($track->rec_status eq 'REC' ){ return ++$last; }
	elsif ( $track->rec_status eq 'MON'){ $track->monitor_version }
	
	print "track ", $track->name, ": no current version found\n" ;
	return undef;
}

sub monitor_version {
	return 89;
	my $track = shift;
	my $group = $::Group::by_name{$track->group};
		print ($track->active), return $track->active if $track->active 
			and grep {$track->active == $_ } @{$track->versions};

		print ($group->version), return $group->version if $group->version
			and grep {$group->version  == $_ } @{$track->versions};

		print ($track->last), return $track->last if $track->last
									and ! $track->active
									and ! $group->version
}

#my $done; 

sub rec_status {
	#$done++;
	#croak if $done > 20;
	my $track = shift;
	print "rec status track: ", $track->name, $/;
	my $group = $::Group::by_name{$track->group};
	return 'REC' if $group->name ne 'Tracker' and $group->rw eq 'REC'; 

					# Mixer group will ignore ch_r status
		
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

		return 'REC' if $track->ch_r;
		return 'MUTE';
	}
	else { return 'MON' if $track->monitor_version;
			return 'MUTE';	
	}
}


# The following are not object methods. 

sub all_tracks { @by_index[1..scalar @by_index - 1] }


#use lib qw(.. .);

# ---------- Group -----------

package ::Group;
#use Exporter qw(import);
#our @EXPORT_OK =qw(group);
use Carp;
use vars qw(%by_name @by_index $active);
our @ISA;
{ 
#$active = 'Tracker'; # REC-enabled
my $n = 0; 
@by_index = ();
%by_name = ();

use ::Object qw( 	name
					tracks
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
		tracks => [],
		rw   	=> 'REC', 
		n => $n,
		@_ 			}, $class;
	#return $object if $skip_index;
	#print "object type: ", ref $object, $/;
	$by_index[$n] = $object;
	$by_name{ $object->name } = $object;
	$object;
}
}

sub tracks { # returns list of tracks in group 

	# note this contrasts with $track->versions, which is 
	# a array reference.

	my $group = shift;
	map{ $_->name } grep{ $_->group eq $group->name } ::Track::all_tracks;
}


sub all_groups { @by_index[1..@by_index - 1] }

sub group {
	my ($id, $method, @vals) = @_;
	my $group =  $::Group::by_name{$id};
	#print "group:: id: $id, method: $method\n";
	my $command = qq(\$group->$method(\@vals));
	#print $command, $/;
	eval $command;
}
 
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
