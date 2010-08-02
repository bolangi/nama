
# ------------  Bus --------------------
#
# The base class ::Bus is now used for grouping tracks
# serving the role of ::Group, which is now a 
# parent class.

package ::Bus;
use Modern::Perl; use Carp; our @ISA = qw( ::Object ::Group );
our $VERSION = 1.0;
our ($debug, %by_name); 
*debug = \$::debug;

use ::Object qw(
					name
					rw
					version 
					n	

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
	if (! $vals{name}){
		say "missing bus name"; 
		return
	}
	if ( $by_name{$vals{name}} ){ 
		say "$vals{name}: bus name already exists. Skipping.";
		return;
	}
	my $bus = bless { 
		class => $class, # for serialization, may be overridden
		rw   	=> 'REC', # for group control
		@_ }, $class;
	$by_name{$bus->name} = $bus;
}
sub group { $_[0]->name }

sub remove { say $_[0]->name, " is system bus. No can remove." }

{ my %allows = (REC => 'REC/MON', MON => 'MON');
sub allows { $allows{ $_[0]->rw } }
}
	
## class methods

# sub buses, and Main
sub all { grep{ ! $::is_system_bus{$_->name} } values %by_name };

sub overall_last { 
	my $max = 0;
	map{ my $last = $_->last; $max = $last if $last > $max  } all();
	$max;
}
	

### subclasses

package ::SubBus;
use Modern::Perl; use Carp; our @ISA = '::Bus';

# graphic routing: track -> mix_track

sub apply {
	my $bus = shift;
	return unless $::tn{$bus->name}->rec_status eq 'REC';
	map{ 
		# connect signal sources to tracks
		my @path = $_->input_path;
		$::g->add_path(@path) if @path;

		# connect tracks to mix track
		
		$::g->add_edge($_->name, $bus->name); 

	} grep{ $_->group eq $bus->group} ::Track::all()
}
sub remove {
	my $bus = shift;

	# all tracks returned to Main group
	map{$::tn{$_}->set(group => 'Main') } $::Bus::by_name{$bus->name}->tracks;

	# remove bus mix track
	$::tn{$bus->name}->remove;

	# remove bus
	delete $::Bus::by_name{$bus->name};
} 
package ::SendBusRaw;
use Modern::Perl; use Carp; our @ISA = '::Bus';
sub apply {
	my $bus = shift;
	map{ 
		$::g->add_edge($_->input_path);
		my @edge = ($_->name, ::output_node($bus->send_type));
		$::g->add_edge(@edge);
		$::g->set_edge_attributes( @edge, { 
			send_id => $bus->send_id,
			width => 2 }); # force to stereo 
	} grep{ $_->group eq $bus->group and $_->input_path} ::Track::all()
}
sub remove {
	my $bus = shift;

	# delete all (slave) tracks
	map{$::tn{$_}->remove } $::Bus::by_name{$bus->name}->tracks;

	# remove bus
	delete $::Bus::by_name{$bus->name};
}
package ::SendBusCooked;
use Modern::Perl; use Carp; our @ISA = '::SendBusRaw';

# graphic routing: target -> slave -> bus_send_type

sub apply {
	my $bus = shift;
	map{ my @edge = ($_->name, ::output_node($bus->send_type));
		 $::g->add_path( $_->target, @edge);
		 $::g->set_edge_attributes( @edge, { 
				send_id => $bus->send_id,
				width => 2})
	} grep{ $_->group eq $bus->group} ::Track::all()
}

1;
__END__
