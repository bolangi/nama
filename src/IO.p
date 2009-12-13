# ---------- IO -----------
package ::IO;
use Modern::Perl; use Carp;
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
our $AUTOLOAD;
#  subroutines
sub get_class {
	my ($type,$direction) = @_;
	::Graph::is_a_loop($type) and 
		return $io_class{ $direction eq 'input' ?  "loop_source" : "loop_sink"};
	$io_class{$type} or croak "unrecognized IO type: $type"
}
use ::Object qw( [% qx(./strip_all ./io_fields) %]);
sub new {
	my $class = shift;
	my $object = bless { @_	}, $class;
}
sub ecs_string {
	my $self = shift;
	my @parts;
	push @parts, '-f:'.$self->format if $self->format;
	push @parts, '-'.$self->direction.':'.$self->device_id;
	join ' ',@parts;
}
sub direction { (ref $_[0]) =~ /::from/ ? 'i' : 'o' }
sub AUTOLOAD {
	my $self = shift;
	# get tail of method call
	my ($method) = $AUTOLOAD =~ /([^:]+)$/;
	$::debug and say "self: $self, track: ", $self->track, " method: $method";
	my $result = q();
	$result = $::tn{$self->track}->$method if $::tn{$self->track};
	#$result = $::track_snapshots->{$self->track}{$method} 
	#	if $::track_snapshots->{$self->track};
	say "result: $result";
	$result;
}
our $new_mono_to_stereo = sub {
	my $class = shift;
	#my $io = $class->SUPER::new(@_); # SUPER seems to have limited use
	my $io = ::IO::new($class, @_);
	$io->set(ecs_extra => $io->mono_to_stereo) unless $io->ecs_extra;
	$io
};

package ::IO::from_null;
use Modern::Perl; our @ISA = '::IO';
sub device_id { 'null' }

package ::IO::to_null;
use Modern::Perl; our @ISA = '::IO';
sub device_id { 'null' }

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
sub new {
	my $class = shift;
	my $io = $class->SUPER::new(@_);
	if ( $io->width and ! $io->format ){
		$io->set(format => ::signal_format($::raw_to_disk_format, $io->width));
	}
	$io
}
sub device_id { $_[0]->full_path }

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
	my $class = $io_class{::soundcard_input_type_string()};
	$class->new(@_);
}

package Audio::Nama::IO::to_soundcard;
use Modern::Perl; our @ISA = '::IO';
sub new {
	shift; # throw away class
	my $class = $io_class{::soundcard_output_type_string()};
	$class->new(@_);
}

package ::IO::from_jack_client;
use Modern::Perl; our @ISA = '::IO';
sub new {
	my $io = ::IO::to_jack_client::new(@_);
}
sub ecs_extra { $_[0]->mono_to_stereo}

package ::IO::to_jack_client;
use Modern::Perl; our @ISA = '::IO';
sub new {
	my $class = shift;
	my $io = $class->SUPER::new(@_);
	my $client = $io->source_device_string;
	$io->set(device_id => "jack,$client");
	my $format;
	if ( $client eq 'system' ){ # we use the full soundcard width

		# shift track to correct output channel
		# we could use jack_multi for this

		$io->set(ecs_extra => $io->pre_send) if $io->pre_send;
		$format = ::signal_format(
			$::devices{jack}->{signal_format},

			# the number of channels
			::jack_client($client,q(input)) # client's input is our output
		);

	} else { # we use track width

		$format = ::signal_format(
					$::devices{jack}->{signal_format},	
					$io->width
		);
	}
	$io->set(format => $format);
	$io;
}

package ::IO::from_jack_multi;
use Modern::Perl; our @ISA = '::IO';
sub ecs_extra { $_[0]->mono_to_stereo }

package ::IO::to_jack_multi;
use Modern::Perl; our @ISA = '::IO';

package ::IO::from_jack_port;
use Modern::Perl; our @ISA = '::IO';
sub ecs_extra { $_[0]->mono_to_stereo }

package ::IO::to_jack_port;
use Modern::Perl; our @ISA = '::IO';

package ::IO::from_soundcard_device;
use Modern::Perl; our @ISA = '::IO';
sub ecs_extra { join ' ', $_[0]->rec_route, $_[0]->mono_to_stereo }
sub device_id { $::devices{$::alsa_capture_device}{ecasound_id} }

package ::IO::to_soundcard_device;
use Modern::Perl; our @ISA = '::IO';
sub device_id { $::devices{$::alsa_playback_device}{ecasound_id} }
sub ecs_extra { $_[0]->pre_send }

1;
__END__

		
