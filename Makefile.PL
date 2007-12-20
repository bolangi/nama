use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
#
use lib 'lib';
my $module = 'UI';
my ($dir, $name);
($name = $module)   =~ s/.*::(\w+)/$1.pm/;
($dir = $module)    =~ s/(.*)::(\w+)/$1/;
($dir_slash = $dir) =~ s(::)(/)g;
$dir 				=~ s/::/-/g;

my $from = "lib/$dir_slash/$name";

WriteMakefile(
    'NAME'		=> $name,
    'VERSION_FROM'	=> $from, # finds $VERSION
    'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => $from, # retrieve abstract from module
       AUTHOR     => 'Joel Roth <jroth@joelz@pobox.com>') : ()),
	'dist' => { COMPRESS=>"gzip", 
			   SUFFIX=>"gz", 
				   PREOP=>('rm -f README; '.
						   "pod2text -80 < $name > README; ".
						   "cp -f README $dir-\$(VERSION); "
						  ),
				 },
);
