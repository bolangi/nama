
# ------------  Bus --------------------

package ::Bus;
use Modern::Perl; use Carp; our @ISA;
our $VERSION = 1.0;
our ($debug, %by_name); 
use ::Object qw(
					name
					destinations
					send_type
					send_id
					class
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
		class => $class, # for serialization, may be overridden
		@_ }, $vals{class} // $class; # for restore
	$by_name{$bus->name} = $bus;
}
sub group { $_[0]->name }
sub all { values %by_name };

sub remove { say $_[0]->name, " is system bus. No can remove." }

# obsolete
#
# we will put the following information in the Track as an aux_send
# 						destination_type
# 						destination_id
# name, init capital e.g. Brass, identical Group name
# destination: 3, jconv, loop,output


package ::SubBus;
use Modern::Perl; use Carp; our @ISA = '::Bus';
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
use Modern::Perl; use Carp;
sub remove {
	my $bus = shift;

	# delete all (slave) tracks
	map{$::tn{$_}->remove } $::Group::by_name{$bus->name}->tracks;

	# delete group
	$::Group::by_name{$bus->name}->remove;

	# remove bus
	delete $::Bus::by_name{$bus->name};
}
sub apply {
	my $bus = shift;
	map{ $::g->add_path( $_->target, $_->name, $bus->send_type.'_out');
		 $::g->set_edge_attributes($_->_name, $bus->send_type.'out', 
		{ device_id => $bus->send_id })
	} grep{ $_->group eq $bus->group} ::Track::all()
}
package ::SendBusCooked;
use Modern::Perl; use Carp; our @ISA = '::SendBusRaw';

1;
__END__
