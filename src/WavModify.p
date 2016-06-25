package ::WavModify;
use Role::Tiny;
use Modern::Perl;
use ::Globals qw(PLAY);

sub normalize {
	my $track = shift;
	if ($track->rec_status ne PLAY){
		::throw($track->name, ": You must set track to PLAY before normalizing, skipping.\n");
		return;
	} 
	# track version will exist if PLAY status
	my $cmd = 'ecanormalize ';
	$cmd .= $track->full_path;
	::pager("executing: $cmd\n");
	system $cmd;
}
sub fixdc {
	my $track = shift;
	if ($track->rec_status ne PLAY){
		::throw($track->name, ": You must set track to PLAY before fixing dc level, skipping.\n");
		return;
	} 

	my $cmd = 'ecafixdc ';
	$cmd .= $track->full_path;
	::pager("executing: $cmd\n");
	system $cmd;
}
1;
