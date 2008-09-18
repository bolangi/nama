package ::Wav;
our $VERSION = 1.0;
our @ISA; 
use ::Object qw(name active dir);
use warnings;
use ::Assign qw(:all);
no warnings qw(uninitialized);
use Carp;

sub get_versions {
	my $wav = shift; # Expects a Track object here
	my $basename = $wav->name;
	my $dir = ::this_wav_dir();
	$debug and print "this_wav_dir: $dir\n";
	$debug and print '$wav->dir', $wav->dir; # indirectly this_wav_dir
	my ($sep, $ext) = qw( _ wav );

	$debug and print "getver: dir $dir basename $basename sep $sep ext $ext\n\n";
	opendir WD, $dir or carp ("can't read directory $dir: $!");
	$debug and print "reading directory: $dir\n\n";
	my %versions = ();
	for my $candidate ( readdir WD ) {
		$debug and print "candidate: $candidate\n\n";
		$candidate =~ m/^ ( $basename 
		   ($sep (\d+))? 
		   \.$ext )
		   $/x or next;
		next if -s join_path($dir, $candidate) == 44;
		$debug and print "match: $1,  num: $3\n\n";
		$versions{ $3 ? $3 : 'bare' } =  $1 ;
	}
	$debug and print "get_version: " , ::yaml_out(\%versions);
	closedir WD;
	%versions;
}

sub targets {# takes a Wav object 
	
	my $wav = shift; 
 	#my $name=  ref $wav ? $wav->name: $wav;
 	my $name =  $wav->name;
	my $dir = $wav->dir;
	$debug2 and print "&targets\n";
	
	$debug and print "this_wav_dir: $dir, name: $name\n";
		my %versions =  $wav->get_versions;
		if ($versions{bare}) {  $versions{1} = $versions{bare}; 
			delete $versions{bare};
		}
	$debug and print "\%versions\n================\n", yaml_out(\%versions);
	\%versions;
}
sub versions {  # takes a Wav object or a string (filename)
	my $wav = shift;
	[ sort { $a <=> $b } keys %{ $wav->targets} ]  
}

sub last { 
	my $wav = shift;
	pop @{ $wav->versions} }

