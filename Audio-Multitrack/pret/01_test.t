# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More qw(no_plan);
# tests => 3;

BEGIN { use_ok('::') };

#########################

use Getopt::Std;

### Option Processing ###
use vars qw(%opts $project_name $debug);
@ARGV = qw(-g -m -e paul_brocante);
getopts('mcegsd', \%opts); 
# d: wav_dir
# c: create project
# g: gui mode
# m: don't load state info
# e: don't load static effects data
$project_name = shift;
diag("project name: $project_name\n");

diag "using ::Graphical->new";
my $ui = ::Graphical->new;
is(defined $ui, 1, ":: instantiation" );
is( $ui->isa('::Graphical'),1, "Parent class for ". ref $ui);
$ui = '';
diag "using ::Text->new";
$ui = ::Text->new;
is(defined $ui, 1, ":: instantiation" );
is( $ui->isa('::Text'),1, "Parent class for ". ref $ui);
$ui = '';
=comment
$ui = ::->new('tk');;
is(defined $ui, 1, ":: instantiation" );
is( $ui->isa('::Graphical'),1, "Parent class for ". ref $ui);
=cut

__END__
my $ui = ::->new('tk');;
is(defined $ui, 1, ":: instantiation" );
is( $ui->isa('::Graphical'),1, "Parent class for ". ref $ui);



__END__
my $s = ::Project->new(name => 'paul_brocante');
is(defined $s, 1, "Project instantiation" );
is( $s->isa('::Project'),1, "Parent class for ". ref $s);
$nom = 'paul_brocante';
$::wav_dir = '/media/projects';
$::project_name = $nom;
is( $s->project_dir , '/media/projects/.ecmd/paul_brocante', "Directory shows");
#$gui->prepare; 
#$gui->loop;
__END__
#is( defined $gui, 6,  'new() returned something' );
#is( $gui->isa('::'), 1,"  and it's the right class" );
#is ($gui->hello, "make a window", " ::Graphical->hello");
my $gui2 = ::->new("tk");
is ($gui2->hello, "make a window", " ::Graphical->hello");
#my $tui = ::Text->new;
#is ($tui->hello, "hello world!", " ::Text->hello");
#ok ($ui->prepare);
#ok ($ui->loop);

#$ui->loop;
#&prepare;
#&loopg;



#ok(1);
#ok(1);

=comment
ok(my $ui = ::->new, ':: new');
ok($ui->hello, 'Baseclass :: hello');
ok(my $tui = ::Text->new, 'T:: new');
ok($tui->hello, 'Text ::  hello');
ok(my $gui = ::Graphical->new, 'Graphical new');
ok($gui->hello, 'Graphical :: hello');
=cut

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.
__END__
1;
