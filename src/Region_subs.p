# ------------ Region routines ----------

package ::;
use Modern::Perl; use Carp;
our ($this_track);

sub set_region {
	my ($beg, $end) = @_;
	$this_track->set(region_start => $beg);
	$this_track->set(region_end => $end);
	::Text::show_region();
}
sub new_region {
	my ($beg, $end, $name) = @_;
	$name ||= new_region_name();
	add_track_alias($name, $this_track->name);	
	set_region($beg,$end);
}
sub new_region_name {
	my $name = $this_track->name . '_region_';
	my $i;
	map{ my ($j) = /_(\d+)$/; $i = $j if $j > $i; }
		grep{/$name/} keys %::Track::by_name;
	$name . ++$i
}
sub remove_region {
	if (! $this_track->region_start){
		say $this_track->name, ": no region is defined. Skipping.";
		return;
	} elsif ($this_track->target ){
		say $this_track->name, ": looks like a region...  removing.";
		$this_track->remove;
	} else { undefine_region() }
}
	
sub undefine_region {
	$this_track->set(region_start => undef );
	$this_track->set(region_end => undef );
	print $this_track->name, ": Region definition removed. Full track will play.\n";
}
1;
__END__
