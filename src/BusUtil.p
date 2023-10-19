{
package ::BusUtil;
use Role::Tiny;
use Modern::Perl '2020';
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
sub is_mixer {
	my $track = shift;
	my $type = $track->{source_type};
	return unless defined $type and $type eq 'bus';
	my $id = $track->{source_id};
	my $bus = $bn{$id};
	$bus	
}
}
1;


