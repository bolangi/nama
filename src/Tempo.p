#----- Tempo.pm ------
# support for beats and bars

package ::Tempo;
use Modern::Perl;
use ::Globals qw($config);
use ::Object qw( note count label bars meter tempo );
use List::Util qw(sum);
# we divide time in chunks specified by klick metronome tempo map
# 
# note: denominator of time signature, e.g. 4 means quarter note, 8 means eighth
# count: numerator of time signature
# bars: measures in this chunk
# meter: time signature e.g 3/4 count/note, note is 4, count is 3
# tempo: bpm or range
# ticks: default 24 ticks equals one quarter note

no warnings 'redefine';

our @chunks;
our @beats;
our @bars;

sub note {
	my $self = shift;
	my ($note) = $self->{meter} =~ m| / (\d+) |x;
	$note;
}
sub count {
	my $self = shift;
	my ($count) = $self->{meter} =~ m| (\d+) / |x;
	$count;
}
sub beats {
	my $self = shift;
	$self->bars * $self->count
}
sub ticks { 
	my $self = shift;
	$self->quarter_notes * $config->{ticks_per_quarter_note}
}
sub quarter_notes {
	my $self = shift;
	$self->beats * $self->note_fraction
}
sub beat_lengths {
	my $self = shift;
	my @beat_lengths;
	if ( $self->fixed_tempo ){
		my $bps = $self->tempo / 60;
		my $seconds_per_beat = 1 / $bps * $self->note_fraction;
		for (1..$self->beats){ push @beat_lengths, $seconds_per_beat }
	}	
	else {
		# r = exp [ ln( t final / t initial )  / n ]
		my $ratio = ratio( $self->start_tempo, $self->end_tempo, $self->beats - 1 );
		my $current_length = quarter_length_from_bpm($self->start_tempo) * $self->note_fraction;
		push @beat_lengths, $current_length;
		for (2 .. $self->beats - 1){
			$current_length *= $ratio;
			push @beat_lengths, $current_length;
		}
		push @beat_lengths, quarter_length_from_bpm($self->end_tempo);
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
	my ($start_bpm, $end_bpm, $beats) = @_;
	my $ratio = exp( log(bpm_to_length($end_bpm) / bpm_to_length($start_bpm)) / $beats );

	# To calculate the factor for multiplying by beat length of note n 
	# to get beat length of note n+1
	#
	# t final / t initial = r^n
	#
	# where
	# t final is the final beat interval
	# t initial is the initial beat interval
	# r is the ratio
	# n is the number of beats for the transition
	#
	# Taking the natural logarithm of both sides,
	#
	# ln( t final / t initial ) = n ln r
	#
	# Hence
	#
	# r = exp [ ln( t final / t initial )  / n ]

}

sub bpm_to_length {
	my $bpm = shift;
	60 / $bpm 
}

sub constant_rate_ramp_position_mth_of_n {
	my ($start_bpm, $end_bpm, $n, $m ) = @_;
	my $ratio = ratio($start_bpm, $end_bpm, $n);
	my $total = 0;
	my $current_length = bpm_to_length($start_bpm);
	$total += $current_length; # first note
	for (2..$m-1){
		$current_length *= $ratio;
		$total += $current_length;
	}
	$total
}
sub linear_ramp_position_mth_of_n {

	my ($start_bpm, $end_bpm, $n, $m) = @_;

	# start_tempo: notes per minute
	# end_tempo: notes per minute
	# n: notes in ramp interval
	# m: ordinal whose position we want

	# this algorithm calculates the position of the
	# *end* of the mth note. To get the starting pos
	# we decrement m

	$m--;

	# we will change time by a constant delta
	# delta = total change / number of steps (n)

	# increment first note length by 0 delta
	# increment second note by 1 delta
	# increment (nth) note by (n-1) delta
	
	# we only increment (no. of steps - 1) times, since the measure
	# following the ramp will presumably continue with the tempo
	# at ramp end. 

	# example: For 4 measures of 4/4, the delta is total change in beat length/16, 
	# we then increment length of subsequent beats from beat 2 to beat 16 by
	# delta. The first note of the next measure will be at the intended tempo

	my $t1 = bpm_to_length($start_bpm);
	my $tn = bpm_to_length($end_bpm);

	my $pos = $m * ($t1 + ($tn - $t1) / $n * ($m - 1) / 2);
    
	# Consider this ramp. The initial time interval 
    # 
    # t0  = 60 s / 100 bpm = 0.6 s.  
    # 
    # The final time interval after 16 beats is 
    # 
    # t16 = 60 s / 120 bpm = 0.5 s.
    # 
    # There are two ways I can think of for the time interval between beats to
    # change.  One is when the time interval changes linearly with the number of
    # beats; the other is that the time interval changes by a constant ratio with
    # each beat.
    # 
    # Let's consider the linear change first.  For your case, the time change
    # with each beat delta ("d") is given by
    # 
    # d = (tn - t1) / n  Where n is the number of notes in the chunk
    # 
    # The time Tm when the mth note ends is
    # Tm =  t1 + ...+ tm
    #     = t1 + (t1 + d) + (t1 + 2 d) + ,,, (t0 + (m-1)d )
    #     = m t1  +  (1 + ... m - 1) d
    # 
    # There are m - 1 terms in the sum (1 + 2 + ... m - 1), and
    # the average term is  (m / 2)  
    # 
    # sum = (m - 1)(m / 2)
    # 
    # Plugging into T,
    # 
    # Tm = m t1 +  d (m-1) m / 2
    # 
    # substitute d to get
    # 
    # Tm = m t1 +  (tn - t1) / n * (m - 1) * m  / 2
    # Tm = m (t1 + (tn - t1) / n * (m - 1) / 2 )

}

sub quarter_length_from_bpm {
	my $bpm = shift;
	my $bps = $bpm / 60;
	my $seconds_per_beat = 1 / $bps
}
sub fixed_tempo {
	my $self = shift;
	$self->{tempo} !~ /-/;	
}
sub start_tempo {
	my $self = shift;
	my ($start_bpm) = $self->fixed_tempo ? $self->tempo
										   : $self->tempo =~ / (\d+) - /x;
}
sub end_tempo {
	my $self = shift;
	my ($end_bpm) = $self->fixed_tempo ? $self->tempo
										 : $self->tempo =~ / - (\d+) /x;
}

sub note_fraction {
	my $self = shift;
	4 / $self->note;
}

	
sub notation_to_time {
	my $self = shift;
	my ($bars, $beats, $ticks) = @_;
	$beats-- unless ! $beats; # first beat is time zero
	$bars--  unless ! $bars;  # first bar is time zero;
	$ticks-- unless ! $ticks; # first tick is time zero;
	my $position_in_ticks = ($bars * $self->count + $beats) * $self->note_fraction * $config->{ticks_per_quarter_note} + $ticks;

	$self->fixed_tempo ? bpm_to_length($self->tempo) * $self->note_fraction / $config->{ticks_per_quarter_note}  * $position_in_ticks
					   : linear_ramp_position_mth_of_n ( $self->start_tempo, $self->end_tempo, $self->ticks, $position_in_ticks )
	

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
		
	if ( -e $file->tempo_map or git( 'ls-files' => $file->tempo_map)){
			
			# case 1 - tempo map appears
			if (not git( 'ls-files' => $file->tempo_map)){
				my $msg = 'tempo map created';
				git( add => $file->tempo_map);
				git( commit => '--quiet', '--message', $msg, $file->tempo_map);
				process_tempo_map();
				render_metronome_track();
			}
			# case 2 - change in tempo map
			elsif (git( diff => $file->tempo_map ) ){
				if (-e $file->tempo_map ){
					my $msg = 'change in tempo map';
					git( commit => '--quiet', '--message', $msg, $file->tempo_map);
					process_tempo_map();
					render_metronome_track();
				} else { 
					my $msg = 'delete tempo map';
					::pager('tempo map has been deleted, turning of metronome track');
					$this_track = metronome_track()->set( rw => OFF );
					git( commit => '--quiet', '--message', $msg, $file->tempo_map);
					initialize_tempo_map();
				};
			}
		}
			
}

sub process_tempo_map {
	local $this_track = metronome_track();
	-e $file->tempo_map or return;
	initialize_tempo_map();
	read_tempo_map($file->tempo_map);
	create_marks_and_beat_index();
}
sub metronome_track {
	my $m = 'metronome';
	if ($tn{$m}){ $tn{$m} } else { add_track($m) }
}

sub initialize_tempo_map { 
	@chunks = @bars = @beats = ();	
	delete_tempo_marks();
}
sub delete_tempo_marks { for( ::Mark::all() ){ $_->remove if $_->tempo_map } }

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
		::Mark->new(name => $chunk->label, time => $chunk->start_time, tempo_map => 1);
	}
}

sub render_metronome_track {
	throw qq(metronome program not found, please install "klick"), return if not `which klick`;
	local $this_track = metronome_track();
	
	$this_track->set(rw => REC);
	my $output = $this_track->full_path;
	my $map = $file->tempo_map;
	my $rate = $project->{sample_rate};
	my $cmd = "klick -f $map -r $rate -W $output";
	::pager("executing: $cmd");
	system($cmd); 
	$this_track->set(rw => PLAY);
	refresh_wav_cache();
}

sub notation_to_time {
	my( $bars, $beats, $ticks) = @_;
	my $time = 0;
	my $in;
	for (@chunks){
		if ($bars > $_->bars) # does not appear during this chunk
			{ $bars -= $_->bars }
		else { $in = $_, last }
	}	
	$time += $in->start_time;
	$time += $in->notation_to_time($bars,$beats, $ticks)
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
