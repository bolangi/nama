# ------ Config subroutines ------

package ::;
use Modern::Perl;
no warnings 'uninitialized';

# global variables
our (


	@config_vars, 	# vars to read from namarc

	$debug,
	$debug2,

);

use ::Globals qw(:singletons);

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
					my $config = join_path($_, config_file());
					if( -f $config or -l $config){ 
						say "Found config file: $config";
						my $yml = read_file($config);
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
	
	$debug2 and print "&read_config\n";
	
	my $config_name_or_contents = shift;
	my $yml = length $config_name_or_contents > 100
		?  $config_name_or_contents
		:  get_data_section("default_namarc");

	strip_all( $yml );
	my %cfg = %{  yaml_in($yml) };
	*subst = \%{ $cfg{abbreviations} }; # alias
	walk_tree(\%cfg);
	walk_tree(\%cfg); # second pass completes substitutions
	assign_var_map( \%cfg, @config_vars);
	$config->{root_dir} = $config->{opts}->{d} if $config->{opts}->{d};
	$config->{root_dir} = expand_tilde($config->{root_dir});
	$config->{sampling_freq} = $cfg{abbreviations}{frequency};

}
sub walk_tree {
	#$debug2 and print "&walk_tree\n";
	my $ref = shift;
	map { substitute($ref, $_) } 
		grep {$_ ne q(abbreviations)} 
			keys %{ $ref };
}
sub substitute{
	my ($parent, $key)  = @_;
	my $val = $parent->{$key};
	#$debug and print qq(key: $key val: $val\n);
	ref $val and walk_tree($val)
		or map{$parent->{$key} =~ s/$_/$subst{$_}/} keys %subst;
}
sub first_run {
	return if $config->{opts}->{f};
	my $config_path = config_file();
	$config_path = "$ENV{HOME}/$config_path" unless -e $config_path;
	$debug and print "config path: $config_path\n";
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

		 write_file(user_customization_file(), $file->{custom_pl});
		
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

1;
__END__
