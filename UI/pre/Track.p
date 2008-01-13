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
		map{ my $track = $_;
			my $n = $track->n;
			print "track ", $track->name, "index: ", $n;
			push @{ $UI::inputs{ 
						$rule->input_type }->{
						$rule->input_object}
				}, deref_code($rule->chain_id, $track) 
						if defined $rule->input_type;
			push @{ $UI::outputs{
						$rule->output_type }->{ 
						deref_code($rule->output_object, $track) }
			}, deref_code($rule->chain_id, $track) 
				if defined $rule->output_type;
		} @tracks;
	} @{ $bus->rules }; 
}

}

	
package ::Rule;
use ::Object qw( 	name
						chain_id

						target 
						depends_on

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
use ::Wav;
our @ISA = '::Wav';
{my $n = 0; # index
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
	my $class = shift;
	my %vals = @_;
	# croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	# (carp "name missing or already in use: $vals{name}\n"), return 
	# if ! $vals{name} or $track_names{$vals{name}}
	my $n = $vals{n} ? $vals{n} : ++$n; 

	return bless { 	name 	=> "Audio $n", # default name
					group	=> 'Tracker',  # default 
					rw   	=> 'REC', 
					n    	=> $n,
					@_ 			}, $class;
}
			

}
package ::Group;
use ::Object qw( 	name
						tracks
						rw
						version );

1;


__END__
my $mixer_out = UI::Rule->new(
	name			=> 'mixer_out', 
	chain_id		=> 'Mixer_out',

	target			=> 'none',
	depends_on		=> sub{},

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
	depends_on		=> sub{},

	input_type 		=> 'mixed', # bus name
	input_object	=> 'loop,222', # $loopb 

	output_type		=> 'file',
	output_object   => sub {
		my $track = shift; 
		join " ", $track->full_path, $mix_to_disk_format},

	#apply_inputs	=> sub{ },  
	#apply_outputs	=> sub{ },  

	default			=> 'off',
);
my $mix_setup = Rule->new(

	name			=>  'mix_setup',
	chain_id		=>  sub { my $track = shift, "J". $track->n },
	target			=>  'all',
	output_object	=>  'loop,111',
	output_type		=>  'cooked',
	default			=>  'on',
	depends_on 		=>  sub{ %{ $inputs{mixed} } },
		map{ push @{ $inputs{cooked}->{$n} }, $chain_id
		push @{ $outputs{ $loopa } } , $chain_id; 
	


my $mon_setup = Rule->new(
	
	name			=>  'mon_setup', 
	target			=>  'MON',
	chain_id 		=>	sub{ my $track = shift; $track->n },
	input_type		=>  'file',
	input_object	=>  sub{ my $track = shift; $track->full_path },
	output_type		=>  'cooked,
	output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
	default			=>  'on',
	post_input		=>	\&mono_to_stereo,
);
	
my $rec_file = Rule->new(

	name		=>  'rec_file', 
	target		=>  'REC',
	chain_id	=>  sub{ my $track = shift; 'R'. $track->n },   
	input_type	=>  'device',
	input_object=>  'multi',
	output_type	=>  'file',
	output_object   => sub {
		my $track = shift; 
		join " ", $track->full_path, $raw_to_disk_format},
	default		=>  'on',
}

# Rec_setup: must come last in oids list, convert REC
# inputs to stereo and output to loop device which will
# have Vol, Pan and other effects prior to various monitoring
# outputs and/or to the mixdown file output.
		
my $rec_setup = Rule->new(

	name			=>	'rec_setup', 
	chain_id		=>  sub{ my $track = shift; $track->n },   
	target			=>	'REC',
	input_type		=>  'device',
	input_object	=>  'multi',
	output_type		=>  'cooked',
	output_object	=>  sub{ my $track = shift; "loop," .  $track->n },
	post_input			=>	\&mono_to_stereo,
	default			=>  'on',
	depends_on 		=> @{ $inputs{cooked}->{"loop," .  $track->n} },
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

