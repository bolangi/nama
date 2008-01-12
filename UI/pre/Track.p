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
				push @{ $UI::inputs { $rule->input_type  }
								->{ $rule->input_object  } },
									&{ $rule->chain_id }($n);
				push @{ $UI::outputs{ $rule->output_type }
								->{ $rule->output_object } },
									&{ $rule->chain_id }($n);
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

						input_type
						input_object

						post_input
						pre_output 
						
						default ); # on or off

						
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
