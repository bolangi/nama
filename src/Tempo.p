# contains Tempo::Chunk, Tempo::Bar, Tempo::Beat, Tempo::Tick 
# routines for reading tempo map are in the root namespace
{
package ::Tempo::Chunk;
use v5.36;
our $VERSION = 1.0;
use ::Globals qw($config);
use ::Object qw( label bars meter tempo tick index);
use List::Util qw(sum);
# we divide time in chunks specified by klick metronome tempo map
# 
# label: name for this tempo section, e.g. Tempo object, e.g. chunk
# bars: measures in this chunk
# meter: time signature e.g 3/4 count/note, note is 4, count is 3
# tempo: bpm or range
# ticks: number of ticks in this chunk
# note: denominator of time signature, e.g. 4 means quarter note, 8 means eighth
# count: numerator of time signature

#no warnings 'redefine';


our $index = 0;
our @chunks;
our @beats;
our @bars;
sub chunks { @chunks }

sub locate_bar ($bar_index) { 
	my $relative_bar = $bar_index;
	my $in;
	for my $chunk (@chunks){
		if ($relative_bar  > $chunk->bars) # does not appear during this chunk
			{ $relative_bar -= $chunk->bars }
		else { $in = $chunk; last }
	}	
	$in->bar($relative_bar); 
	
}
sub new ($class, %args) {
		$args{meter} //= '4/4';
		$args{index} = $index++;
		my $self = bless \%args, $class;
		push @chunks, $self;
}
sub my_length ($self) {
	$self->bars * $self->count * $self->note_length;
}
sub previous ($self) {
	$self->index > 0 and $chunks[$self->index - 1] 
}

sub start_pos ($self) {
	$self->previous ? $self->previous->end_pos : 0;
}
sub end_pos ($self) {
	$self->start_pos + $self->my_length
}


sub bar ($self, $bar_index) {
	::Tempo::Bar->new( chunk => $self,
						index => $bar_index);
}


sub note ($self) {  # denominator, 4, in 2/4
	my ($note) = $self->{meter} =~ m| / (\d+) |x;
	$note;
}
sub count ($self) { # numerator, 2, in 2/4
	my ($count) = $self->{meter} =~ m| (\d+) / |x;
	$count;
}
sub beats ($self) {
	$self->bars * $self->count
}
sub ticks ($self) { 
	$self->quarter_notes * $config->{ticks_per_quarter_note}
}
sub quarter_notes ($self) {
	$self->beats * $self->note_fraction
}
sub note_fraction ($self) {
	4 / $self->note;
}

sub note_length ($self){
	if ( $self->fixed_tempo ){
		my $beat_length = 60 / $self->tempo;
		my $seconds_per_note =  $beat_length * $self->note_fraction;
	}	
}
=comment
	else {
		my $nl_start = note_length($self->start_tempo, $self->note_fraction);
		my $nl_end   = note_length($self->end_tempo,   $self->note_fraction);
		my $delta = ($nl_end - $nl_start) / $self->notes;
		for my $incr (0 .. $self->notes - 1){
			push @note_lengths, ($nl_start + $incr * $delta);
		}
	}
=cut;

sub ratio {
	my ($start_bpm, $end_bpm, $beats) = @_;
	my $ratio = exp( log(bpm_to_length($end_bpm) / bpm_to_length($start_bpm)) / $beats );

}

sub bpm_to_length {
	my $bpm = shift;
	60 / $bpm 
}

sub note_position_during_tempo_ramp {

=comment
	my ($start_bpm, $end_bpm, $beats, $nth) = @_;

	# start_tempo: beats per minute
	# end_tempo: beats per minute
	# nth: beat whose position we want
	# beats: total beats in ramp interval

	return 0 if $nth == 1;
	::throw("$nth: zero or missing nth beat"), return if ! $nth;

	# To determine the start of a beat we accumlate
	# time through the end of the previous beat.

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

=cut
}

sub quarter_length {
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
}

{
package ::Tempo::Bar;
use v5.36;
use ::Object qw(chunk index);

sub new ($class, %args) {
	bless \%args, $class
}
sub start_pos ($self)
{
	$self->chunk->start_pos + ($self->index - 1) * $self->chunk->count * $self->chunk->note_length
}
sub end_pos ($self)
{
	$self->start_pos + $self->chunk->count * $self->chunk->note_length
}
sub beat ($self, $beat_index) {
	::Tempo::Beat->new( bar => $self,
						index => $beat_index);
}
}


{
package ::Tempo::Beat;
use v5.36;
use ::Object qw(bar index);

sub new ($class, %args) {
	bless \%args, $class
}
sub end_pos ($self) {
	my $bar = $self->bar;
	my $chunk = $self->bar->chunk;
	if ( $chunk->fixed_tempo ){
		$bar->start_pos + $self->index * $chunk->note_length;
	}
	else { die "no support for tempo ramp" }

}
sub start_pos ($self) {
	my $bar = $self->bar;
	my $chunk = $self->bar->chunk;
	if ( $chunk->fixed_tempo ){
		$bar->start_pos + ($self->index - 1) * $chunk->note_length;
	}
	else { die "no support for tempo ramp" }

}
sub tick ($self, $tick_index) {
	::Tempo::Tick->new( beat => $self, index => $tick_index)
}
	

}

{
package ::Tempo::Tick;
use v5.36;
use ::Object qw(beat index);

sub new ($class, %args) {
	bless \%args, $class
}
sub end_pos ($self) {
	my $beat = $self->beat;
	my $chunk = $beat->bar->chunk;
	if ( $chunk->fixed_tempo ){
		$beat->start_pos + $self->index * $chunk->note_length / 24;
	}
	else { die "no support for tempo ramp" }

}
sub start_pos ($self) {
	my $beat = $self->beat;
	my $bar = $beat->bar;
	my $chunk = $bar->chunk;
	if ( $chunk->fixed_tempo ){
		$beat->start_pos + ($self->index - 1) * $chunk->note_length/ 24;
	}
	else { die "no support for tempo ramp" }

}
}

package ::;
use v5.36;
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

sub change_in_tempo_map{ $config->{use_git} and git_diff($file->tempo_map) }

sub import_tempo_map {
		my $is_update = shift;
		local $this_track = metronome_track();

		# don't process if metronome track contains audio
		# unless we specifically request it

		return if $this_track->version and not $is_update;

		initialize_tempo_map();
		read_tempo_map($file->tempo_map);
		mark_song_sections();
		render_metronome_track();
}

sub metronome_track {
	my $m = 'metronome';
	if ($tn{$m}){ $tn{$m} } else { add_track($m) }
}

sub initialize_tempo_map { 
	@::Tempo::Chunk::chunks = ();
	remove_section_marks();
}
sub remove_section_marks { for( ::Mark::all() ){ $_->remove if $_->type eq 'song' } }

sub read_tempo_map {
	my $file = shift;
	return unless -e $file;
	my @lines = grep{ ! /^\s*$/ } ::strip_comments(read_file($file));
	parse_tempo_map( @lines );
}
sub parse_tempo_map {
	my @lines = @_;
	for ( @lines )
	{
		no warnings 'uninitialized';
		chomp; 
		# say	;
		/^\s* $label? \s+ $bars \s+ ($meter \s+)? $chunks/x;
		#say "label: $+{label} bars: $+{bars} meter: $+{meter} tempo: $+{tempo}";
		my %chunk;
		@chunk{ @fields } = @+{ @fields };
		::Tempo::Chunk->new(%chunk);
		# make real mark$tempo_mark{$chunk->label} = $chunk if $chunk->label;
	}
}

sub mark_song_sections {
	for my $chunk (@::Tempo::Chunk::chunks) {
		$chunk->label and drop_mark( name => $chunk->label, time => $chunk->start_pos, type => 'song' );
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
	my( $bar_index, $beat_index, $tick_index) = @_;
	my ($bar) = ::Tempo::Chunk::locate_bar($bar_index);
	return $bar->start_pos unless $beat_index; 
	my $beat = $bar->beat($beat_index);
	return $beat->start_pos unless $tick_index;
	my $tick = $beat->tick($tick_index);
	return $tick->start_pos;
}
sub arm_metronome {
	::throw(  q(tempo map ") . $file->tempo_map . q(" not found, skipping) ), return if not -e $file->tempo_map;
	try { system('killall','klick') };
	my $cmd = 'klick -t -f '. $file->tempo_map . '&';
	system $cmd;
	::pager("metronome is armed");
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
