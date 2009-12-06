# ---------- IO -----------

package ::IO_Helper;
use strict;
our $VERSION = 1.0;
our ($debug);
local $debug = 0;
use Carp;
our @ISA = ();

use ::Object qw( 		type
						object
						format

						);

# type (string): loop, device, file, etc.
# object (string): Ecasound device, with optionally appended format string
# format (string): Ecasound format string



sub new {
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	bless \%vals, $class;
	
}

package ::IO;
use Modern::Perl;
use Carp;
our %io_class = qw(
	null_in					::IO::from_null
	null_out				::IO::to_null
	soundcard_in 			::IO::from_soundcard
	soundcard_out 			::IO::to_soundcard
	soundcard_device_in 	::IO::from_soundcard_device
	soundcard_device_out 	::IO::to_soundcard_device
	wav_in 					::IO::from_wav
	wav_out 				::IO::to_wav
	loop_source				::IO::from_loop
	loop_sink				::IO::to_loop
	loop_in					::IO::from_loop
	loop_out				::IO::to_loop
	jack_client_in			::IO::from_jack_client
	jack_client_out 		::IO::to_jack_client
	jack_port_in			::IO::from_jack_port
	jack_port_out 			::IO::to_jack_port
	jack_manual_in  		::IO::from_jack_port
	jack_manual_out 		::IO::to_jack_port
	jack_multi_in			::IO::from_jack_multi
	jack_multi_out			::IO::to_jack_multi
	);

use ::Object qw(
[% qx(./strip_all ./io_fields) %]
);
sub new {
	my $class = shift;
	#my $direction = $class =~ /::from/ ? 'input' : 'output';
	my $direction = ($class =~ /::from/ ? 'input' : 'output');
	say "class: $class, direction: $direction";
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	my $track = $vals{track}; # may not exist

	# we will default to track chain number and input or output values
	# (these may be overridden)
	push @_, direction 	=> $direction;
	if ($track){
		my ($type,$id) = @{ 
			$direction eq 'input'
				? $track->source_input   # not reliable in MON case
				: $track->send_output
		};
		say $track->name, ": source_type: ", $track->source_type, 
			", type: $type, id: $id, class: $class";
		my %h;
		my @assign = qw(
				chain_id 		$track->n
				type 			$type
				device_id 		$id
				width			$track->width
				playat			$track->playat
				region_start	$track->region_start
				region_end		$track->region_end	
				modifiers		$track->modifiers
				mono_to_stereo  $track->mono_to_stereo
				route			$track->route
				rec_route		$track->rec_route
				full_path		$track->full_path
		);

		while ( my($key, $var) = splice @assign, 0, 2 ){
			$h{$key} = eval $var;
		}
		say yaml_out \%h;
		unshift @_, %h;

		# TODO: move the following routines from Track
		# to IO

	
		# Alternatively, call $track->methods
		# inside ::IO subclasses where they are
		# needed. That will save duplication
		
	say join $/, "all fields", @_;
	}
	my $object = bless { @_	}, $class;
}
{my %io = ( input => 'i', output => 'o' );
sub ecs_string {
	my $self = shift;
	my @parts;
	push @parts, $self->a_op();
	push @parts, '-f:'.$self->format if $self->format;
	push @parts, '-'.$io{$self->direction}.':'.$self->device_id;
	join ' ',@parts;
}
}
sub a_op { '-a:'.$_[0]->chain_id }

package ::IO::from_null;
use Modern::Perl; use Carp; our @ISA = '::IO';
sub ecs_extra { $_[0]->mono_to_stereo }
sub device_id { 'null' }

package ::IO::to_null;
use Modern::Perl; use Carp; our @ISA = '::IO';
sub device_id { 'null' }

package ::IO::from_wav;
use Modern::Perl; use Carp; our @ISA = '::IO';
sub device_id { $_[0]->full_path }
sub ecs_extra { $_[0]->mono_to_stereo }

package ::IO::to_wav;
use Modern::Perl; use Carp; our @ISA = '::IO';
sub device_id { $_[0]->full_path }
# format

package ::IO::from_loop;
use Modern::Perl; use Carp; our @ISA = '::IO';
sub new {
	my $class = shift;
	my %vals = @_;
	::IO::new($class, %vals, device_id => "loop,$vals{endpoint}");
}

package ::IO::to_loop;
use Modern::Perl; use Carp; our @ISA = '::IO';
sub new {
	my $class = shift;
	my %vals = @_;
	::IO::new($class, %vals, device_id => "loop,$vals{endpoint}");
}

package ::IO::from_soundcard;
use Modern::Perl; use Carp; our @ISA = '::IO';
sub ecs_extra { join " ", $_[0]->rec_route , $_[0]->mono_to_stereo }

package ::IO::to_soundcard;
use Modern::Perl; use Carp; our @ISA = '::IO';
sub new {
	my $class = shift;
	my %vals = @_;
	my ($type, $id) = @{ ::soundcard_output2()};
	my $try = ::io_class($type) . q{->new(@_, device_id => $id)};
	say "soundcard constructor eval: $try";
	eval $try;
}
# sub ecs_extra { $_[0]->pre_send} # not a default, belongs
# in constructor

package ::IO::from_jack_client;
use Modern::Perl; use Carp; our @ISA = '::IO';

package ::IO::to_jack_client;
use Modern::Perl; use Carp; our @ISA = '::IO';

package ::IO::from_jack_multi;
use Modern::Perl; use Carp; our @ISA = '::IO';

package ::IO::to_jack_multi;
use Modern::Perl; use Carp; our @ISA = '::IO';

package ::IO::from_jack_port;
use Modern::Perl; use Carp; our @ISA = '::IO';

package ::IO::to_jack_port;
use Modern::Perl; use Carp; our @ISA = '::IO';

package ::IO::from_soundcard_device;
use Modern::Perl; use Carp; our @ISA = '::IO';
sub new {
	my $class = shift;
	my %vals = @_;
	my $device = $::devices{$vals{device_id}}{ecasound_id};
	::IO::new($class, @_, device_id => $device);
}

package ::IO::to_soundcard_device;
use Modern::Perl; use Carp; our @ISA = '::IO::from_soundcard_device';

1;
__END__

		
