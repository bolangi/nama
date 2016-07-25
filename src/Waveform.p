{package ::Waveform;
use Role::Tiny;
use Modern::Perl;
use ::Globals qw(:all);
use ::Util qw(join_path);
use autodie qw(:all);

sub generate_waveforms {
	my ($track, $version) = @_;
	my $sourcefile = join_path(::this_wav_dir(), $track->targets->{$version});
	my $datafile = time_series_filename($track->name, $version);
	initial_time_series($sourcefile, $datafile);
	my $p1 = time_series_filename($track->name, $version, 1);
	say "p1: $p1";
	first_series($datafile, $p1, $config->{sample_rate});
	my $previous_file = $p1;
	for my $power (2..8)
	{
		my $datafile = time_series_filename($track->name, $version, $power);
		my $factor = 10; 
		my $unit = 'seconds';
		rms_series($previous_file, $datafile, $factor, $unit);
		$previous_file = $datafile;
	}
}

sub time_series_filename {
	my ($trackname, $version, $power) = @_;
	my $filename = ! $power 
		? "${trackname}_$version.dat"
		: "${trackname}_$version#$power.dat";
	join_path(::waveform_dir(),$filename)
}
	
sub initial_time_series {
	my ($from, $to) = @_;
	my @cmd = ('tsriff', $from, $to);
	my $cmd = join " ", @cmd;
	say "ts-command: $cmd";
	system(@cmd) == 0 or die "system @cmd failed: $?";
 	#guitar_2.wav guitar_2.dat 
}
	
sub first_series {
	my ($from, $to, $sample_rate) = @_;
	open my $rh, '<', $from;
	open my $wh, '>', $to;
	my $i = 0;
	while (my $line = <$rh>)
	{
		$line =~ /(\d+)/ and say $wh ++$i/$sample_rate, " $1";
		# take first channel, throw away the rest
		# output:  seconds   level 
	}
}
sub rms_series {
	my($from, $to, $factor, $unit) = @_;
	open my $in_h, '<', $from;
	open my $out_h, '>', $to;
	my ($pos, $acc, $count, $level);
	while (! eof $in_h)
	{
		for (1..$factor)
		{	$count = $acc = 0; 
			my $entry = <$in_h>;
			defined $entry or last;
			($pos, $level, undef) = split ' ', $entry;
			$count++;
			$acc += $level**2;
		}
		my $rms = sqrt($acc/$count);
		say $out_h "$pos -$rms $rms";
	}
}
# 	rms for $factor values
#     write outfile (time (s/min), rms )
sub generate_plot {
# 	my ($file, %params) = @_
# 	outfile guitar_2#2.png
# 	gnuplot(@params)
} 

}
1
__END__


=comment
# track guitar.wav version 2
# screen width e.g. 800
# try for 2 hours max on screen
# 800 dots / 125 minutes =  6.4 dots/min
# 2400 dots / 120 minute = 20 dots/ min
# 1600 dots / 120 minute = 13.3 dots/min
 or 1 dot / 33 million samples

# 

scale down factor | resolution
1 					48000 dots per second
10 					4800  dots / sec
100  				480 dots / sec
1_000 				48 dots / sec
10_000 				4.8 dots/sec
100_000  			288 dots/min
1_000_000 			28.8 dots/min
10_000_000 			2.9 dots/min




my %dispatch = (
	1 => 
	2 =>
	3 =>
	4 =>
	5 =>
	6 =>
	7 =>
	8 =>
);

    
                     guitar_2.dat   # initial_time_series
                     guitar_2#1.dat  # first_series
                     guitar_2#2.dat # rms_series
                     guitar_2#3.dat  
                     guitar_2#4.dat  
                     guitar_2#5.dat  
                     guitar_2#6.dat  
                     guitar_2#7.dat  
=cut
