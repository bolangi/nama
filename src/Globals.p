package ::Globals;
use Exporter::Lite;
use Modern::Perl;
our @EXPORT = qw(

[% qx(cat ./singletons.pl) %]
[% qx(cat ./globals.pl   ) %]

);

1;
