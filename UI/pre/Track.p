
package ::Bus;
use Object::Tiny qw(	name
						groups
						tracks 
						rules
						
						);

my $track_bus = ::Bus->new(
	name => 'Tracker',
	groups => ['Tracker'],
	tracks => [],
	rules  => [],
);

my $master_fader  = ::Bus->new(
	name => 'Master',
	groups => ['Master'],
	rules  => [ @rules{qw(stereo)} ],
);
	


=comment
	tracks: sax, vocal, piano
	name:	Tracker / Mix / Master 
	rw
	templates: rec_setup, mon_setup, etc.
=cut


package ::Rule;
use Object::Tiny qw( 	name
						chain_id

						target 
						depends_on

						output_type
						output_name

						input_type
						input_name

						post_input
						pre_output );
						
#target: REC | MON | chain_id | all | none

my $stereo = ::Rule->new(
	name			=> 'stereo',
	chain_id		=> sub{ 'Stereo' },

	target			=> 'none',
	depends_on		=> sub{},

	input_type 		=> 'mixed',
	input_object	=> $loopb, 

	output_type		=> 'device',
	output_object	=> 'stereo',

	default			=> 'on',

);

my %rules;

$rules{ $stereo->name } = $stereo;


=comment
	push @{ $inputs { $oid->input_type  }->{ $oid->input_object  } },
		&{ $oid{chain_id} }($n);
	push @{ $outputs{ $oid->output_type }->{ $oid->output_object } },
		&{ $oid{chain_id} }($n);

=cut
package ::Track;
our @ISA = '::Wav';
{my $n = 0; # index
use Object::Tiny qw( 	name
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
	$n++;
	return bless { 	name 	=> "Audio $n", # default name
					group	=> 'Tracker',  # default 
					rw   	=> 'REC', 
					n    	=> $n,
					@_ 			}, $class;
}
			

}
package ::Group;
use Object::Tiny qw( 	name
						tracks
						rw
						version );

