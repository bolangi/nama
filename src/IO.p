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
	jack_client_in			::IO::from_jack_multi
	jack_client_out			::IO::to_jack_multi
	);

### class definition

our $AUTOLOAD;

# add underscore to field names so that regular method
# access will go through AUTOLOAD

# we add an underscore to each key 

use ::Object qw([%join " ",map{$_."_" }split " ", qx(./strip_all ./io_fields)%]);

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
sub direction { 
	(ref $_[0]) =~ /::from/ ? 'input' : 'output' 
}
sub io_prefix { substr $_[0]->direction, 0, 1 } # 'i' or 'o'

my %dont_fall_through = (ecs_extra => 1, format_template => 1);
sub AUTOLOAD {
	my $self = shift;
	# get tail of method call
	my ($call) = $AUTOLOAD =~ /([^:]+)$/;
	my $result = q();
	my $field = "$call\_";
	my $method = "_$call";
	return $self->{$field} if exists $self->{$field};
	return $self->$method if $self->can($method);
	if ( my $track = $::tn{$self->{track_}} ){
		return $track->$call if $track->can($call)
	}
	return if $dont_fall_through{$call};
	croak "Autoload fell through. Object type: ", (ref $self), ", illegal method call: $call\n";
}

sub DESTROY {}


# The following are track-related routines that belong here
# because they are only used in generating chain setups.
# They are accessed via AUTOLOAD, querying the track object
# associated with a particular IO object

# If there is no track for an object, the object must
# provide any needed data

sub mono_to_stereo { 
	my $self = shift;
	my $cmd = "file " .  $self->full_path;
	if ( 	$self->width == 2 and $self->rec_status eq 'REC'
		    or  -e $self->full_path
				and qx(which file)
				and qx($cmd) =~ /stereo/i ){ 
		return q(); 
	} elsif ( ($self->width == 1 or ! $self->width) and $self->rec_status eq 'REC'
				or  -e $self->full_path
				and qx(which file)
				and qx($cmd) =~ /mono/i ){ 
		return "-chcopy:1,2" 
	} else { # do nothing for higher channel counts
	} 
}
sub soundcard_input { 
	[::IO::soundcard_input_type_string(), $_[0]->source_id()]
}
sub source_input {
	my $track = shift;
	given ( $track->source_type ){
		when ( 'soundcard'  ){ return $track->soundcard_input }
		when ( 'jack_client'){
			if ( $::jack_running ){ return ['jack_multi_in', $track->source_id] }
			else { 	say($track->name. ": cannot set source ".$track->source_id
				.". JACK not running."); return [] }
		}
		when ( 'loop'){ return ['loop_source',$track->source_id ] } 
		when ('jack_port'){
			if ( $::jack_running ){ return ['jack_port_in', $track->source_id] }
			else { 	say($track->name. ": cannot set source ".$track->source_id
				.". JACK not running."); return [] }
		}
		default { say $track->name, ": unsupported source type: $_"; return [] }
	}
}

sub source_type_string { $_[0]->source_input()->[0] }
sub source_device_string { $_[0]->source_input()->[1] }
sub send_output {
	my $track = shift;
	given ($track->send_type){
		when ( 'soundcard' ){ 
			if ($::jack_running) {
				return ['jack_multi_out', 'system']
			} else {return [ 'soundcard_device_out', $track->send_id] }
		}
		when ('jack_client') { 
			if ($::jack_running){return [ 'jack_multi_out', $track->send_id] }
			else { carp $track->name . 
					q(: auxilary send to JACK client specified,) .
					q( but jackd is not running.  Skipping.);
					return [];
			}
		}
		when ('loop') { return [ 'loop_sink', $track->send_id ] }
			
		default { return [] }
	}
 };

sub send_type_string { $_[0]->send_output()->[0] }
sub send_device_string { $_[0]->send_output()->[1] }
sub playat_output {
	my $track = shift;
	if ( $track->playat_time ){
		join ',',"playat" , $track->playat_time;
	}
}

sub select_output {
	my $track = shift;
	if ( $track->region_start and $track->region_end){
		my $end = $track->region_end_time;
		my $start = $track->region_start_time;
		my $length = $end - $start;
		join ',',"select", $start, $length
	}
}


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
sub _device_id { 'null' } # 

package ::IO::to_null;
use Modern::Perl; our @ISA = '::IO';
sub _device_id { 'null' }  # underscore for testing

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
sub _format_template { $::raw_to_disk_format } 

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
sub device_id { 'jack,,'.$_[0]->port_name.'_out' }

package ::IO::from_jack_port;
use Modern::Perl; our @ISA = '::IO::to_jack_port';
sub device_id { 'jack,,'.$_[0]->port_name.'_in' }
sub ecs_extra { $_[0]->mono_to_stereo }

package ::IO::from_soundcard_device;
use Modern::Perl; our @ISA = '::IO';
sub ecs_extra { join ' ', $_[0]->rec_route, $_[0]->mono_to_stereo }
sub device_id { $::devices{$::alsa_capture_device}{ecasound_id} }
sub input_channel { $_[0]->source_id }
sub rec_route {
	# works for mono/stereo only!
	no warnings qw(uninitialized);
	my $self = shift;
	# needed only if input channel is greater than 1
	return '' if ! $self->input_channel or $self->input_channel == 1; 
	
	my $route = "-chmove:" . $self->input_channel . ",1"; 
	if ( $self->width == 2){
		$route .= " -chmove:" . ($self->input_channel + 1) . ",2";
	}
	return $route;
}
package ::IO::to_soundcard_device;
use Modern::Perl; our @ISA = '::IO';
sub device_id { $::devices{$::alsa_playback_device}{ecasound_id} }
sub ecs_extra {route(2,$_[0]->output_channel) } # assume stereo signal
sub output_channel { $_[0]->send_id }
sub route2 {
	my ($from, $to, $width) = @_;
}
sub route {
	# routes signals (1..$width) to ($dest..$dest+$width-1 )
	
	my ($width, $dest) = @_;
	return undef if $dest == 1 or ! $dest;
	# print "route: width: $width, destination: $dest\n\n";
	my $offset = $dest - 1;
	my $route ;
	for my $c ( map{$width - $_ + 1} 1..$width ) {
		$route .= " -chmove:$c," . ( $c + $offset);
	}
	$route;
}

package ::IO::any;
use Modern::Perl; our @ISA = '::IO';


1;
__END__

