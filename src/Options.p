# --------- Command line options ----------

package ::;
use Modern::Perl;

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
		
);

	map{$config->{opts}->{$_} = ''} values %options;

	# long options

	Getopt::Long::Configure ("bundling");	
	my $getopts = 'GetOptions( ';
	map{ $getopts .= qq("$options{$_}|$_" => \\\$config->{opts}->{$options{$_}}, \n)} keys %options;
	$getopts .= ' )' ;

	#say $getopts;

	eval $getopts or die "Stopped.\n";
	$config->{opts}->{O} = ! $config->{opts}->{Q};
	
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

Debugging options:

--no-state, -M                   Don't load project state
--no-static-effects-data, -S     Don't load effects data
--no-static-effects-cache, -C    Bypass effects data cache
--no-reconfigure-engine, -R      Don't automatically configure engine
--debugging-output, -D           Emit debugging information
--fake-jack, -J                  Simulate JACK environment
--fake-alsa, -A                  Simulate ALSA environment
--no-ecasound, -E                Don't spawn Ecasound process
--execute-command, -X            Supply a command to execute
--no-terminal, -T                Don't initialize terminal
--no-fades, -F                   No fades on transport start/stop
--no-latency, -O                 Don't apply latency compensation
--log, -L                        Categories to log

HELP
}

1;
__END__
	

