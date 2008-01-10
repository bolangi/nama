use Test::More qw(no_plan);
use strict;

## Grab at anything nearby

use lib qw(.. . lib lib/UI);


#use UI::Wav;
#use UI::Assign qw(:all);
# `make test'. After `make install' it should work as `perl 1.t'

BEGIN { 
	diag ("TESTING $0\n");
	use_ok('UI::Wav') ;
}
my $wav = UI::Wav->new( qw(	name  	track01.cdda 
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


