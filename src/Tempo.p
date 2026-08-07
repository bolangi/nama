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
	$self->time_at_note_position($self->beats);
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
	$self->note_length_at(0);
}

# Klick ramps BPM linearly over musical position.  Integrating reciprocal
# tempo gives elapsed time; allowing a fractional note position extends the
# same curve to Nama's ticks while preserving Klick's beat boundaries.
sub time_at_note_position ($self, $position) {
	return 0 if $position == 0;

	my $start = $self->start_tempo;
	if ($self->fixed_tempo) {
		return $position * 240 / ($self->note * $start);
	}

	my $change = $self->end_tempo - $start;
	my $tempo_at_position = $start
		+ $change * $position / $self->beats;

	240 * $self->beats
		/ ($self->note * $change)
		* log($tempo_at_position / $start);
}

sub time_after_notes ($self, $notes) {
	$self->time_at_note_position($notes);
}

sub time_after_ticks ($self, $ticks) {
	$self->time_at_note_position($ticks / $self->ticks_per_note);
}

sub note_length_at ($self, $note_index) {
	$self->time_at_note_position($note_index + 1)
		- $self->time_at_note_position($note_index);
}

sub tick_length_at ($self, $tick_index) {
	$self->time_after_ticks($tick_index + 1)
		- $self->time_after_ticks($tick_index);
}
sub fixed_tempo {
	my $self = shift;
	$self->{tempo} !~ /-/;	
}
sub start_tempo {
	my $self = shift;
	return $self->tempo if $self->fixed_tempo;
	my ($start_bpm) = $self->tempo =~ / (\d+) - /x;
	$start_bpm;
}
sub end_tempo {
	my $self = shift;
	return $self->tempo if $self->fixed_tempo;
	my ($end_bpm) = $self->tempo =~ / - (\d+) /x;
	$end_bpm;
}
sub ticks_per_note ($self) {
	$config->{ticks_per_quarter_note} * $self->note_fraction;
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
	my $chunk = $self->chunk;
	my $notes = ($self->index - 1) * $chunk->count;
	$chunk->start_pos + $chunk->time_after_notes($notes);
}
sub end_pos ($self)
{
	my $chunk = $self->chunk;
	my $notes = $self->index * $chunk->count;
	$chunk->start_pos + $chunk->time_after_notes($notes);
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
	my $notes = ($bar->index - 1) * $chunk->count + $self->index;
	$chunk->start_pos + $chunk->time_after_notes($notes);
}
sub start_pos ($self) {
	my $bar = $self->bar;
	my $chunk = $self->bar->chunk;
	my $notes = ($bar->index - 1) * $chunk->count + $self->index - 1;
	$chunk->start_pos + $chunk->time_after_notes($notes);
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
	my $note_index = ($beat->bar->index - 1) * $chunk->count
	               + $beat->index - 1;
	my $ticks = $note_index * $chunk->ticks_per_note + $self->index;
	$chunk->start_pos + $chunk->time_after_ticks($ticks);
}
sub start_pos ($self) {
	my $beat = $self->beat;
	my $bar = $beat->bar;
	my $chunk = $bar->chunk;
	my $note_index = ($bar->index - 1) * $chunk->count
	               + $beat->index - 1;
	my $ticks = $note_index * $chunk->ticks_per_note + $self->index - 1;
	$chunk->start_pos + $chunk->time_after_ticks($ticks);
}
}

package ::;
use v5.36;
use Data::Dumper::Concise;
use ::Log qw(logsub logpkg);
use ::Util qw(strip_comments);
use Path::Tiny qw(path);
use List::Util qw(sum);
use autodie qw(:all);

my $label = qr| (?<label> [-_\d\w]+) :       |x;
my $bars  = qr| (?<bars>  \d+      )         |x;
my $meter = qr| (?<meter> \d+ / \d+)         |x;
my $chunks = qr| (?<tempo> \d+ ( - \d+)? )    |x;

my @fields = qw( label bars meter tempo );

sub change_in_tempo_map{ $config->{use_git} and git_diff($file->tempo_map) }

sub import_tempo_map {
		my $is_update = shift;
		return unless -e $file->tempo_map;

		local $this_track = metronome_track(); # creating it if not present
		
		initialize_tempo_map();
		read_tempo_map($file->tempo_map);
		mark_song_sections();

		render_metronome_track() if $is_update or not scalar $this_track->versions->@* ;
}

sub metronome_track {
	my $m = 'metronome';
	if ($tn{$m}){ $tn{$m} } else { add_track($m, rw => OFF) }
}

sub initialize_tempo_map { 
	@::Tempo::Chunk::chunks = ();
	$::Tempo::Chunk::index = 0;
	remove_section_marks();
}
sub remove_section_marks { 
	for( ::Mark::all() ) { 
 		 $_->remove if defined $_ 
					and defined $_->type 
					and $_->type eq 'song'
	}
}

sub read_tempo_map {
	my $file = shift;
	return unless -e $file;
	my @lines = grep{ ! /^\s*$/ } strip_comments(path($file)->lines_utf8);
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
	pager("executing: $cmd");
	my $ret = 
 	try   { system($cmd) } 
	catch { throw("caught error: $_"); "failed" };

	$this_track->set(rw => $ret ? OFF : PLAY);
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

sub note_duration ($count, $note) {
	::throw(  q(tempo map ") . $file->tempo_map . q(" not found, cannot enter note duration") ), return if not -e $file->tempo_map;
	my $top = $::Tempo::Chunk::chunks[0];
	my $quarter = 60 / $top->tempo; 
	my $length = $quarter * $count * ( 4 / $note );
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
