package ::Insert;
use Modern::Perl;
use Carp;
no warnings qw(uninitialized redefine);
our $VERSION = 0.1
our ($debug);
local $debug = 0;
use vars qw(%by_index);
use ::Object qw(
	insert_type
	class
	send_type
	send_id
	return_type
	return_id
	wetness
	tracks
	wet_track
	dry_track
	wetness
);

initialize();

sub initialize { %by_index = () }

sub idx { # return first free track index
	my $n = 0;
	while (++$n){
		return $n if not $by_index{$n}
	}
}

sub new {
	my $class = shift;
	my %vals = @_;
	my @undeclared = grep{ ! $_is_field{$_} } keys %vals;
    croak "undeclared field: @undeclared" if @undeclared;
	my $n = $vals{n} || idx(); 
	my $object = bless { 
					class	=> $class, # for restore
					@_ 			}, $class;
	$by_index{$n} = $object;
}

package ::PostFaderInsert;

sub add_insert_cooked {
	my ($send_id, $return_id) = @_;
	my $old_this_track = $this_track;
	my $t = $::this_track;
	my $name = $t->name;
	$t->remove_insert;
	my $i = {
		insert_type => 'cooked',
		send_type 	=> ::dest_type($send_id),
		send_id	  	=> $send_id,
		return_type 	=> ::dest_type($return_id),
		return_id	=> $return_id,
		wetness		=> 100,
	};
	# default to return from same JACK client or adjacent soundcard channels
	# default to return via same system (soundcard or JACK)
	if (! $i->{return_id}){
		$i->{return_type} = $i->{send_type};
		$i->{return_id} =  $i->{send_id} if $i->{return_type} eq 'jack_client';
		$i->{return_id} =  $i->{send_id} + 2 if $i->{return_type} eq 'soundcard';
	}

	
	$t->set(inserts => $i); 1;

	# we slave the wet track to the original track so that
	# we know the external output (if any) will be identical
	
	my $wet = ::SlaveTrack->new( 
				name => "$name\_wet",
				target => $name,
				group => 'Insert',
				rw => 'REC',
				hide => 1,
			);
	# in the graph we will override the input with the insert's return source

	# we slave the dry track to the original track so that
	# we know the external output (if any) will be identical
	
	my $dry = ::SlaveTrack->new( 
				name => "$name\_dry", 
				target => $name,
				group => 'Insert',
				hide => 1,
				rw => 'REC');

	# the input fields will be ignored, since the track will get input
	# via the loop device track_insert
	
	$i->{dry_vol} = $dry->vol;
	$i->{wet_vol} = $wet->vol;
	
	$i->{tracks} = [ $wet->name, $dry->name ];
	$this_track = $old_this_track;
}

