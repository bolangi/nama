# ----------- Util.pm -----------

# this package is for small subroutines with
# well-defined interfaces

package ::;
our ( %tn );

package ::Util;
use Modern::Perl;

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(

rw_set
freq
channels
input_node
output_node
signal_format

) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = ();


## rw_set() for managing bus-level REC/MON/OFF settings commands
{
my %bus_logic = ( 
	mix_track =>
	{

	# setting mix track to REC
	# set bus to MON (user should set bus to REC)
	
		REC => sub
		{
			my ($bus, $track) = @_;
			$track->set_rec;
			$bus->set(rw => 'MON');
		},

	# setting mix track to MON 
	# set bus to OFF
	
		MON => sub
		{
			my ($bus, $track) = @_;
			$track->set_mon;
			$bus->set(rw => 'OFF');
		},
		OFF => sub
		{

	# setting mix track to OFF 
	# set bus to OFF
	
			my ($bus, $track) = @_;
			$track->set_off;
			$bus->set(rw => 'OFF');
		}
	},
	member_track =>
	{

	# setting member track to REC
	#
	# - set REC siblings to MON if bus is MON
	# - set all siblings to OFF if bus is OFF
	# - set bus to REC
	# - set mix track to REC/rec_defeat
	
		REC => sub 
		{ 
			my ($bus, $track) = @_;
			if ($bus->rw eq 'MON'){
				
				# set REC tracks to MON
				map{$_->set(rw => 'MON')  } 
				grep{$_->rw eq 'REC'} 
				map{$tn{$_}}
				$bus->tracks;

			}
			if ($bus->rw eq 'OFF'){
			
				# set all tracks to OFF 
				map{$_->set(rw => 'OFF')  } 
				map{$tn{$_}}
				$bus->tracks;
			}

			$track->set_rec;

			$bus->set(rw => 'REC');
			$tn{$bus->send_id}->busify;
			
		},

	# setting member track to MON 
	#
	# - set all siblings to OFF if bus is OFF
	# - set bus to MON
	# - set mix track to REC/rec_defeat
	
		MON => sub
		{ 
			my ($bus, $track) = @_;
			if ($bus->rw eq 'OFF'){
			
				# set all tracks to OFF 
				map{$_->set(rw => 'OFF')  } 
				map{$::tn{$_}}
				$bus->tracks;

				$bus->set(rw => 'MON');
			}
			$track->set_mon;
			#$tn{$bus->send_id}->busify; why needed????

		},

	# setting member track to OFF 

		OFF => sub
		{
			my ($bus, $track) = @_;
			$track->set_off;
		},
	},
);
sub rw_set {
	my ($bus,$track,$rw) = @_;
	my $type = $track->is_mix_track
		? 'mix_track'
		: 'member_track';
	$bus_logic{$type}{uc $rw}->($bus,$track);
}
}

sub freq { [split ',', $_[0] ]->[2] }  # e.g. s16_le,2,44100

sub channels { [split ',', $_[0] ]->[1] }
	
sub input_node { $_[0].'_in' }
sub output_node {$_[0].'_out'}

sub signal_format {
	my ($template, $channel_count) = @_;
	$template =~ s/N/$channel_count/;
	my $format = $template;
}
