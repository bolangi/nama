# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 1;
BEGIN { use_ok('Audio::Ecasound::Flow') };

#########################

use Getopt::Std;

### Option Processing ###
use vars qw(%opts $session_name $debug);
@ARGV=qw(-g -m -e paul_brocante);
getopts('mcegsd', \%opts); 
# d: wav_dir
# c: create session
# g: gui mode
# m: don't load state info
# e: don't load static effects data
$session_name = shift;
$debug and print "session name: $session_name\n";

#sub hello {print "superclass hello\n"};
#sub hello {print "make a window\n";}
#sub hello {print "hello world!\n"}
my $gui = Audio::Ecasound::Flow::UI::Graphical->new;
is ($gui->hello, "make a window", " ::UI::Graphical->hello");
#my $gui2 = Audio::Ecasound::Flow::UI->new("tk");
#is ($gui2->hello, "make a window", " ::UI::Graphical->hello");
#my $tui = Audio::Ecasound::Flow::UI::Text->new;
#is ($tui->hello, "hello world!", " ::UI::Text->hello");
#ok ($ui->prepare);
#ok ($ui->loop);

#$ui->loop;
#&prepare;
#&loopg;



#ok(1);
#ok(1);

=comment
ok(my $ui = UI->new, 'UI new');
ok($ui->hello, 'Baseclass UI hello');
ok(my $tui = UI::Text->new, 'TUI new');
ok($tui->hello, 'Text UI  hello');
ok(my $gui = UI::Graphical->new, 'Graphical new');
ok($gui->hello, 'Graphical UI hello');
=cut

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.
__END__
1;
