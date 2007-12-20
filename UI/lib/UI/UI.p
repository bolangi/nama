package ::;
our @ISA;
use Object::Tiny qw(mode);
sub hello {print "superclass hello\n"};

package ::Graphical;
our @ISA = '::';
sub hello {print "make a window\n";}

package ::Text;
our @ISA = '::';
sub hello {print "hello world!\n";}

my $ui = ::->new;
$ui->hello;

__END__
my $tui = ::Text->new;
$tui->hello;

my $gui = ::Graphical->new;
$gui->hello;
