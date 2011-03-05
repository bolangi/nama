# ------ Config subroutines ------

package ::;
use Modern::Perl;
our (
	%opts,
	$project_root,
	%subst,
	$debug2,
	$project_name,
	%cfg,
	$default,
	@config_vars,
);

## configuration file

{ # OPTIMIZATION

  # we allow for the (admitted rare) possibility that
  # $project_root may change

my %proot;
sub project_root { 
	$proot{$project_root} ||= resolve_path($project_root)
}
}

sub config_file { $opts{f} ? $opts{f} : ".namarc" }

{ # OPTIMIZATION
my %wdir; 
sub this_wav_dir {
	$opts{p} and return $project_root; # cwd
	$project_name and
	$wdir{$project_name} ||= resolve_path(
		join_path( project_root(), $project_name, q(.wav) )  
	);
}
}

sub project_dir {
	$opts{p} and return $project_root; # cwd
	$project_name and join_path( project_root(), $project_name) 
}

sub global_config {

	# return text of config file, in the following order
	# or priority:
	#
	# 1. the file designated by the -f command line argument
	# 2. .namarc in the current project directory, i.e. ~/nama/untitled/.namarc
	# 3. .namarc in the home directory, i.e. ~/.namarc
	# 4. .namarc in the project root directory, i.e. ~/nama/.namarc
	if( $opts{f} ){
		print("reading config file $opts{f}\n");
		return read_file($opts{f});
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
# 	io( join_path($ENV{HOME}, config_file()))->all;
# }

sub read_config {

	# read and process the configuration file
	#
	# use the embedded default file if none other is present
	
	$debug2 and print "&read_config\n";
	
	my $config = shift;
	my $yml = length $config > 100 ? $config : $default;
	strip_all( $yml );
	%cfg = %{  yaml_in($yml) };
	*subst = \%{ $cfg{abbreviations} }; # alias
	walk_tree(\%cfg);
	walk_tree(\%cfg); # second pass completes substitutions
	assign_var( \%cfg, @config_vars);
	$project_root = $opts{d} if $opts{d};
	$project_root = expand_tilde($project_root);

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
1;
__END__
