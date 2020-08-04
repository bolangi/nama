#----- Tempo.pm ------
# support for beats and bars

package ::;
use Modern::Perl;
use Data::Dumper::Concise;
use ::Log qw(logsub logpkg);
use ::Util qw(strip_comments);
use File::Slurp;

our @tempo;
my $label = qr| (?<label> [-_\d\w]+) :       |x;
my $bars  = qr| (?<bars>  \d+      )         |x;
my $meter = qr| (?<meter> \d / \d  )         |x;
my $tempo = qr| (?<tempo> \d+ ( - \d+)? )    |x;

sub read_tempo_map {
	my $file = shift;
	my @lines = read_file($file);
	for ( @lines )
	{
		chomp; say	;
		/^\s* $label? \s+ $bars \s+ ($meter \s+)? $tempo/x;
		say "label: $+{label} bars: $+{bars} meter: $+{meter} tempo: $+{tempo}";
		my %chunk;
		@chunk{ qw( label bars meter tempo ) } = @+{ qw( label bars meter tempo ) };
		say Dumper \%chunk;
		push @tempo, \%chunk;
			
	}
}
1
__END__

#  [label:] bars [meter] tempo [pattern] [volume]

#my $fixed_tempo = qr| 

Tn = n t0 +  [ (tn - t0) / n ] n (n + 1) / 2                                                                                                                           
    = n t0  +  (tn - t0) (n + 1) / 2                                                                                                                                   
    = t0 (n - n/2 - 1/2)  +  tn (n + 1) / 2                                                                                                                            
                                                                                                                                                                       
*    = t0 (n - 1) / 2  +  tn (n + 1) / 2*


export 
#

iinterface

$tempo->pos('chorus2')
$tempo->pos(4,3)
$tempo->pos(4)

bar_pos('chorus2')

my $pos = is_bar_pos(@args) # 'chorus2' '4 1'

my $barpos = is_bar_pos(@args);
$pos = $pos ? $pos : markpos(@args)

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
