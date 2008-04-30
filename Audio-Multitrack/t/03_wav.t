use Test::More qw(no_plan);
use strict;

BEGIN { 
	diag ("TESTING $0\n");
	use_ok('Audio::Multitrack::Wav') ;
}
my $wav = Audio::Multitrack::Wav->new( qw(	name  	track01.cdda 
							dir   	/media/sessions/test-abc
							)) ;
is ($wav->name, 'track01.cdda', "name assignment");
is ($wav->dir, '/media/sessions/test-abc', "directory assignment");
is (shift @{$wav->versions}, 1, "locating .wav files");
#%{$wav->targets};
1;
__END__

diag("Serializing, storing and recalling data");
is( $foo, 2, "Scalar number assignment");
is( $name, 'John', "Scalar string assignment");
my $sum;
map{ $sum += $_ } @face;
is ($sum, 25, "Array assignment");
is( $dict{fruit}, 'melon', "Hash assignment");
is ($serialized, $expected, "Serialization round trip");


