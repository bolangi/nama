package ::Wav;
our $VERSION = 1.0;
our @ISA; 
use ::Object qw(name version dir);
use warnings;
use ::Assign qw(:all);
use ::Util qw(join_path);
use ::Log qw(logit);
use Memoize qw(memoize unmemoize); # called by code in ::Memoize.pm
no warnings qw(uninitialized);
use Carp;

sub get_versions {
	my $self = shift;
	my ($sep, $ext) = qw( _ wav );
	my ($dir, $basename) = ($self->dir, $self->basename);
#	print "dir: ", $self->dir(), $/;
	#print "basename: ", $self->basename(), $/;
	logit(__PACKAGE__,'debug',"getver: dir $dir basename $basename sep $sep ext $ext");
	my %versions = ();
	for my $candidate ( candidates($dir) ) {
	#	logit(__PACKAGE__,'debug',"candidate: $candidate");
	
		my( $match, $dummy, $num) = 
			( $candidate =~ m/^ ( $basename 
			   ($sep (\d+))? 
			   \.$ext ) 
			  $/x
			  ); # regex statement
		if ( $match ) { $versions{ $num || 'bare' } =  $match }
	}
	logit(__PACKAGE__,'debug',sub{"get_version: " , ::yaml_out(\%versions)});
	%versions;
}

sub candidates {
	my $dir = shift;
	$dir =  File::Spec::Link->resolve_all( $dir );
	opendir my $wavdir, $dir or die "cannot open $dir: $!";
	my @candidates = readdir $wavdir;
	closedir $wavdir;
	@candidates = grep{ ! (-s join_path($dir, $_) == 44 ) } @candidates;
	#$logit(__PACKAGE__,'debug',join $/, @candidates);
	@candidates;
}

sub targets {
	
	my $self = shift; 

#	$::debug2 and print "&targets\n";
	
		my %versions =  $self->get_versions;
		if ($versions{bare}) {  $versions{1} = $versions{bare}; 
			delete $versions{bare};
		}
	logit(__PACKAGE__,'debug',sub{"\%versions\n================\n", yaml_out(\%versions)});
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
