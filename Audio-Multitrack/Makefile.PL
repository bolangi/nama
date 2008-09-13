use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
#
use lib 'lib';
my $module = 'Audio::Ecasound::Multitrack';
my ($dir, $name);
($name = $module)   =~ s/(\w+::)*(\w+)/$2.pm/;
($dir = $module)    =~ s/(.+)(::)(\w+)/$1/;
#$dir =~ s/::$//;
($dir_slash = $dir) =~ s(::)(/)g;
#$dir =~ s(::)(/)g;
#$dir =~ s(/$)(/)g;
$dir 				=~ s/::/-/g;
#print "dir: $dir, dir_slash: $dir_slash, name: $name"; exit;

my $from = "lib/$dir_slash/$name";
print "from: $from\n";
#my $from = $name;

WriteMakefile(
    'NAME'		=> $name,
    'VERSION_FROM'	=> $from, # finds $VERSION
    'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
	EXE_FILES    => [qw(scripts/nama)],
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => $from, # retrieve abstract from module
       AUTHOR     => 'Joel Roth <jroth@joelz@pobox.com>') : ()),
	'dist' => { COMPRESS=>"gzip", 
			   SUFFIX=>"gz", 
# 				   PREOP=>('rm -f README; '.
# 						   "pod2text -80 < $name > README; ".
# 						   "cp -f README $dir-\$(VERSION); "
#						  ),
				 },
);
