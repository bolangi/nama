### customize.pl - user code

# test this by typing:
#
#     perl customize.pl
#
# or, if you are running from your build directory, e.g.
#
#     perl -I ~/build/nama/lib customize.pl

use Modern::Perl;
use Nama::Globals qw(:all);

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
				my $v = $this_track->playback_version;
				promote_version_to_track($this_track, $v);
		},

 		# Change the current project's sample rate
		# Usage: set_samplerate <samplerate>
		# Accepted sample rates: 8kHz, 11025Hz, 16kHz, 22.05kHz, 24kHz, 32kHz,
		# 44.1kHz, 48kHz, 64kHz, 88.2kHz and 96kHz
		# but you must write them long form: 44100 not 44.1kHz
		
		set_samplerate => sub {
				my ($srate) = @_;
				my @allowable = qw{ 96000 88200 64000 48000 44100 32000 24000 22050 16000 11025 8000 };
				my %allowable = map{$_ => 1} @allowable; 
				if ( $allowable{$srate} ){
				
						$project->{sample_rate} = $srate;
				}
				else
				{
						say("$srate is not an allowed samplerate.");
						say("Use one of: @allowable");
				}
				print ("\n")
		},

	},

);
