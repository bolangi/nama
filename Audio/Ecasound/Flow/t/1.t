# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN { use_ok('Audio::Ecasound::Flow') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

ok(&graphical, 'GUI interface');

ok(&textual, 'Text interface');

sub graphical {
	my $ui = UI::Graphical->new;
	$ui->prepare;
	$ui->main;
	1;
}
sub textual {
	my $tui = UI::Text->new;
	$ui->prepare;
	$ui->main;
	1;
}
