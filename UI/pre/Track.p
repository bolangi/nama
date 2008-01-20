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

# ---------- UI ----------

package ::;

no strict qw(vars);

my $loopa = 'loop,111'; # duplicate
my $loopb = 'loop,222'; # duplicate 


my $mixer_out = ::Rule->new( #  this is the master fader
	name			=> 'mixer_out', 
	chain_id		=> 'Mixer_out',

	target			=> 'none',
	
	# sub{ defined $inputs{mixed}  or $debug and print("no customers for mixed, skipping\n"), 0},

	input_type 		=> 'mixed', # bus name
	input_object	=> $loopb, 

	output_type		=> 'device',
	output_object	=> 'stereo',

	status			=> 1,

);

my $mix_down = ::Rule->new(

	name			=> 'mix_file', 
	chain_id		=> 'Mixdown',
	target			=> 'all', # default
	condition => sub{ 
		defined $outputs{mixed} or $debug 
			and print("no customers for mixed, skipping mixdown\n"), 0}, 

	input_type 		=> 'mixed', # bus name
	input_object	=> $loopb,

	output_type		=> 'file',
	output_object   => sub {
		my $track = shift; 
		join " ", $track->full_path, $mix_to_disk_format},

	status			=> 1,
);
my $mix_setup = ::Rule->new(

	name			=>  'mix_setup',
	chain_id		=>  sub { my $track = shift; "J". $track->n },
	target			=>  'all',
	input_type		=>  'cooked',
	input_object	=>  sub { my $track = shift; "loop," .  $track->n },
	output_object	=>  $loopa,
	output_type		=>  'cooked',
	condition 		=>  sub{ defined $inputs{mixed} },
	status			=>  1,
	
);


my $mon_setup = ::Rule->new(
	
	name			=>  'mon_setup', 
	target			=>  'MON',
	chain_id 		=>	sub{ my $track = shift; $track->n },
	input_type		=>  'file',
	input_object	=>  sub{ my $track = shift; $track->full_path },
	output_type		=>  'cooked',
	output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
	post_input		=>	\&mono_to_stereo,
	status			=>  1,
);
	
my $rec_file = ::Rule->new(

	name		=>  'rec_file', 
	target		=>  'REC',
	chain_id	=>  sub{ my $track = shift; 'R'. $track->n },   
	input_type	=>  'device',
	input_object=>  'multi',
	output_type	=>  'file',
	output_object   => sub {
		my $track = shift; 
		join " ", $track->full_path, $raw_to_disk_format},
	status		=>  1,
);

# Rec_setup: must come last in oids list, convert REC
# inputs to stereo and output to loop device which will
# have Vol, Pan and other effects prior to various monitoring
# outputs and/or to the mixdown file output.
		
my $rec_setup = ::Rule->new(

	name			=>	'rec_setup', 
	chain_id		=>  sub{ my $track = shift; $track->n },   
	target			=>	'REC',
	input_type		=>  'device',
	input_object	=>  'multi',
	output_type		=>  'cooked',
	output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
	post_input			=>	\&mono_to_stereo,
	condition 		=> sub { my $track = shift; 
							return "satisfied" if defined
							$inputs{cooked}->{"loop," . $track->n}; 
							0 } ,
	status			=>  1,
);

my $multi = ::Rule->new(

	name			=>  'multi', 
	target			=>  'MON',
	chain_id 		=>	sub{ my $track = shift; "M".$track->n },
	input_type		=>  'file',
	input_object	=>  sub{ my $track = shift; "loop," .  $track->n},
	output_type		=>  'device',
	output_object	=>  'multi',
	pre_output		=>	\&pre_multi,
	status			=>  1,
);

sub mono_to_stereo { " -erc:1,2 " }

sub pre_multi {
	#$debug2 and print "&pre_multi\n";
	my $track = shift;
	return if ! defined $track->ch_m or $track->ch_m == 1;
	route(2,$track->ch_m); # stereo signal
}

=comment

# Multi: output 'cooked' monitor channels to side-by-side
# PCMs starting at the monitor channel assignment in the track menu.
#  Default to PCMs 1 & 2.


# Live: apply effects to REC channels route to multichannel sound card
# as above. 

	name	=>  q(live),
	target	=>  q(rec),
	id		=>	q(L),
	output	=>  q(multi),
	type	=>  q(cooked),
	pre_output	=>	\&pre_multi,
	status	=>  0,

	push @{ $inputs{cooked}->{$n} }, $chain_id if $rec_status eq 'REC'
	push @{ $outputs{$oid{output}} }, $chain_id;

=cut
sub route {
	my ($width, $dest) = @_;
	return undef if $dest == 1 or $dest == 0;
	$debug and print "route: width: $width, destination: $dest\n\n";
	my $offset = $dest - 1;
	my $map ;
	for my $c ( map{$width - $_ + 1} 1..$width ) {
		$map .= " -erc:$c," . ( $c + $offset);
		$map .= " -eac:0,"  . $c;
	}
	$map;
}
sub eliminate_loops {
	my $n = shift;
	return unless defined $inputs{cooked}->{$n} and scalar @{$inputs{cooked}->{$n}} == 1;
	# get customer's id from cooked list and remove it from the list

	my $cooked_id = pop @{ $inputs{cooked}->{$n} }; 

	# add chain $n to the list of the customer's output device 
	
	no warnings;
	my ($oid) = grep{ $cooked_id =~ /$_->{id}/ } @oids;
	use warnings;
	my %oid = %{$oid};
	defined $outputs{ $oid{output} } or $outputs{ $oid{output}} = [];
	push @{ $outputs{ $oid{output} } }, $n;

	

	# remove chain $n as source for the loop

	my $loop_id = "loop,$n";
	delete $outputs{$loop_id}; 
	
	# remove customers that use loop as input

	delete $inputs{$loop_id}; 

	# remove cooked customer from his output device list

	@{ $outputs{$oid{output}} } = grep{$_ ne $cooked_id} @{ $outputs{$oid->{output}} };

	# transfer any intermediate processing to numeric chain,
	# deleting the source.
	no warnings;
	$post_input{$n} .= $post_input{$cooked_id};
	$pre_output{$n} .= $pre_output{$cooked_id}; 
	use warnings;
	delete $post_input{$cooked_id};
	delete $pre_output{$cooked_id};

}

1;

__END__
