# ------ Config subroutines ------

# To create a new config var:
#
# add the symbol e.g. $eager_mode to @config_vars in var_type.pl
# add the mapping (e.g. $eager_mode $mode->{_eager_opt} ) to file var_map

# these subs are in the main namespace

package ::;

my $logger = Log::Log4perl->get_logger("::Config");
use Modern::Perl;
no warnings 'uninitialized';

use ::Globals qw(:all);

# exclusive to this module
our ( 
	%subst,			# substitutions		
);

## configuration file

sub global_config {

	# return text of config file, in the following order
	# or priority:
	#
	# 1. the file designated by the -f command line argument
	# 2. .namarc in the current project directory, i.e. ~/nama/untitled/.namarc
	# 3. .namarc in the home directory, i.e. ~/.namarc
	# 4. .namarc in the project root directory, i.e. ~/nama/.namarc
	if( $config->{opts}->{f} ){
		print("reading config file $config->{opts}->{f}\n");
		return read_file($config->{opts}->{f});
	}
	my @search_path = (project_dir(), $ENV{HOME}, project_root() );
	my $c = 0;
		map{ 
				if (-d $_) {
					my $config_path = join_path($_, config_file());
					if( -f $config_path or -l $config_path){ 
						say "Found config file: $config_path";
						my $yml = read_file($config_path);
						return $yml;
					}
				}
			} ( @search_path) 
}

# sub global_config {
# 	read_file( join_path($ENV{HOME}, config_file()));
# }

sub read_config {

	# read and process the configuration file
	#
	# use the embedded default file if none other is present
	
	logsub("&read_config");
	
	my $config_file = shift;
	
	my $yml = $config_file // get_data_section("default_namarc");
	strip_all( $yml );
	my %cfg = %{  yaml_in($yml) };
	*subst = \%{$cfg{abbreviations}}; # alias
	walk_tree(\%cfg);
	walk_tree(\%cfg); # second pass completes substitutions
	assign( 
		data => \%cfg,
		vars => [ @config_vars ], # config file format doesnt change
		class => '::',
		var_map => 1,
	);
	$config->{root_dir} = $config->{opts}->{d} if $config->{opts}->{d};
	$config->{root_dir} = expand_tilde($config->{root_dir});
	$config->{sample_rate} = $cfg{abbreviations}{frequency};
	set_default_globals(); # in case they are undefined
}
sub walk_tree {
	#logsub("&walk_tree");
	my $ref = shift;
	map { substitute($ref, $_) } 
		grep {$_ ne q(abbreviations)} 
			keys %{ $ref };
}
sub substitute{
	my ($parent, $key)  = @_;
	my $val = $parent->{$key};
	#logit('::Config','debug', qq(key: $key val: $val\n) );
	ref $val and walk_tree($val)
		or map{$parent->{$key} =~ s/$_/$subst{$_}/} keys %subst;
}
sub first_run {
	return if $config->{opts}->{f};
	my $config_path = config_file();
	$config_path = "$ENV{HOME}/$config_path" unless -e $config_path;
	logit('::Config','debug', "config path: $config_path" );
	if ( ! -e $config_path and ! -l $config_path  ) {

	# check for missing components

	my $missing;
	my @a = `which analyseplugin`;
	@a or print( <<WARN
LADSPA helper program 'analyseplugin' not found
in $ENV{PATH}, your shell's list of executable 
directories. You will probably have more fun with the LADSPA
libraries and executables installed. http://ladspa.org
WARN
	) and  sleeper (0.6) and $missing++;
	my @b = `which ecasound`;
	@b or print( <<WARN
Ecasound executable program 'ecasound' not found
in $ENV{PATH}, your shell's list of executable 
directories. This suite depends on the Ecasound
libraries and executables for all audio processing! 
WARN
	) and sleeper (0.6) and $missing++;
	if ( $missing ) {
	print "You lack $missing main parts of this suite.  
Do you want to continue? [N] ";
	$missing and 
	my $reply = <STDIN>;
	chomp $reply;
	print("Goodbye.\n"), exit unless $reply =~ /y/i;
	}
print <<HELLO;

Aloha. Welcome to Nama and Ecasound.

HELLO
	sleeper (0.6);
	print "Configuration file $config_path not found.

May I create it for you? [yes] ";
	my $make_namarc = <STDIN>;
	sleep 1;
	print <<PROJECT_ROOT;

Nama places all sound and control files under the
project root directory, by default $ENV{HOME}/nama.

PROJECT_ROOT
	print "Would you like to create $ENV{HOME}/nama? [yes] ";
	my $reply = <STDIN>;
	chomp $reply;
	my $default_config;
	if ($reply !~ /n/i){
		# write project root path into default namarc
		$default_config = get_data_section("default_namarc");
		$default_config =~ s/^project_root.*$/project_root: $ENV{HOME}\/nama/m;
		
		# create path nama/untitled/.wav
		#
		# this creates directories for 
		#   - project root
		#   - project name 'untitled', the default project, and
		#   - project untitled's hidden directory for holding WAV files
		
		mkpath( join_path($ENV{HOME}, qw(nama untitled .wav)) );

		 write_file(user_customization_file(), get_data_section('custom_pl'));
		
	} else {
		print <<OTHER;
Please make sure to set the project_root directory in
.namarc, or on the command line using the -d option.

OTHER
	}
	if ($make_namarc !~ /n/i){
		write_file($config_path, $default_config);
	}
	sleep 1;
	print "\n.... Done!\n\nPlease edit $config_path and restart Nama.\n\n";
	print "Exiting.\n"; 
	exit;	
	}
}

sub set_default_globals {

	$config->{engine_globals_general} ||= "-z:mixmode,sum";
	$config->{engine_globals_realtime} ||= "-z:db,100000 -z:nointbuf";
	$config->{engine_globals_nonrealtime} ||= "-z:nodb -z:intbuf";
	$config->{engine_buffersize_realtime} ||= 256; 
	$config->{engine_buffersize_nonrealtime} ||= 1024;

}

1;
__END__
