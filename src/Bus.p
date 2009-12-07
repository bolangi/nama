# ------------  Bus --------------------

package ::Bus;
use Modern::Perl;
use Carp;
our $VERSION = 1.0;
our ($debug); # entire file
use vars qw(%by_name);
our @ISA;
use ::Object qw(						
[% qx(cat ./bus_fields) %]
						);

sub initialize { %by_name = () };
sub new {
	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	if (! $vals{name} or $by_name{$vals{name}}){
		carp($vals{name},": missing or duplicate bus name. Skipping.\n");
		return;
	}
	my $bus = bless { 
		tracks => [], 
		groups => [], 
		rules  => [],
		class => $class,
		@_ }, $vals{class} // $class;
	$by_name{$bus->name} = $bus;
}

1;
__END__
=comment

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
=cut
