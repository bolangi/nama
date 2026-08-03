# --------- Command line options ----------

package ::;
use v5.36;

sub process_command_line_options {

	my %options = (
[% qx(./generate_options specs) %]	);

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
$help->{usage} = <<'HELP';
[% qx(./generate_options help) %]
HELP
}

1;
__END__
	
