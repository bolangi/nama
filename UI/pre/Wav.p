package ::Wav;
use Object::Tiny qw(name active dir);
use warnings;
#no warnings qw(uninitialized);
our @ISA; # no ancestors
use Carp;

sub get_versions {
	my $wav = shift;
	my $basename = $wav->name;
	my $dir = $wav->dir;
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
		$debug and print "match: $1,  num: $3\n\n";
		$versions{ $3 ? $3 : 'bare' } =  $1 ;
	}
	$debug and print "get_version: " , yaml_out(\%versions);
	closedir WD;
	%versions;
}

sub targets {# takes a Wav object or basename
	local $debug = 1;
	my $wav = shift; 
 	#my $name=  ref $wav ? $wav->name: $wav;
 	my $name =  $wav->name;
	my $dir = $wav->dir;
	$debug2 and print "&targets\n";
	local $debug = 0;
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
	if (ref $wav){ [ sort { $a <=> $b } keys %{ $wav->targets} ] } 
	else 		 { [ sort { $a <=> $b } keys %{ targets($wav)} ] }
}

sub last { 
	my $wav = shift;
	pop @{ $wav->versions} }


=comment

# not the responsibility of Wav
sub monitor_version {}
sub selected_version {
	# return track-specific version if selected,
	# otherwise return global version selection
	# but only if this version exists
	my $wav = shift;
	$wav->active 
		? $wav->active  				# my own setting
		: ${ $wav->targets }->{ $::monitor_version } # group setting if I can
			? ${ $wav->targets }->{ $::monitor_version } 
			: $wav->last;                          # my latest version
	### or should I give the active version
}
=cut
=comment
sub last_version { 
	## for each track or tracks in take

$track->last_version;
$take->last_version
$project->last_version
	
			$last_version = $this_last if $this_last > $last_version ;

}

sub new_version {
	last_version() + 1;
}
=cut

=comment
my $wav = Wav->new( name => vocal);

$wav->versions;
$wav->name # vocal
$wav->n     # 3 i.e. track 3
$wav->active
$wav->targets
$wav->full_path

returns numbers

$wav->targets

returns targets

=cut

