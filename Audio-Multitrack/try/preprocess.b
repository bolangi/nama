use IO::All;

local $debug = 1;
$debug and print "Preprocessing\n";
sub preprocess {
my ($file, $ext, $coderef) = @_; # $file: Flow for Flow.pm
$debug and print "file: $file, extension: $ext\ coderef: ", ref $code, $/;

my $subs = io "$file.subs";#  subroutine declarations
$debug and print "subs: $subs\n";

my $vars = io "$file.vars";#  variable declarations
my $defs = io "$file.defs";#  definitions
my $ppc  = io "$file.ppc"; #  source for making $file.pm

my $use_subs = "use subs qw($subs);$/";
my $use_vars = "use vars qw($vars);$/";

my $pm = $ppc; # transform into pm

sub include_regex {
	my $file = shift; 
	qr/^ # begining of line
    	\# hash
		\s* # zero or more space
		include
		\s+		
		$file
		\b # boundary
		/x; # extended regex
}
my $re = include_regex("$file.subs");
$pm =~ s/$re/$use_subs/;

$re = include_regex("$file.vars");
$pm =~ s/$re/$use_vars/;

$re = include_regex("$file.defs");
$pm =~ s/$re/$defs/;

$pm > io "$file.pm";
