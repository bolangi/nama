
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


		
sub all { values %by_name };

sub remove { say $_[0]->name, " is system bus, no can remove" }

# we will put the following information in the Track as an aux_send
# 						destination_type
# 						destination_id
# name, init capital e.g. Brass, identical Group name
# destination: 3, jconv, loop,output


package ::SubBus;
use Modern::Perl;
use Carp;
our @ISA = '::Bus';

use ::Object qw(
[% qx(cat ./bus_fields) %]
);
sub remove {
	my $bus = shift;

	# all tracks returned to Main group
	map{$::tn{$_}->set(group => 'Main') } $::Group::by_name{$bus->name}->tracks;

	# remove bus mix track
	$::tn{$bus->name}->remove;

	# delete group
	$::Group::by_name{$bus->name}->remove;

	# remove bus
	delete $::Bus::by_name{$bus->name};
} 

package ::SendBusRaw;
use Modern::Perl;
use Carp;
our @ISA = '::Bus';
use ::Object qw(
[% qx(cat ./bus_fields ) %]

);
sub remove {
	my $bus = shift;

	# delete all (slave) tracks
	map{$::tn{$_}->remove } $::Group::by_name{$bus->name}->tracks;

	# delete group
	$::Group::by_name{$bus->name}->remove;

	# remove bus
	delete $::Bus::by_name{$bus->name};
}
package ::SendBusCooked;
use Modern::Perl;
use Carp;
our @ISA = '::SendBusRaw';
use ::Object qw(
[% qx(cat ./bus_fields ) %]
);



1;
__END__
