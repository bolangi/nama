# ---------- IO -----------
# 
# IO objects for writing Ecasound chain setup file
#
# Three ways we set object values:
# 
# 1. Using the constructor new()
# 2. Defining a method (generally clobbers constructor values)
# 3. AUTOLOAD calling undefined methods on the associated track
package ::IO;
use Modern::Perl; use Carp;

# we will use the following to map from graph node names
# to IO class names

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
	jack_port_in			::IO::from_jack_port
	jack_port_out 			::IO::to_jack_port
	jack_multi_in			::IO::from_jack_multi
	jack_multi_out			::IO::to_jack_multi
	);

### class definition

our $AUTOLOAD;

# add underscore to field names so that regular method
# access will go through AUTOLOAD

# we add an underscore to each key 

use ::Object qw([%join " ",map{"$_\_" }split " ", qx(./strip_all ./io_fields)%]);

use Try::Tiny;

sub new {
	my $class = shift;
	my %vals = @_;
	my @args = map{$_."_", $vals{$_}} keys %vals; # add underscore to key 
	bless {@args}, $class
}

sub ecs_string {
	my $self = shift;
	my @parts;
	push @parts, '-f:'.$self->format if $self->format;
	push @parts, '-'.$self->io_prefix.':'.$self->device_id;
	join ' ',@parts;
}
sub format { 
	my $self = shift;
	::signal_format($self->format_template, $self->width)
		if $self->format_template and $self->width
}
#sub _direction { # allow override
sub direction { # allow override
	(ref $_[0]) =~ /::from/ ? 'input' : 'output' 
}
sub io_prefix { substr $_[0]->direction, 0, 1 } # 'i' or 'o'

sub AUTOLOAD {
	my $self = shift;
	# get tail of method call
	my ($call) = $AUTOLOAD =~ /([^:]+)$/;
	my $result = q();
	my $field = "$call\_";
	my $method = "_$call";
	return $self->{$field} if exists $self->{$field};
	return $self->$method if $self->can($method);
	local $@;
	eval { $::tn{$self->{track_}}->$call }
}

sub DESTROY {}

###  utility subroutines

sub get_class {
	my ($type,$direction) = @_;
	::Graph::is_a_loop($type) and 
		return $io_class{ $direction eq 'input' ?  "loop_source" : "loop_sink"};
	$io_class{$type} or croak "unrecognized IO type: $type"
}
sub soundcard_input_type_string {
	$::jack_running ? 'jack_multi_in' : 'soundcard_device_in'
}
sub soundcard_output_type_string {
	$::jack_running ? 'jack_multi_out' : 'soundcard_device_out'
}
sub soundcard_input_device_string {
	$::jack_running ? 'system' : $::alsa_capture_device
}
sub soundcard_output_device_string {
	$::jack_running ? 'system' : $::alsa_playback_device
}
sub jack_multi_route {
	my ($client, $direction, $start, $width)  = @_;
	my $end   = $start + $width - 1;
	$direction .= '_prefix'; # key
	join q(,),q(jack_multi),
	map{"$client\:$::jack{$client}{$direction}$_"} $start..$end
}

### subclass definitions

### we add an underscore _ to any method name that
### we want to override
package ::IO::from_null;
use Modern::Perl; our @ISA = '::IO';
sub device_id { 'null' } # 

package ::IO::to_null;
use Modern::Perl; our @ISA = '::IO';
sub device_id { 'null' }  # underscore for testing

package ::IO::from_wav;
use Modern::Perl; our @ISA = '::IO';
sub device_id { 
	my $io = shift;
	my @modifiers;
	push @modifiers, $io->playat_output if $io->playat_output;
	push @modifiers, $io->select_output if $io->select_output;
	push @modifiers, split " ", $io->modifiers if $io->modifiers;
	push @modifiers, $io->full_path;
	join(q[,],@modifiers);
}
sub ecs_extra { $_[0]->mono_to_stereo}

package ::IO::to_wav;
use Modern::Perl; our @ISA = '::IO';
sub device_id { $_[0]->full_path }
# enable override
sub format_template { $_[0]->{format_template} || $::raw_to_disk_format } 

package ::IO::from_loop;
use Modern::Perl; our @ISA = '::IO';
sub new {
	my $class = shift;
	my %vals = @_;
	$class->SUPER::new( %vals, device_id => "loop,$vals{endpoint}");
}
package ::IO::to_loop;
use Modern::Perl; our @ISA = '::IO::from_loop';

package ::IO::from_soundcard;
use Modern::Perl; our @ISA = '::IO';
sub new {
	shift; # throw away class
	my $class = $io_class{::IO::soundcard_input_type_string()};
	$class->new(@_);
}
package Audio::Nama::IO::to_soundcard;
use Modern::Perl; our @ISA = '::IO';
sub new {
	shift; # throw away class
	my $class = $io_class{::IO::soundcard_output_type_string()};
	$class->new(@_);
}
package ::IO::from_jack_client;
use Modern::Perl; our @ISA = '::IO';
sub device_id { 'jack,'.$_[0]->source_device_string}
sub ecs_extra { $_[0]->mono_to_stereo}

package ::IO::to_jack_multi;
use Modern::Perl; our @ISA = '::IO';
sub device_id { 
	my $io = shift;
	# maybe source_id is an input number
	my $client = $io->direction eq 'input' 
		? $io->source_id
		: $io->send_id;
	my $channel = 1;
	# confusing, but the direction is with respect to the client
	my $direction = $io->direction eq 'input' ? 'output' : 'input';
	if( ::dest_type($client) eq 'soundcard'){
		$channel = $client;
		$client = ::IO::soundcard_input_device_string(); # system, okay for output
	}
	::IO::jack_multi_route($client,$direction,$channel,$io->width )
}
# don't need to specify format, since we take all channels

package ::IO::from_jack_multi;
use Modern::Perl; our @ISA = '::IO::to_jack_multi';
sub ecs_extra { $_[0]->mono_to_stereo }

package ::IO::to_jack_port;
use Modern::Perl; our @ISA = '::IO';
sub format_template { $::devices{jack}{signal_format} }
sub device_id { 'jack,,'.$_[0]->name.'\_out' }

package ::IO::from_jack_port;
use Modern::Perl; our @ISA = '::IO::to_jack_port';
sub device_id { 'jack,,'.$_[0]->name.'\_in' }
sub ecs_extra { $_[0]->mono_to_stereo }

package ::IO::from_soundcard_device;
use Modern::Perl; our @ISA = '::IO';
sub ecs_extra { join ' ', $_[0]->rec_route, $_[0]->mono_to_stereo }
sub device_id { $::devices{$::alsa_capture_device}{ecasound_id} }

package ::IO::to_soundcard_device;
use Modern::Perl; our @ISA = '::IO';
sub device_id { $::devices{$::alsa_playback_device}{ecasound_id} }
sub ecs_extra { $_[0]->pre_send }

package ::IO::any;
use Modern::Perl; our @ISA = '::IO';


1;
__END__

