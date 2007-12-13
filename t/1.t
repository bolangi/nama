# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 2;
BEGIN { use_ok('Audio::Ecasound::Flow') };

#########################

package Audio::Ecasound::Flow;

### Option Processing ###
use vars qw(%opts $session_name $debug);
getopts('mceg', \%opts); 
$session_name = 'paul_brocante';
$debug and print "session name: $session_name\n";
&prepare;
&loopg;

ok(1);
ok(1);

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
