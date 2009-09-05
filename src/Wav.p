package ::Wav;
our $VERSION = 1.0;
our @ISA; 
use ::Object qw(name active dir);
use warnings;
use ::Assign qw(:all);
use Memoize qw(memoize unmemoize);
no warnings qw(uninitialized);
use Carp;

sub get_versions {
	#local $debug = 1;
	my $self = shift;
	my ($sep, $ext) = qw( _ wav );
	my ($dir, $basename) = ($self->dir, $self->basename);
#	print "dir: ", $self->dir(), $/;
	#print "basename: ", $self->basename(), $/;
	$debug and print "getver: dir $dir basename $basename sep $sep ext $ext\n\n";
	my %versions = ();
	for my $candidate ( candidates($dir) ) {
	#	$debug and print "candidate: $candidate\n\n";
	
		my( $match, $dummy, $num) = 
			( $candidate =~ m/^ ( $basename 
			   ($sep (\d+))? 
			   \.$ext ) 
			  $/x
			  ); # regex statement
		if ( $match ) { $versions{ $num || 'bare' } =  $match }
	}
	$debug and print "get_version: " , ::yaml_out(\%versions);
	%versions;
}

sub candidates {
	my $dir = shift;
	$dir =  File::Spec::Link->resolve_all( $dir );
	opendir my $wavdir, $dir or die "cannot open $dir: $!";
	my @candidates = readdir $wavdir;
	closedir $wavdir;
	@candidates = grep{ ! (-s join_path($dir, $_) == 44 ) } @candidates;
	#$debug and print join $/, @candidates;
	@candidates;
}

sub targets {
	
	my $self = shift; 

#	$::debug2 and print "&targets\n";
	
		my %versions =  $self->get_versions;
		if ($versions{bare}) {  $versions{1} = $versions{bare}; 
			delete $versions{bare};
		}
	$debug and print "\%versions\n================\n", yaml_out(\%versions);
	\%versions;
}

	
sub versions {  
#	$::debug2 and print "&versions\n";
	my $self = shift;
	[ sort { $a <=> $b } keys %{ $self->targets} ]  
}

sub last { 
	my $self = shift;
	pop @{ $self->versions} }

