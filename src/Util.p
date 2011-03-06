# ----------- Util.pm -----------

# this package is for small subroutines with
# well-defined interfaces

package ::;
our ( %tn ); 			# rw_set()
our ( $chain_setup); 	# really_recording()

package ::Util;
use Modern::Perl; use Carp;
no warnings 'uninitialized';

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(

rw_set
freq
channels
input_node
output_node
signal_format
process_is_running
really_recording
d1
d2
dn
round
colonize
time_tag
heuristic_time
dest_type

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
sub process_is_running {
	my $name = shift;
	my @pids = split " ", qx(pgrep $name);
	my @ps_ax  = grep{   my $pid;
						/$name/ and ! /defunct/
						and ($pid) = /(\d+)/
						and grep{ $pid == $_ } @pids 
				} split "\n", qx(ps ax) ;
}
# return file output entries, including Mixdown 
sub really_recording { 
	map{ /-o:(.+?\.wav)$/} grep{ /-o:/ and /\.wav$/} split "\n", $chain_setup
}
sub d1 {
	my $n = shift;
	sprintf("%.1f", $n)
}
sub d2 {
	my $n = shift;
	sprintf("%.2f", $n)
}
sub dn {
	my ($n, $places) = @_;
	sprintf("%." . $places . "f", $n);
}
sub round {
	my $n = shift;
	return 0 if $n == 0;
	$n = int $n if $n > 10;
	$n = d2($n) if $n < 10;
	$n;
}
sub colonize { # convert seconds to hours:minutes:seconds 
	my $sec = shift || 0;
	my $hours = int ($sec / 3600);
	$sec = $sec % 3600;
	my $min = int ($sec / 60);
	$sec = $sec % 60;
	$sec = "0$sec" if $sec < 10;
	$min = "0$min" if $min < 10 and $hours;
	($hours ? "$hours:" : "") . qq($min:$sec);
}



sub time_tag {
	my @time = localtime time;
	$time[4]++;
	$time[5]+=1900;
	@time = @time[5,4,3,2,1,0];
	sprintf "%4d.%02d.%02d-%02d:%02d:%02d", @time
}

sub heuristic_time {
	my $sec = shift;
	d1($sec) .  ( $sec > 120 ? " (" . colonize( $sec ) . ") "  : " " )
}

sub dest_type {
	my $dest = shift;
	my $type;
	given( $dest ){
		when( undef )       {} # do nothing

		# non JACK related

		when('bus')			   { $type = 'bus'             }
		when('null')           { $type = 'null'            }
		when(/^loop,/)         { $type = 'loop'            }

		when(! /\D/)           { $type = 'soundcard'       } # digits only

		# JACK related

		when(/^man/)           { $type = 'jack_manual'     }
		when('jack')           { $type = 'jack_manual'     }
		when(/(^\w+\.)?ports/) { $type = 'jack_ports_list' }
		default                { $type = 'jack_client'     } 

	}
	$type
}

1;
__END__

