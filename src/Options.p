# --------- Command line options ----------

package ::;
use v5.36;

sub process_command_line_options {

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

	$config->{opts}->{$_} = '' for values %options;

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

--create-project, -c             Create project if it doesn't exist
--sample-rate, -z                Set sample rate for project
--help, -h                       This help display

Advanced options

--gui, -g                        Start Nama in GUI mode (experimental)
--regenerate-effects-cache, -r   Regenerate effects data cache
--project-root, -d               Specify project root directory
--config, -f                     Specify configuration file (default: ~/.namarc)
--use-pwd, -p                    Use current dir for all WAV and project files
--net-eci, -n                    Use Ecasound's Net-ECI interface (default)
--libecasoundc, -l               Use Ecasound's libecasoundc interface
--save-alsa, -a                  Save/restore alsa state with project data
--no-ecasound, -E                Don't spawn Ecasound process
--no-state, -M                   Don't load project state
--no-static-effects-data, -S     Don't load effects data
--no-static-effects-cache, -C    Don't load effects data cache
--no-reconfigure-engine, -R      Don't automatically save or reconfigure
--no-terminal, -T                Don't initialize terminal
--no-fades, -F                   No fades on transport start/stop
--fake-jack, -J                  Simulate JACK environment
--fake-alsa, -A                  Simulate ALSA environment
--log, -L                        Log these (comma separated) categories
--execute-command, -X            Supply a command to execute

HELP
}
# --latency, -Q                    Apply latency compensation
# --no-latency, -O                 Don't apply latency compensation

1;
__END__
	

