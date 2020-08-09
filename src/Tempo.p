#----- Tempo.pm ------
# support for beats and bars

package ::;
use Modern::Perl;
use Data::Dumper::Concise;
use ::Log qw(logsub logpkg);
use ::Util qw(strip_comments);
use File::Slurp;

our @chunks;
our @beats;
our @bars;

my $label = qr| (?<label> [-_\d\w]+) :       |x;
my $bars  = qr| (?<bars>  \d+      )         |x;
my $meter = qr| (?<meter> \d / \d  )         |x;
my $chunks = qr| (?<tempo> \d+ ( - \d+)? )    |x;

my @fields = qw( label bars meter tempo );

sub beat { $beats[ $_[0] - 1] }
sub bar  {  $bars[ $_[0] - 1] }
sub barbeat { 
	# advance bars
	# 
}

sub read_tempo_map {
	my $file = shift;
	return unless -e $file;
	my @lines = read_file($file);
	for ( @lines )
	{
		no warnings 'uninitialized';
		chomp; 
		# say	;
		/^\s* $label? \s+ $bars \s+ ($meter \s+)? $chunks/x;
		#say "label: $+{label} bars: $+{bars} meter: $+{meter} tempo: $+{tempo}";
		my %chunk;
		@chunk{ @fields } = @+{ @fields };
		my $chunk = bless \%chunk, '::Tempo';
		#say Dumper $chunk;
		push @chunks, $chunk;
		# make real mark$tempo_mark{$chunk->label} = $chunk if $chunk->label;
	}
}

sub create_marks {
	for my $chunk (@chunks){
	#	index_beats

	}	

}

package ::Tempo;
use Modern::Perl;
use ::Object qw( note count label bars meter tempo );
# we divide time in chunks specified by klick metronome tempo map
# 
# note: denominator of time signature
# count: numerator of time signature
# bars: measures in this chunk
# meter: time signature e.g 3/4
# tempo: bpm or range

no warnings 'redefine';
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
