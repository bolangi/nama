use lib qw(.. .); # for testing
use strict;
our ($debug);
$debug = 1;

# ------------  Bus --------------------

package ::Bus;
use Carp;
our @ISA;
use ::Object qw(	name
						groups
						tracks 
						rules
						
						);

{
#my $dummy_track_g = ::Track->new(name => 'dummy');
my $dummy_track = ::Track->new(n => 999, group => 'dummy');

sub new {
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	return bless { 
		tracks => [], 
		groups => [], 
		rules  => [],
		@_ }, $class; 
}

sub deref_code {
	my ($value, $track) = @_;
	my $type = ref $value ? ref $value : "scalar";
	my $tracktype = ref $track;
	#print "found type: $type, value: $value\n";
	#print "found type: $type, tracktype: $tracktype, value: $value\n";
	if ( $type  =~ /CODE/){
		 #print "code found\n";
		$value = &$value($track);
		 #print "code value: $value\n";
		 $value;
	} else {
		#print "value found: $value\n"; 
		$value }
}
#$ perl -e 'my $foo = sub{ print "foo: @_" }; my $a = 3; &$foo($a)'
# foo: 3$ 

		
sub apply {
	
	#print join " ", map{ ref $_ } values %::Rule::by_name; exit;
	my $bus = shift;
	$debug and print q(applying rules for bus "), $bus->name, qq("\n);
	print "bus name: ", $bus->name, $/;
	print "groups: ", join " ", @{$bus->groups}, $/;
	print "rules: ", join " ", @{$bus->rules}, $/;
	my @track_names = (@{$bus->tracks}, 

		map{ my $group = $::Group::by_name{$_}; 
			print "group: ", $group->name, $/;
			print "includes: ", $group->tracks, $/;
			$group->tracks 
								}  @{ $bus->groups }

	);
	print "tracks: ", join " ", @track_names;
	my @tracks = map{ $::Track::by_name{$_} } @track_names; 

	map{ my $rule_name = $_;
		print "apply rule name: $rule_name\n"; 
		my $rule = $::Rule::by_name{$_};
		#print "rule is type: ", ref $rule, $/;
		print "condition: ", $rule->condition, $/;
		# we ensure that mix_out executes without tracks
		@tracks = ($dummy_track) if ! @tracks and $rule->target eq 'none';

		map{ my $track = $_; # 
			my $n = $track->n;
			$debug and print "track ", $track->name, " index: $n\n";
			my $key1 = deref_code($rule->input_type, $track);
			my $key2 = deref_code($rule->input_object, $track) ;
			my $chain_id = deref_code($rule->chain_id, $track) ;
			my $rec_status = $track->rec_status;
			my $condition_met = deref_code($rule->condition, $track);

			print "chain_id: $chain_id, rec_status: $rec_status, condition: $condition_met,  input key1: $key1, key2: $key2\n";
			if ( 
				$track->rec_status ne 'MUTE' 
					and $rule->status
					and ( 		$rule->target =~ /all|none/
							or  $rule->target eq $track->rec_status)
					and $condition_met
						
						)  {

				defined $rule->input_type and
					push @{ $::inputs{ $key1 }->{ $key2 } }, $chain_id ;

				$key1 = deref_code($rule->output_type, $track);
				$key2 = deref_code($rule->output_object, $track) ;
			print "chain_id: $chain_id, rec_status: $rec_status, condition: $condition_met, output key1: $key1, key2: $key2\n";

				defined $rule->output_type and
					push @{ $::outputs{ $key1 }->{ $key2 } }, $chain_id;
			# add intermediate processing
		
		my ($post_input, $pre_output);
		$post_input = deref_code($rule->post_input, $track->n) 
			if defined $rule->post_input;
		$pre_output = deref_code($rule->pre_output, $track->n) 
			if defined $rule->pre_output;
		$debug and print "pre_output: $pre_output, post_input: $post_input\n";
		$::post_input{$chain_id} .= $post_input if defined $post_input;
		$::pre_output{$chain_id} .= $pre_output if defined $pre_output;
			}

		} @tracks;
	} @{ $bus->rules }; 
}

}

# ------------  Rule  --------------------
	
package ::Rule;
use Carp;
use vars qw(%by_name @by_index);
{ 
my $n = 0;
@by_index = ();	# return ref to Track by numeric key
%by_name = ();	# return ref to Track by name
my %rule_names; 
use ::Object qw( 	name
						chain_id

						target 
					 	condition		

						output_type
						output_object
						output_format

						input_type
						input_object

						post_input
						pre_output 

						status ); # 1 or 0

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
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	croak "rule name already in use: $vals{name}\n"
		 if $rule_names{$vals{name}}; # null name returns false
	#my $n = $vals{n} ? $vals{n} : ++$n; 
	$n++;
	my $object = bless { 	
		name 	=> "Rule $n", # default name
		target  => 'all',     # default target
		condition => 1, 	# apply by default
					@_,  			}, $class;

	$rule_names{$vals{name}}++;
	#print "previous rule count: ", scalar @by_index, $/;
	#print "n: $n, name: ", $object->name, $/;
	$by_index[$n] = $object;
	$by_name{ $object->name } = $object;
	$object;
	
}

sub all_rules { @by_index[1..scalar @by_index - 1] }

}

sub dump{
	my $rule = shift;
	print "rule: ", $rule->name, $/;
}

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
	# add the track to the corresponding Groups list
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
	my $group = $::Group::by_name{$track->group};
	my $last = $track->very_last;
	#print "last found is $last\n"; 
	if 		($track->rec_status eq 'REC' ){ return ++$last; }
	elsif ( $track->rec_status eq 'MON'){
		return $track->active if $track->active 
			and grep {$track->active == $_ } @{$track->versions};

		return $group->version if $group->version
			and grep {$group->version  == $_ } @{$track->versions};

		return $track->last if $track->last
									and ! $track->active
									and ! $group->version
	}
	print "track ", $track->name, ": no current version found\n" ;
	return undef;
}
	

sub rec_status {
	my $track = shift;
	my $group = $::Group::by_name{$track->group};
	return 'REC' if ! defined $group 
					or $group->name ne 'Tracker' ; 
					
					# mix_out will be REC
		
	return 'MUTE' if 
		$group->rw eq 'MUTE'
		or $track->rw eq 'MUTE'
		or $track->rw eq 'MON' and ! $track->full_path;
	if( 	
		$track->rw eq 'REC'
		 and $group->rw eq 'REC'
		) {

		return 'REC' if $track->ch_r;
		return 'MUTE';
	}
	else { return 'MON' if $track->full_path;
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
my %group_names;

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
	(carp "group name already in use: $vals{name}\n"), return 
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

=comment

# neither of these work, result is 2 should be 4 !!

sub last_version { 
	my $group = shift;
	my @tracks = $group->tracks;
	my $track_name = pop @tracks;
	my $track = $::Track::by_name{$track_name};
	$track->last_version;
}

sub last_version {
	my $group = shift;
	print join " ", 'searching tracks:', $group->tracks, $/;
	my $max = 0;
	map{ 
		my $track = $_;
		print "track: ", $track->name, "\n";
		my $last = $track->last;
		$max = $last if $last > $max;
	}	map { $::Track::by_name{$_} } $group->tracks;
}

=cut

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
