package ::Wav;
use v5.36;
our $VERSION = 1.001;
use ::Globals qw(%bn $config);
use ::Util qw(join_path);
use ::Assign qw(json_out);
use ::Log qw(logpkg);
use Memoize qw(memoize unmemoize); # called by code in ::Memoize.pm
use warnings;
no warnings qw(uninitialized);

use Role::Tiny;

sub wav_length ($track) {
	::wav_length($track->full_path)
}
sub wav_format ($track) {
	::wav_format($track->full_path)
}

	
sub dir ($self) {
	 $self->project  
		? join_path(::project_root(), $self->project, '.wav')
		: ::this_wav_dir();
}

sub basename ($self) {
	$self->target || $self->name
}

sub full_path ($track) { join_path($track->dir, $track->current_wav) }

sub group_last ($track) {
	my $bus = $bn{$track->group}; 
	$bus->last;
}

sub last { $_[0]->versions->[-1] || 0 }
sub current_wav ($track) {
	my $last = $track->current_version;
	if 	($track->candidate_rec){
		$track->name . '_' . $last . '.wav'
	} elsif ($track->candidate_play){
		my $filename = $track->targets->{ $track->playback_version } ;
		$filename
	} else {
		logpkg('debug', "track ", $track->name, ": no current version") ;
		undef; 
	}
}

sub current_version ($track) {

	# two possible version numbers, depending on REC/PLAY status
	
	if 	($track->candidate_rec)
	{ 
		my $last = $config->{use_group_numbering} 
					? ::Bus::overall_last()
					: $track->last;
		return ++$last
	}
	elsif ($track->candidate_play){ return $track->playback_version }
	else { return 0 }
}

sub playback_version ($track) {
	return $track->version if $track->version 
				and grep {$track->version  == $_ } $track->versions->@* ;
	$track->last;
}
sub targets ($self) { # WAV file targets, distinct from 'target' attribute
	_targets(dir => $self->dir, name => $self->basename)
}
sub versions ($self) {
	_versions(dir => $self->dir, name => $self->basename) 
}


sub get_versions {
	my %args = @_;
	$args{sep} //= '_';
	$args{ext} //= 'wav';
	my ($sep, $ext) = ($args{sep}, $args{ext});
	my ($dir, $basename) = ($args{dir}, $args{name});
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

sub _targets {
	
	my %args = @_;

#	$::debug2 and print "&targets\n";
	
		my %versions =  get_versions(%args);
		if ($versions{bare}) {  $versions{1} = $versions{bare}; 
			delete $versions{bare};
		}
	logpkg('debug',sub{"\%versions\n================\n", json_out(\%versions)});
	\%versions;
}

sub _versions {  
#	$::debug2 and print "&versions\n";
	my %args = @_;
	[ sort { $a <=> $b } keys _targets(%args)->%* ]  
}
1;
