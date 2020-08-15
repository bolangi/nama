#----- Tempo.pm ------
# support for beats and bars

package ::Tempo;
use Modern::Perl;
use ::Object qw( note count label bars meter tempo );
use List::Util qw(sum);
# we divide time in chunks specified by klick metronome tempo map
# 
# note: denominator of time signature
# count: numerator of time signature
# bars: measures in this chunk
# meter: time signature e.g 3/4
# tempo: bpm or range

no warnings 'redefine';

our @chunks;
our @beats;
our @bars;

sub note {
	my $self = shift;
	my ($note) = $self->{meter} =~ m| / (\d+) |x;
}
sub count {
	my $self = shift;
	my ($count) = $self->{meter} =~ m| (\d+) / |x;
}
sub beats {
	my $self = shift;
	$self->bars * $self->count
}
sub beat_lengths {
	my $self = shift;
	my @beat_lengths;
	if ( $self->fixed_tempo ){
		my $bps = $self->tempo / 60;
		my $seconds_per_beat = 1 / $bps;
		for (1..$self->beats){ push @beat_lengths, $seconds_per_beat }
	}	
	else {
		# r = exp [ ln( t final / t initial )  / n ]
		my $ratio = ratio( $self->start_tempo, $self->end_tempo, $self->beats - 1 );
		my $current_length = beat_length_from_bpm($self->start_tempo);
		push @beat_lengths, $current_length;
		for (2 .. $self->beats - 1){
			$current_length *= $ratio;
			push @beat_lengths, $current_length;
		}
		push @beat_lengths, beat_length_from_bpm($self->end_tempo);
	}
	@beat_lengths
}
sub bar_lengths {
	my $self = shift;
	my @beats = $self->beat_lengths;
	my @bars;
	while (scalar @beats){
		push @bars, sum splice @beats, 0, $self->count; 
	}
	@bars
}
sub length {
	my $self = shift;
	my $length = sum $self->bar_lengths();
}

sub start_time {
	my $self = shift;
	my $time = 0;
	for (@chunks){
		last if $_ == $self; # exit before final increment
		$time += $_->length;
	}
	$time
}
sub end_time {
	my $self = shift;
	my $time = 0;
	for (@chunks){
		$time += $_->length; # increment before exit
		last if $_ == $self;
	}
	$time
}
sub ratio {
	my ($start_tempo, $end_tempo, $beats) = @_;
	my $ratio = exp( log(beat_length_from_bpm($end_tempo) / beat_length_from_bpm($start_tempo)) / $beats );
}
sub beat_length_from_bpm {
	my $bpm = shift;
	my $bps = $bpm / 60;
	my $seconds_per_beat = 1 / $bps;
}
sub fixed_tempo {
	my $self = shift;
	$self->{tempo} !~ /-/;	
}
sub start_tempo {
	my $self = shift;
	my ($start_tempo) = $self->fixed_tempo ? $self->tempo
										   : $self->tempo =~ / (\d+) - /x;
}
sub end_tempo {
	my $self = shift;
	my ($end_tempo) = $self->fixed_tempo ? $self->tempo
										 : $self->tempo =~ / - (\d+) /x;
}

package ::;
use Modern::Perl;
use Data::Dumper::Concise;
use ::Log qw(logsub logpkg);
use ::Util qw(strip_comments);
use File::Slurp;
use List::Util qw(sum);
use autodie qw(:all);

my $label = qr| (?<label> [-_\d\w]+) :       |x;
my $bars  = qr| (?<bars>  \d+      )         |x;
my $meter = qr| (?<meter> \d / \d  )         |x;
my $chunks = qr| (?<tempo> \d+ ( - \d+)? )    |x;

my @fields = qw( label bars meter tempo );

sub beat {  
	my $nth = shift;
	sum @beats[0..$nth-1]
}
sub bar  {
	my $nth = shift;
	sum @bars[0..$nth-1]
}
sub barbeat { 					# position in time of nth bar, mth beat 
	# advance bars
	# 
}
sub refresh_tempo_map {
		my $force = shift;
		if ($config->{use_git} and git( diff => $file->tempo_map ) || $force ){
			git( add => $file->tempo_map );
  			git( commit => '--quiet', '--message', 'change in tempo map '. $file->tempo_map);
		}
		delete_tempo_marks();
		initialize_tempo_map();
		read_tempo_map($file->tempo_map);
}
sub initialize_tempo_map { @chunks = @bars = @beats = ()  }
sub delete_tempo_marks {

}
sub read_tempo_map {
	my $file = shift;
	return unless -e $file;
	my @lines = grep{ ! /^\s*$/ } ::strip_comments(read_file($file));
	for ( @lines )
	{
		no warnings 'uninitialized';
		chomp; 
		# say	;
		/^\s* $label? \s+ $bars \s+ ($meter \s+)? $chunks/x;
		#say "label: $+{label} bars: $+{bars} meter: $+{meter} tempo: $+{tempo}";
		my %chunk;
		@chunk{ @fields } = @+{ @fields };
		$chunk{meter} //= '4/4';
		my $chunk = bless \%chunk, '::Tempo';
		#say Dumper $chunk;
		push @chunks, $chunk;
		# make real mark$tempo_mark{$chunk->label} = $chunk if $chunk->label;
	}
}

sub create_marks_and_beat_index {
	for my $chunk (@chunks){
		push @bars, $chunk->bar_lengths;
		push @beats, $chunk->beat_lengths;
		::Mark->new(name => $chunk->name, time => $chunk->start_time, tempo_map => 1);
	}
}

sub create_metronome_track {
	my $plugin = 'klick';
	my $m = 'metronome';
	throw qq(metronome program not found, please install "klick"), return if not `which klick`;
	local $this_track;
	
	if ($tn{$m}){ $this_track = $tn{$m} }	
 	else { add_track($m) }
	$this_track->set(rw => REC); # to get correct value for ->current_wav
	
	my $map = $file->tempo_map;
	my $rate = $project->sample_rate;
	my $output = $this_track->current_wav;
	my $cmd = "klick -f $map -r $rate -W $output";
	system($cmd); 

 	@{$setup->{_last_rec_tracks}} = ($this_track);
	rec_cleanup();
}

1
__END__

#  [label:] bars [meter] tempo [pattern] [volume]

parse into array

bars => 8
name => verse1
tempo => 120
tempo => 120-140
pattern => X.x.
volume => 0.5
comment => play 8 measures at 120 bpm (4/4)


intro:    8 120           # play 8 measures at 120 bpm (4/4)                                                                                                           
verse1:   12 120 X.x.     # 12 measures at 120 bpm, playing only the 1st and 3rd beat                                                                                  
          4 120-140 X.x.  # gradually increase tempo to 140 bpm                                                                                                        
chorus1:  16 140                                                                                                                                                       
bridge:   8 3/4 140 0.5   # change to 3/4 time, reduce volume                                                                                                          
          8 3/4 140       # normal volume again                                                                                                                        
verse2:   12 120          # back to 4/4 (implied)                                                                                                                      
chorus2:  16 140          # jump to 140 bpm                                                                                                                            
outro:    6 140                                                                                                                                                        
          2 140-80        # ritardando over the last 2 bars    
