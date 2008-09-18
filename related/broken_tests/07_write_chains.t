package Audio::Multitrack; ## correct variable namespace
use Audio::Multitrack;
use Test::More qw(no_plan);
use Getopt::Std;
use vars qw(%opts $project $debug $ui $project_name);
my $debug = 1;
### Option Processing ###
push @ARGV, qw( -e  );
#push @ARGV, qw(-d /media/sessions test-abc  );
getopts('mcegsd:', \%opts); 
#print join $/, (%opts);
# d: wav_dir
# c: create project
# g: gui mode
# m: don't load state info
# e: don't load static effects data
# s: don't load static effects data cache
$project = shift;
$debug and print "project name: $project\n";
$project and $project_name = $project;
$ui = $opts{g} ?  Audio::Multitrack::Graphical->new : Audio::Multitrack::Text->new;
$ui->prepare; 
#$ui->loop;


my $sax = Audio::Multitrack::Track->new( name => 'sax' );

my $piano  = Audio::Multitrack::Track->new( name => 'piano', ch_r => 2 );

use vars qw($ch_m $ch_r);
$ch_m = 3; $ch_r = 7;
add_track("vocal"); 

my $group = $Audio::Multitrack::Group::by_name{$sax->group};
map{ print $_->dump } map { $Audio::Multitrack::Track::by_name{$_} } ($group->tracks); 

exit;

print "group name: ", $group->name, $/;

#print keys %Audio::Multitrack::Track::by_name; exit;


print "tracks: ", $group->tracks , $/;
$master_fader->apply;

$tracker->apply;

#is ( yaml_out( \%Audio::Multitrack::inputs ). yaml_out(\%Audio::Multitrack::outputs), $nice_output, "Apply bus rules to generate chains");

print  yaml_out( \%Audio::Multitrack::inputs ). yaml_out(\%Audio::Multitrack::outputs);

UI::write_chains();



1;

__END__

