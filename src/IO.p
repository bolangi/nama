# ---------- IO -----------
package ::IO;
use Modern::Perl;
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

use ::Object qw( [% qx(./strip_all ./io_fields) %]);
sub new {
	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	my $track = $vals{track}; # may not exist

	# we will default to track chain number and input or output values
	# (these may be overridden)
	if ($track){
		my ($type,$id) = @{ 
			$vals{direction} eq 'input'
				? $track->source_input   # not reliable in MON case
				: $track->send_output
		};
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
				source_input	$track->source_input
				send_output		$track->send_output
		);

		while ( my($key, $var) = splice @assign, 0, 2 ){
			$h{$key} = eval $var and $@ and croak "$var: eval failed: $@";
		}
		say ::yaml_out \%h;
		unshift @_, %h;  # other arguments (in %h) will supersede track values

		# TODO: move the following routines from Track
		# to IO
	
		# Alternatively, call $track->methods
		# inside ::IO subclasses where they are
		# needed. That will save duplication
		
	say join " ", "all fields", @_;
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
our $new_mono_to_stereo = sub {
	my $class = shift;
	#my $io = $class->SUPER::new(@_);
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
*new = $::IO::new_mono_to_stereo;
sub device_id { $_[0]->full_path }

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
	::IO::new($class, %vals, device_id => "loop,$vals{endpoint}");
}

package ::IO::to_loop;
use Modern::Perl; our @ISA = '::IO::from_loop';

package ::IO::from_soundcard;
use Modern::Perl; our @ISA = '::IO';
sub new {
	my $class = shift;
	my %vals = @_;
	my $io = ::IO->new(@_); # to get type... may be jack
	say "io class: ",ref $io;
	my ($type, $id) = ($io->type, $io->device_id);
	say "type: $type, id: $id";
	$class = ::io_class($type);
	$class->new(@_);
}

package ::IO::to_soundcard;
use Modern::Perl; our @ISA = '::IO';
sub new {
	my $class = shift;
	my %vals = @_;
	my ($type, $id) = @{ ::soundcard_output()};
	$class = ::io_class($type);
	$class->new(@_, device_id => $id);
}

package ::IO::from_jack_client;
use Modern::Perl; our @ISA = '::IO::to_jack_client';
*new = $::IO::new_mono_to_stereo;

package ::IO::to_jack_client;
use Modern::Perl; our @ISA = '::IO';
sub new {
	my $class = shift;
	my $io = ::IO::new($class, @_);
	my $client = $io->device_id;
	$io->set(device_id => "jack,$client");
	my $format;
	if ( $client eq 'system' ){ # we use the full soundcard width

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
*new = $::IO::new_mono_to_stereo;

package ::IO::to_jack_multi;
use Modern::Perl; our @ISA = '::IO';

package ::IO::from_jack_port;
use Modern::Perl; our @ISA = '::IO';
*new = $::IO::new_mono_to_stereo;

package ::IO::to_jack_port;
use Modern::Perl; our @ISA = '::IO';

package ::IO::from_soundcard_device;
use Modern::Perl; our @ISA = '::IO';
sub new {
	my $class = shift;
	my $io = ::IO::new($class, @_);
	#say "io device1: ",$io->device_id;
	my $device = $::devices{$io->device_id}{ecasound_id};
	$io->set(device_id => $device);
	$io->set(ecs_extra => join " ", $io->rec_route, $io->mono_to_stereo) 
		unless $io->ecs_extra;
	#say "io device2: ",$io->device_id;
	$io;
}

package ::IO::to_soundcard_device;
use Modern::Perl; our @ISA = '::IO';
sub new {
	my $class = shift;
	my $io = ::IO::new($class, @_);
	my $dubious_dev = $io->device_id;
	# override device_id with default unless meaningful value present
	if ( ! $::devices{$dubious_dev} ){  
		$io->set(device_id => $::alsa_playback_device);
	}
	my $device = $::devices{$io->device_id}{ecasound_id};
	$io->set(device_id => $device);
	$io;
}

1;
__END__

		
