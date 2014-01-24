# ----------- Util.pm -----------

# this package is for small subroutines with
# well-defined interfaces

package ::Util;
use Modern::Perl; 
use Carp;
use Data::Dumper::Concise;
use ::Assign qw(json_out);
use ::Globals qw(:all);
use ::Log qw(logit logsub logpkg);

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
	d1
	d2
	dn
	round
	colonize
	time_tag
	heuristic_time
	dest_type
	dest_string

	create_dir
	join_path
	wav_off
	strip_all
	strip_blank_lines
	strip_comments
	remove_spaces
	expand_tilde
	resolve_path
	dumper

) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = ();


## rw_set() for managing bus-level REC/MON/OFF settings commands
{
my %bus_logic = ( 
	mix_track =>
	{

	# setting mix track to REC
	
		REC => sub
		{
			my ($bus, $track) = @_;
			$track->set_rec;
		},

	# setting a mix track to PLAY
	
		PLAY => sub
		{
			my ($bus, $track) = @_;
			$track->set_play;
		},

	# setting a mix track to MON
	
		MON => sub
		{
			my ($bus, $track) = @_;
			$track->set_mon;
		},

	# setting mix track to OFF
	
		OFF => sub
		{
			my ($bus, $track) = @_;

			$track->set_off;

			# with the mix track off, 
			# the member tracks get pruned 
			# from the graph 
		}
	},
	member_track =>
	{

	# setting member track to REC
	
		REC => sub 
		{ 
			my ($bus, $track) = @_;

			$track->set_rec() or return;

			$bus->set(rw => 'MON');
			$tn{$bus->send_id}->busify 
				if $bus->send_type eq 'track' and $tn{$bus->send_id};
			
		},

	# setting member track to MON 
	
		MON => sub
		{ 
			my ($bus, $track) = @_;
			$bus->set(rw => 'MON') if $bus->rw eq 'OFF';
			$track->set_mon;
		},

	# setting member track to PLAY
	
		PLAY => sub
		{ 
			my ($bus, $track) = @_;
			$bus->set(rw => 'MON') if $bus->rw eq 'OFF';
			$track->set_play;

		},
	# setting member track to OFF 

		OFF => sub
		{
			my ($bus, $track) = @_;
			$track->set_off;
		},
	},
);
# for track commands 'rec', 'mon','off' we 
# may toggle rw state of the bus as well
#

sub rw_set {
	logsub("&rw_set");
	my ($bus,$track,$rw) = @_;
	my $type = $track->is_mix_track
		? 'mix_track'
		: 'member_track';
	$bus_logic{$type}{uc $rw}->($bus,$track);
}
}

sub freq { [split ',', $_[0] ]->[2] }  # e.g. s16_le,2,44100

sub channels { [split ',', $_[0] ]->[1] }
	
# these are the names of loop devices corresponding
# to pre- and post-fader nodes of a track signal
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
	if($dest eq undef )			{ undef			}

	# non JACK related

	if($dest eq 'bus')		 	{ 'bus'			}
	elsif($dest eq 'null')	 	{ 'null'		}
	elsif($dest eq 'rtnull')	{ 'rtnull'		}
	elsif($dest =~ /^loop,/)	{ 'loop'		}
	elsif($dest !~ /\D/)		{ 'soundcard'	} # digits only

	# JACK related

	elsif($dest =~ /^man/)		{ 'jack_manual'	}
	elsif($dest eq 'jack')		{ 'jack_manual'	}
	elsif($dest =~  /(^\w+\.)?ports/)	{ 'jack_ports_list' }
	else 						{ 'jack_client'	} 
}
sub dest_string {
	my ($type, $id, $width) = @_;
	if ($type eq 'soundcard'){
		my $ch = $id;
		my @channels;
		push @channels, $_ for $ch .. ($ch + $width - 1);
		join '/', @channels
	}
	else { $id }
}

sub create_dir {
	my @dirs = @_;
	map{ my $dir = $_;
	logpkg('debug',"creating directory [ $dir ]");
		-e $dir 
#and (carp "create_dir: '$dir' already exists, skipping...\n") 
			or system qq( mkdir -p $dir)
		} @dirs;
}

sub join_path {
	
	my @parts = @_;
	my $path = join '/', @parts;
	$path =~ s(/{2,})(/)g;
	$path;
}

sub wav_off {
	my $wav = shift;
	$wav =~ s/\.wav\s*$//i;
	$wav;
}

sub strip_all{ strip_trailing_spaces(strip_blank_lines( strip_comments(@_))) }

sub strip_trailing_spaces {
	map {s/\s+$//} @_;
	@_;
}
sub strip_blank_lines {
	map{ s/\n(\s*\n)+/\n/sg } @_;
	map{ s/^\n+//s } @_;
	@_;
	 
}

sub strip_comments { #  
	map{ s/#.*$//mg; } @_;
	map{ s/\s+$//mg; } @_;

	@_
} 

sub remove_spaces {															 
		my $entry = shift;													  
		# remove leading and trailing spaces									
																				
		$entry =~ s/^\s*//;													 
		$entry =~ s/\s*$//;													 
																				
		# convert other spaces to underscores								   
																				
		$entry =~ s/\s+/_/g;													
		$entry;																 
}																			   
sub resolve_path {
	my $path = shift;
	$path = expand_tilde($path);
	$path = File::Spec::Link->resolve_all($path);
}
sub expand_tilde { 
	my $path = shift; 

 	my $home = File::HomeDir->my_home;


	# ~bob -> /home/bob
	$path =~ s(
		^ 		# beginning of line
		~ 		# tilde
		(\w+) 	# username
	)
	(File::HomeDir->users_home($1))ex;

	# ~/something -> /home/bob/something
	$path =~ s( 
		^		# beginning of line
		~		# tilde
		/		# slash
	)
	($home/)x;
	$path
}
sub dumper { 
	! defined $_ and "undef"
	or ! (ref $_) and $_ 
	#or (ref $_) =~ /HASH|ARRAY/ and ::json_out($_)
	or ref $_ and Dumper($_)
}

1;
__END__

