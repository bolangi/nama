use Modern::Perl;
use File::Slurp;
my %var_map = 
			
			map  { split " ", $_ }  # store as key/value pairs
			grep { my @var = split " ", $_; @var == 2 } # take only substitutions
			grep{ ! /^\s*$/ }  	# skip blank lines
			split "\n", var_map();

my @singletons = singletons();
use Data::Dumper;
#print Dumper \%var_map;
#print join $/, singletons();

my @filenames = glob("*.p *pl *.t");
say join $/, @filenames;
my $ov_regex = qr/my [^;]*?$old_var_name\b/s;
my $s_regex = qr/my [^;]*?$singleton_name\b/s;

my @old_vars = keys %var_map;
map{
	my $file = $_;
	my $contents = read_file($_);

	map {   my $old_var_name = $_;
			my $ov_regex = qr/my [^;]*?$old_var_name\b/s;
			say "old var name $old_var_name found in file $file" 
				if $contents =~ /$ov_regex/s
	} @old_vars;
	map {
			my $singleton_name = $_;
			my $s_regex = qr/my [^;]*?$singleton_name\b/s;
			say "singleton name $singleton_name found in file $file" 
				if $contents =~ /$ov_regex/s
	} @singletons
} @filenames;

=comment

substitute $project->{name} for $project_name in assignment

	$project->{name} = ......

substitute $config->{devices} for %devices
and use a reference to the hash instead of a hash

	$config->{devices} = { hash structure }

=cut

sub singletons {
	my $singletons = read_file("./singletons.pl");
	map{ s/,//; $_ } split " ", $singletons;
}



sub var_map { 

	my $var_map = read_file("./var_map");
	$var_map
}


# end
