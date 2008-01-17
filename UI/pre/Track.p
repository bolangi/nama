use lib qw(.. .); # for testing
use strict;
our ($debug);
$debug = 1;
package ::Bus;
our @ISA;
use ::Object qw(	name
						groups
						tracks 
						rules
						
						);

{
my $dummy_track_g = ::Track->new(name => 'dummy');
my $dummy_track = ::Track->new(n => 999, group => 'dummy');

sub deref_code {
	my ($value, $track) = @_;
	ref $value =~ /CODE/ 
		?  &$value($$track)
		:  $value
}
		
sub apply {
	my $bus = shift;
	$debug and print q(applying rules for bus "), $bus->name, qq("\n);
	my @tracks;
	push @tracks, map{ @{$_} } $bus->tracks, map{$_->tracks} @{ $bus->groups };
	print "tracks:: @tracks\n";
	map{ my $rule = $$_;
		my @tracks = @tracks;
		@tracks = ($dummy_track) if ! @tracks and $rule->target eq 'none';
		map{ my $track = $_; # 
			my $n = $$track->n;
			$debug and print "track ", $$track->name, " index: $n\n";
			push @{ $UI::inputs{ 
						deref_code($rule->input_type, $track) }->{
						deref_code($rule->input_object, $track) }
				}, deref_code($rule->chain_id, $track) 
						if defined $rule->input_type;
			push @{ $UI::outputs{
						deref_code( $rule->output_type, $track)  }->{ 
						deref_code( $rule->output_object, $track) }

					# i could rewrite this to be
					# $track->deref_code(  $rule->output_object )
			}, deref_code($rule->chain_id, $track) 
				if defined $rule->output_type;
		} @tracks;
	} @{ $bus->rules }; 
}

}

	
package ::Rule;
use Carp;
use vars qw(%by_name @by_index);
{ 
my $n;
@by_index;	# return ref to Track by numeric key
%by_name;	# return ref to Track by name
my %group_names; 
use ::Object qw( 	name
						chain_id

						target 
						am_needed	

						output_type
						output_object
						output_format

						input_type
						input_object

						post_input
						pre_output 

						apply_inputs
						apply_output
						
						default ); # on or off

# chain_id, depends_on, apply_inputs and apply_outputs are
# code refs.
						
#target: REC | MON | chain_id | all | none

sub new {
	# returns a reference to an object that is indexed by
	# name and by an assigned index
	#
	# The indexing is bypassed and an object returned 
	# if an index n is supplied as  a parameter
	
	my $class = shift;
	my %vals = @_;
	carp "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	(carp "name already in use: $vals{name}\n"), return 
		 if $group_names{$vals{name}}; # null name returns false
	my $n = $vals{n} ? $vals{n} : ++$n; 
	my $object = bless { 	name 	=> "Rule $n", # default name
					@_ 			}, $class;

	$group_names{$vals{name}}++;
	$by_index[$n] = \$object;
	$by_name{ $object->name } = \$object;
	\$object;
	
}

sub all_rules { @by_index[1..scalar @by_index] }

}

sub dump{
	my $rule = shift;
	print "rule: ", $rule->name, $/;
}

package ::Track;
use Carp;
use vars qw(%by_name @by_index);
use ::Wav;
our @ISA = '::Wav';
{my $n = 0; 	# incrementing numeric key
@by_index;	# return ref to Track by numeric key
%by_name;	# return ref to Track by name
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
	carp "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	(carp "name already in use: $vals{name}\n"), return 
		 if $track_names{$vals{name}}; # null name returns false
	my $add_index = ! $vals{n};
	my $n = $vals{n} ? $vals{n} : ++$n; 
	my $object = bless { 	name 	=> "Audio_$n", # default name
					group	=> 'Tracker',  # default 
					rw   	=> 'REC', 
					n    	=> $n,
					@_ 			}, $class;

	print "object class: $class, object type: ", ref $object, $/;
	$track_names{$vals{name}}++;
	if ( $add_index ) {
		$by_index[$n] = \$object;
		$by_name{ $object->name } = \$object;
		
	}
	# add the track to the corresponding Groups list
	my $group = $::Group::by_name{ $object->group }; 

	# create group if necessary
	
	defined $group or $group = ::Group->new( name => $object->group );

	print "group type: ", ref $$group, $/;
	#$::Group::by_name{ $object->group } = \$object;
	$$group->set( tracks => [ @{ $$group->tracks }, $object->name ]);
	\$object;
	
}
sub full_path {
	my $track = ${shift()}; # copy! 
	join_path 
		$track->dir ? $track->dir : "." , 
			$track->name . "_" .  $track->overall_version
}


# The following are not object methods. 

sub is {
	my $id = shift;
	$id =~ /^\d+$/ 
		and $::Track::by_index[$id]
		or  $::Track::by_name{$id}
}

#${ Track::is 1 }->set( rw => 'MUTE');
#${ Track::is "sax" }->rw;

sub all_tracks { @by_index[1..scalar @by_index] }


}

package ::Group;
use Carp;
use vars qw(%by_name @by_index);
our @ISA;
{ 
@by_index;
%by_name;
my %group_names;
my $n; 

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
	carp "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	(carp "name already in use: $vals{name}\n"), return 
		 if $group_names{$vals{name}};
	$group_names{$vals{name}}++;
	#my $skip_index = $vals{n};
	my $n = $vals{n} ? $vals{n} : ++$n; 
	my $object = bless { 	
		name 	=> "Group $n", # default name
		tracks => [],
		rw   	=> 'REC', 
		n => $n,
		@_ 			}, $class;
	#return $object if $skip_index;
	print "object type: ", ref $object, $/;
	$by_index[$n] = \$object;
	$by_name{ $object->name } = \$object;
	\$object;
}

sub all_groups { @by_index[1..@by_index] }

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

}

__END__
