### customize.pl - user code

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
	no warnings 'uninitialized';
	join ' ', 'nama', git_branch_display(), bus_track_display(), '> ' 
},

## user defined commands

commands => 
	{
		# usage: greet <name> <adjective>
		greet => sub { 
				my ($name,$adjective) = @_;
				pager("Hello $name! You look $adjective today!!");
		},
		disable_jack_polling => sub{ $project->{events}->{poll_jack} = undef },

		promote_current_version => sub {
				my $v = $this_track->monitor_version;
				promote_version_to_track($this_track, $v);
		},

	},

);
