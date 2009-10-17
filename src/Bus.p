
# ------------  Bus --------------------

package ::Bus;
our $VERSION = 1.0;
use strict;
our ($debug);
$debug = 0;
use Carp;
our @ISA;
use ::Object qw(	name
						groups
						tracks 
						rules
						
						);

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


		
sub apply {
	
	#local $debug = 1;
	#print join " ", map{ ref $_ } values %::Rule::by_name; exit;
	my $bus = shift;
	$debug and print q(applying rules for bus "), $bus->name, qq("\n);
	$debug and print "bus name: ", $bus->name, $/;
	$debug and print "groups: ", join " ", @{$bus->groups}, $/;
	$debug and print "rules: ", join " ", @{$bus->rules}, $/;

	# get track names corresponding to this bus
	
	my @track_names = (@{$bus->tracks}, 

		map{ $debug and print "group name: $_\n";
			$debug and print join " ", "keys:", keys( %::Group::by_name), $/;
			my $group = $::Group::by_name{$_}; 
			$debug and print "group validated: ", $group->name, $/;
			$debug and print "includes: ", $group->tracks, $/;
			$group->tracks 
								}  @{ $bus->groups }

	);
	$debug and print "tracks: ", join " ", @track_names, $/;
	my @tracks = map{ $::Track::by_name{$_} } @track_names; 

	map{ my $track = $_; # 
		my $n = $track->n;
		$debug and print "track ", $track->name, " index: $n\n";

		map{ my $rule_name = $_;
			$debug and print "apply rule name: $rule_name\n"; 
			my $rule = $::Rule::by_name{$_};
			#print "rule is type: ", ref $rule, $/;
			$debug and print "condition: ", $rule->condition, $/;

			my $key1 = deref_code($rule->input_type, $track);
			my $key2 = deref_code($rule->input_object, $track) ;
			my $chain_id = deref_code($rule->chain_id, $track) ;
			my $rec_status = $track->rec_status;
			my $condition_met = deref_code($rule->condition, $track);

			$debug and print "chain_id: $chain_id, rec_status: $rec_status, condition: $condition_met,  input key1: $key1, key2: $key2\n";
			if ( 
				$track->rec_status ne 'OFF' 
					and $rule->status
					and ( 		$rule->target =~ /all|none/
							or  $rule->target eq $track->rec_status)
					and $condition_met
						
						)  {

				defined $rule->input_type and
					push @{ $::inputs{ $key1 }->{ $key2 } }, $chain_id ;

				$key1 = deref_code($rule->output_type, $track);
				$key2 = deref_code($rule->output_object, $track) ;
			$debug and print "chain_id: $chain_id, rec_status: $rec_status, condition: $condition_met, output key1: $key1, key2: $key2\n";

				defined $rule->output_type and
					push @{ $::outputs{ $key1 }->{ $key2 } }, $chain_id;
			# add intermediate processing
		
		my ($post_input, $pre_output);
		$post_input = deref_code($rule->post_input, $track) 
			if defined $rule->post_input;
		$pre_output = deref_code($rule->pre_output, $track) 
			if defined $rule->pre_output;
		$debug and print "pre_output: $pre_output, post_input: $post_input\n";
		$::post_input{$chain_id} .= $post_input if defined $post_input;
		$::pre_output{$chain_id} .= $pre_output if defined $pre_output;
			}

		} @{ $bus->rules } ;
	} @tracks; 
}
# the following is utility code, not an object method

sub deref_code {
	my ($value, $track) = @_;
	my $type = ref $value || "scalar";
	my $tracktype = ref $track;
	#print "found type: $type, value: $value\n";
	#print "found type: $type, tracktype: $tracktype, value: $value\n";
	if ( $type  =~ /CODE/){
		 $debug and print "code found\n";
		$value = &$value($track);
		 $debug and print "code value: $value\n";
		 $value;
	} else {
		$debug and print "scalar value: $value\n"; 
		$value }
}


# ------------  Rule  --------------------
	
package ::Rule;
use Carp;
use vars qw($n %by_name @by_index %rule_names);
$n = 0;
@by_index = ();	# return ref to Track by numeric key
%by_name = ();	# return ref to Track by name
%rule_names = (); 
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

sub dump{
	my $rule = shift;
	print "rule: ", $rule->name, $/;
}

### subclass

package ::MixBus;
our @ISA = '::Bus';
sub apply {} ; ## TODO 

### subclass

package ::UserBus;
use strict;
use Carp;
our @ISA = '::Bus';
use vars qw(@buses %by_name);

use ::Object qw(	name
						groups
						tracks 
						rules
						destination_type
						destination_id


						);

# we will put the following information in the Track as an aux_send
# 						destination_type
# 						destination_id
# name, init capital e.g. Brass, identical Group name
# destination: 3, jconv, loop,output


sub new {
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	my $self = bless { 
		tracks => [], 
		groups => [], 
		rules  => [],
		@_ }, $class; 
	push @buses, $self;
	$by_name{$self->name} = $self;
	return $self;
}

sub all { @buses }

# not object method

# sub by_name {
# 	my $name = shift;
# 	( grep { $_->name  eq $name } @buses ); # list context return object
# }

1;
__END__


						
						);

1;
