package ::Wav;
our $VERSION = 1.0;
our @ISA; 
use ::Object qw(name version dir);
use warnings;
use ::Assign qw(:all);
use ::Util qw(join_path);
use ::Log qw(logsub logpkg);
use Memoize qw(memoize unmemoize); # called by code in ::Memoize.pm
no warnings qw(uninitialized);
use Carp;

sub get_versions {
	my $self = shift;
	my ($sep, $ext) = qw( _ wav );
	my ($dir, $basename) = ($self->dir, $self->basename);
#	print "dir: ", $self->dir(), $/;
	#print "basename: ", $self->basename(), $/;
	logpkg('debug',"getver: dir $dir basename $basename sep $sep ext $ext");
	my %versions = ();
	for my $candidate ( candidates($dir) ) {
	#	logpkg('debug',"candidate: $candidate");
	
		my( $match, $dummy, $num) = 
			( $candidate =~ m/^ ( $basename 
			   ($sep (\d+))? 
			   \.$ext ) 
			  $/x
			  ); # regex statement
		if ( $match ) { $versions{ $num || 'bare' } =  $match }
	}
	logpkg('debug',sub{"get_version: " , ::json_out(\%versions)});
	%versions;
}

sub candidates {
	my $dir = shift;
	$dir =  File::Spec::Link->resolve_all( $dir );
	opendir my $wavdir, $dir or die "cannot open $dir: $!";
	my @candidates = readdir $wavdir;
	closedir $wavdir;
	@candidates = grep{ ! (-s join_path($dir, $_) == 44 ) } @candidates;
	#logpkg('debug',join $/, @candidates);
	@candidates;
}

sub targets {
	
	my $self = shift; 

#	$::debug2 and print "&targets\n";
	
		my %versions =  $self->get_versions;
		if ($versions{bare}) {  $versions{1} = $versions{bare}; 
			delete $versions{bare};
		}
	logpkg('debug',sub{"\%versions\n================\n", json_out(\%versions)});
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

1;
