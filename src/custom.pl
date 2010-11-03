prompt => sub 
	{
	"nama [". ($this_bus eq 'Main' ? '': "$this_bus/").  
		($this_track ? $this_track->name : '') . "] ('h' for help)> "
	},

aliases => {

	promote_current_version => sub
		{
		$this_track =~ /^([^-]+)/;  # match any chars before first '-'
		my $name_root = $1;         # assign matched text
		my $v = $this_track->monitor_version;
		my $new_name = "$name_root-v$v";
		promote_version_to_track($this_track, $v, $new_name, $this_bus);
		},

	pcv => 'promote_current_version',
}
