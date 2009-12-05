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


1;
__END__

# first try

package ::IO; # base class for all IO objects
use Modern::Perl;
our $VERSION = 1.0;
our ($debug);
local $debug = 0;
use Carp;
our @ISA = ();
use vars qw($n @all %by_index) ;

use ::Object qw( 	direction
					type
					id
					format
					channel
					width

					ecasound_id
					post_input
					pre_output
				);

# unnecessary: direction (from class) type (claass) 
#

$n = 0;

sub new {
	
	my $class = shift;
	my %vals = @_;
	croak "undeclared field: @_" if grep{ ! $_is_field{$_} } keys %vals;
	my $n = $vals{n} // ++$n; 
	my $self = bless { n => $n, @_ }, $class;
	push @all, $self;
	$by_index{"I$n"} = $self;
	$self;
	
}

package ::IO::Source::Soundcard;
our @ISA = '::IO';
=comment
add_io(track => sax, direction => source, io_type => soundcard, 
	io_id => consumer channel => 3, width => 2);


modify_io
=cut

	
package ::IO::Sink::Soundcard;
our @ISA = '::IO';

package ::IO::Source::Jack_client;
our @ISA = '::IO';

	
package ::IO::Sink::Jack_client;
our @ISA = '::IO';

package ::IO::Sink::Track;
our @ISA = '::IO';

=comment

# second try

for our refactor:

@io; # array for holding IO::* objects that generate chain setup
dispatch($_);

sub dispatch {
	my $arr_ref = shift;
	my($name, $endpoint) = decode_edge($arr_ref);
	my $track = $tn{$name};
	my $class = io_class($endpoint);
	my $try = "$class->new(\$track, override(\$name))";
	push @io, eval $try;
	
}
	
sub decode_edge {
	# assume track-endpoint or endpoint-track
	# return track, endpoint
	my ($a, $b) = @$_[0];
	$tn{$a} ? @$_[0] : reverse @$_[0]
}

{ my %io = qw(
	null_in			::IO::from_null
	null_out		::IO::to_null
	soundcard_in 	::IO::from_soundcard
	soundcard_out 	::IO::to_soundcard
	wav_in 			::IO::from_wav
	wav_out 		::IO::to_wav
	loop_source		::IO::from_loop
	loop_sink		::IO::to_loop
	loop_in			::IO::from_loop
	loop_out		::IO::to_loop
	jack_client_in	::IO::from_jack_client
	jack_client_out ::IO::to_jack_client
	jack_port_in	::IO::from_jack_port
	jack_port_out 	::IO::to_jack_port
	jack_manual_in  ::IO::from_jack_port
	jack_manual_out ::IO::to_jack_port
	jack_multi_in	::IO::from_jack_multi
	jack_multi_out	::IO::to_jack_multi
	);

sub io_class { $io{$_[0]} or croak "unknown endpoint type: $_[0]"; }
}
package ::IO::base;
use Modern::Perl;
use Carp;
our @ISA = '::IO::base';
use ::Object qw(track chain_id direction type device_id);
{my %io = { input => 'i', output => 'o' };
sub ecs_string {
	my $self = shift;
	my @parts;
	push @parts, '-a:'.$self->chain_id;
	push @parts, '-f:'.$self->format if $self->format;
	push @parts, '-'.$io{$self->direction}.':'.$self->device_id;
	join ' ',@parts;
}
}
sub new {
	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	my $object = bless { @_	}, $class;
}

package ::IO::from_null;
use Modern::Perl;
use Carp;
our @ISA = '::IO::base';
use ::Object qw(track chain_id direction type device_id);
# sub direction { 'input' }
# sub type { 'device' }
# sub device_id {'null'}
sub ecs_extra { $_[0]->track->mono_to_stereo }

# sub write_chains
	
map { 	push @input_chains, $_->ecs_string;
		push @post_input, 	$_->ecs_extra if $_->ecs_extra; }
grep { $_->direction eq 'input' } @io;

map { 	push @output_chains, $_->ecs_string;
		push @pre_output, 	 $_->ecs_extra if $_->ecs_extra; }
grep { $_->direction eq 'output' } @io;
	
=cut
		
