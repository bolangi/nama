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

package ::IO::base;
use Modern::Perl;
use Carp;
use ::Object qw(
[% qx(./strip_all ./io_fields) %]
);
sub new {
	my $class = shift;
	my $direction = $class =~ /::from/ ? 'input' : 'output';
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	my $track = $vals{track}; # may not exist

	# we will default to track chain number and input or output values
	# (these may be overridden)
	if ($track){
		say $track->name, ": source_type: ", $track->source_type, 
			", type: $vals{type}, class: $class";
		my ($type,$id) = @{ 
			$direction eq 'input'
				? $track->source_input 
				: $track->send_output
		};
		unshift @_, chain 		=> $track->n,
					direction 	=> $direction,
					type 		=> $type,
					device_id 	=> $id,
					width		=> $track->width,

					playat		=> $track->playat,
					region_start=> $track->region_start,
					region_end	=> $track->region_end,	
					modifiers	=> $track->modifiers,

		# TODO: move the following routines from Track
		# to IO::base

	
		# Alternatively, call $track->methods
		# inside ::IO::base subclasses where they are
		# needed. That will save duplication
		
					mono_to_stereo => $track->mono_to_stereo,
					route		=> $track->route,
					rec_route	=> $track->rec_route,
					full_path	=> $track->full_path,
					;
	}
	my $object = bless { @_	}, $class;
}
{my %io = ( input => 'i', output => 'o' );
sub ecs_string {
	my $self = shift;
	my @parts;
	push @parts, '-a:'.$self->chain_id;
	push @parts, '-f:'.$self->format if $self->format;
	push @parts, '-'.$io{$self->direction}.':'.$self->device_id;
	join ' ',@parts;
}
}

package ::IO::from_null;
use Modern::Perl;
use Carp;
use ::Object qw(
[% qx(./strip_all ./io_fields) %]
);
our @ISA = '::IO::base';
sub ecs_extra { $_[0]->mono_to_stereo }
sub device_id { 'null' }

1;
__END__


package ::;

#for our refactor:

#@io; # array for holding IO::* objects that generate chain setup
#dispatch($_);

# sub write_chains
	
map { 	push @input_chains, $_->ecs_string;
		push @post_input, 	$_->ecs_extra if $_->ecs_extra; }
grep { $_->direction eq 'input' } @io;

map { 	push @output_chains, $_->ecs_string;
		push @pre_output, 	 $_->ecs_extra if $_->ecs_extra; }
grep { $_->direction eq 'output' } @io;
	
=cut
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

		
