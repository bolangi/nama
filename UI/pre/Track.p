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
my $dummy_track = ::Track->new(n => 999);

sub deref_code {
	my ($value, $track) = @_;
	ref $value =~ /CODE/ 
		?  &$value($track)
		:  $value
}
		
sub apply {
	my $bus = shift;
	$debug and print q(applying rules for bus "), $bus->name, qq("\n);
	my @tracks;
	push @tracks, map{ @{$_} } $bus->tracks, map{$_->tracks} @{ $bus->groups };
	map{ my $rule = $_;
		my @tracks = @tracks;
		@tracks = ($dummy_track) if ! @tracks and $rule->target eq 'none';
		map{ my $track = $_; # 
			my $n = $$track->n;
			print "track ", $$track->name, "index: ", $n;
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


package ::Track;
use Carp;
use ::Wav;
our @ISA = '::Wav';
{my $n = 0; 	# incrementing numeric key
my @by_index;	# return ref to Track by numeric key
my %by_name;	# return ref to Track by name
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

	$track_names{$vals{name}}++;
	if ( $add_index ) {
		$by_index[$n] = \$object;
		$by_name{ $object->name } = \$object;
	}
	\$object;
	
}
sub full_path {
	my $track = ${shift()}; # copy! 
	join_path 
		$track->dir ? $track->dir : "." , 
			$track->name . "_" .  $track->overall_version
}

=comment
sub overall_version { 
	my $track = ${shift()}; # copy! 
	if ( $track->rec_status eq 'REC' ){ $last_version + 1 }
	elsif ( $track->rec_status eq 'MON'){ 
	my $version = $track->active
		? $track->active 
		: ${ ::Group::by_name $track->group };
	(grep {$_ == $version } @{$track->versions}}) ? $version : undef;
	

sub selected_version {
	# return track-specific version if selected,
	# otherwise return global version selection
	# but only if this version exists
	my $n = shift;
no warnings;

use warnings;
}
sub set_active_version {
	my $n = shift;
	$debug and print "chain $n: versions: @{$state_c{$n}->{versions}}\n";    
		$state_c{$n}->{active} = $state_c{$n}->{versions}->[-1] 
			if $state_c{$n}->{versions};    
		$debug and print "active version, chain $n: $state_c{$n}->{active}\n\n";
}
sub new_version {
	$last_version + 1;
}
sub mon_vert {
	my $ver = shift;
	return if $ver == $monitor_version;
	# store @{ $state_c{$ver}{ops} }
	# store %copp
	# remove effects  and use $ver's set if there are effects for $v
	$monitor_version = $ver;
	$ui->refresh();
}
=cut


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

=comment

my $existing_tracks = ${ $track->group }->tracks;

=cut
package ::Group;
use Carp;
our @ISA;
{ 
my @by_index;
my %by_name;
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
	my $skip_index = $vals{n};
	my $n = $vals{n} ? $vals{n} : ++$n; 
	my $object = bless { 	
		name 	=> "Group $n", # default name
		rw   	=> 'REC', 
		n => $n,
		@_ 			}, $class;
	return $object if $skip_index;
	$by_index[$n] = \$object;
	$by_name{ $object->name } = \$object;
	\$object;
}

sub all_groups { @by_index[1..@by_index] }

1;

}

__END__
my $mixer_out = UI::Rule->new( #  this is the master fader
	name			=> 'mixer_out', 
	chain_id		=> 'Mixer_out',

	target			=> 'none',
	am_needed		=> sub{ keys $inputs{mixed} },

	input_type 		=> 'mixed', # bus name
	input_object	=> 'loop,222', # $loopb 

	output_type		=> 'device',
	output_object	=> 'stereo',

	default			=> 'on',

);

my $mixdown = UI::Rule->new(

	name			=> 'mixdown', 
	chain_id		=> 'Mixdown',
	target			=> 'all', # default
	am_needed => sub{ 
		keys $outputs{mixed} or $debug 
			and print("no customers for mixed, skipping mixdown"), 0}, 

	input_type 		=> 'mixed', # bus name
	input_object	=> 'loop,222', # $loopb 

	output_type		=> 'file',
	output_object   => sub {
		my $track = ${shift()}; 
		join " ", $track->full_path, $mix_to_disk_format},

	#apply_inputs	=> sub{ },  
	#apply_outputs	=> sub{ },  

	default			=> 'off',
);
my $mix_setup = Rule->new(

	name			=>  'mix_setup',
	chain_id		=>  sub { my $track = shift, "J". $track->n },
	target			=>  'all',
	input_type		=>  'cooked',
	input_object	=>  sub { my $track = shift, "loop," .  $track->n }
	output_object	=>  'loop,111', # $loopa
	output_type		=>  'cooked',
	default			=>  'on',
	am_needed 		=>  sub{ %{ $inputs{mixed} } },
	


my $mon_setup = Rule->new(
	
	name			=>  'mon_setup', 
	target			=>  'MON',
	chain_id 		=>	sub{ my $track = ${shift()}; $track->n },
	input_type		=>  'file',
	input_object	=>  sub{ my $track = ${shift()}; $track->full_path },
	output_type		=>  'cooked',
	output_object	=>  sub{ my $track = ${shift()}; "loop," .  $track->n },
	default			=>  'on',
	post_input		=>	\&mono_to_stereo,
);
	
my $rec_file = Rule->new(

	name		=>  'rec_file', 
	target		=>  'REC',
	chain_id	=>  sub{ my $track = ${shift()}; 'R'. $track->n },   
	input_type	=>  'device',
	input_object=>  'multi',
	output_type	=>  'file',
	output_object   => sub {
		my $track = ${shift()}; 
		join " ", $track->full_path, $raw_to_disk_format},
	default		=>  'on',
}

# Rec_setup: must come last in oids list, convert REC
# inputs to stereo and output to loop device which will
# have Vol, Pan and other effects prior to various monitoring
# outputs and/or to the mixdown file output.
		
my $rec_setup = Rule->new(

	name			=>	'rec_setup', 
	chain_id		=>  sub{ my $track = ${shift()}; $track->n },   
	target			=>	'REC',
	input_type		=>  'device',
	input_object	=>  'multi',
	output_type		=>  'cooked',
	output_object	=>  sub{ my $track = ${shift()}; "loop," .  $track->n },
	post_input			=>	\&mono_to_stereo,
	default			=>  'on',
	am_needed 		=> @{ $inputs{cooked}->{"loop," .  $track->n} },
)


# Multi: output 'cooked' monitor channels to side-by-side
# PCMs starting at the monitor channel assignment in the track menu.
#  Default to PCMs 1 & 2.

	name	=>	q(multi), 
	target	=>	q(mon),  
	id		=>	q(m),
	output	=>	q(multi),
	type	=>	q(cooked),
	pre_output	=>	\&pre_multi,
	default	=> q(off),

# Live: apply effects to REC channels route to multichannel sound card
# as above. 

	name	=>  q(live),
	target	=>  q(rec),
	id		=>	q(L),
	output	=>  q(multi),
	type	=>  q(cooked),
	pre_output	=>	\&pre_multi,
	default	=>  q(off),

	push @{ $inputs{cooked}->{$n} }, $chain_id if $rec_status eq 'REC'
	push @{ $outputs{$oid{output}} }, $chain_id;

