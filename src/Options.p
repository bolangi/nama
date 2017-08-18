# --------- Command line options ----------

package ::;
use Modern::Perl;

sub nama_line_options {

	my %options = qw(

        save-alsa  		a
		project-root=s  d
		use-pwd			p
		create-project  c
		config=s		f
		gui			  	g
		text			t
		no-state		M
		net-eci			n
		libecasoundc	l
		help			h
		regenerate-effects-cache	r
		no-static-effects-data		S
		no-static-effects-cache		C
		no-reconfigure-engine		R
		fake-jack					J
		fake-alsa					A
		fake-ecasound				E
		debugging-output			D
		execute-command=s			X
		no-terminal					T
        no-fade-on-transport-start  F
		log=s                       L
		no-latency                  O
		latency                     Q
		sample-rate=s				z
   
);

	map{$config->{opts}->{$_} = ''} values %options;

	# long options

	Getopt::Long::Configure ("bundling");	
	my $getopts = 'GetOptions( ';
	map{ $getopts .= qq("$options{$_}|$_" => \\\$config->{opts}->{$options{$_}}, \n)} keys %options;
	$getopts .= ' )' ;

	#say $getopts;

	eval $getopts or die "Stopped.\n";
	
	if ($config->{opts}->{h}){ say $help->{usage}; exit; }

}
BEGIN {
$help->{usage} = <<HELP;

USAGE: nama [options] [project_name]

--gui, -g                        Start Nama in GUI mode
--text, -t                       Start Nama in text mode
--config, -f                     Specify configuration file (default: ~/.namarc)
--project-root, -d               Specify project root directory
--use-pwd, -p                    Use current dir for all WAV and project files
--create-project, -c             Create project if it doesn't exist
--net-eci, -n                    Use Ecasound's Net-ECI interface
--libecasoundc, -l               Use Ecasound's libecasoundc interface
--save-alsa, -a                  Save/restore alsa state with project data
--help, -h                       This help display
--regenerate-effects-cache, -r   Regenerate the effects data cache
--sample-rate, -z                use this sample rate, and set as default for session

Debugging options:

--no-state, -M                   Don't load project state
--no-static-effects-data, -S     Don't load effects data
--no-static-effects-cache, -C    Don't load effects data cache
--no-reconfigure-engine, -R      Don't autosave, autoreconfigure or git snapshot
--fake-jack, -J                  Simulate JACK environment
--fake-alsa, -A                  Simulate ALSA environment
--no-ecasound, -E                Don't spawn Ecasound process
--execute-command, -X            Supply a command to execute
--no-terminal, -T                Don't initialize terminal
--no-fades, -F                   No fades on transport start/stop
--log, -L                        Log these (comma separated) categories

HELP
}
# --latency, -Q                    Apply latency compensation
# --no-latency, -O                 Don't apply latency compensation

1;
__END__
	

