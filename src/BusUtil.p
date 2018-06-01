{
package ::BusUtil;
use Role::Tiny;
use Modern::Perl;
use ::Globals qw(%tn %bn PLAY OFF MON);

sub version_has_edits { 
	my ($track) = @_;
	grep
		{ 		$_->host_track eq $track->name
     		and $_->host_version == $track->playback_version
		} values %::Edit::by_name;
}	
sub bus_tree { # for solo function to work in sub buses
	my $track = shift;
	my $mix = $track->group;
	return if $mix eq 'Main';
	($mix, $tn{$mix}->bus_tree);
}

sub activate_bus {
	my $track = shift;
	 ::add_bus($track->name) unless $track->is_system_track;
}
sub deactivate_bus {
	my $track = shift;
	return if $track->is_system_track;
	my $bus = $bn{$track->name};
	$bus->set( rw => OFF );
}
}
1;


