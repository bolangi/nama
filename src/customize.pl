### customize.pl - Nama user customization file

# test this by typing:
#
#     perl customize.pl
#
# or, if you are running from your build directory, e.g.
#
#     perl -I ~/build/nama/lib customize.pl

use Modern::Perl;
use Audio::Nama::Globals qw(:all);

my @user_customization = (

prompt => sub { 

	"nama ".
 	git_branch_display().   # The name of the project branch you 
							# are working on;
							# suppressed if you are on
							# the 'master' (default) branch.
	"[". 
	this_track_name().		# the name of the current track 
	this_bus_display(). 	# The name of the current bus;
							 # suppressed if you the current
							 # track is in the 'Main' bus.
 	"] > "
 	},

## user defined commands

commands => 
	{
		# usage: greet <name> <adjective>
		greet => sub { 
				my ($name,$adjective) = @_;
				print ("Hello $name! You look $adjective today!!\n");
		},
		disable_jack_polling => sub{ $engine->{events}->{poll_jack} = undef },

		promote_current_version => sub {
				my $v = $this_track->monitor_version;
				promote_version_to_track($this_track, $v);
		},

	},

);
