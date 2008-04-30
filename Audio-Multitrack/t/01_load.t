# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More qw(no_plan);
# tests => 3;

BEGIN { use_ok('Audio::Multitrack') };

#########################

use Getopt::Std;

diag "using Audio::Multitrack::Graphical->new";
my $ui = Audio::Multitrack::Graphical->new;
is(defined $ui, 1, ":: instantiation" );
is( $ui->isa('Audio::Multitrack::Graphical'),1, "Parent class for ". ref $ui);
$ui = '';
diag "using Audio::Multitrack::Text->new";
$ui = Audio::Multitrack::Text->new;
is(defined $ui, 1, ":: instantiation" );
is( $ui->isa('Audio::Multitrack::Text'),1, "Parent class for ". ref $ui);
1;
__END__

