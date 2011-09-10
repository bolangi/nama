### custom.pl - Nama user customization file

# See notes at end

##  Prompt section - replaces default user prompt

prompt =>  
	q{
	"nama [". ($this_bus eq 'Main' ? '': "$this_bus/").  
		($this_track ? $this_track->name : '') . "] >"
	},


##  Aliases section - shortcuts to any Nama or user-defined commands

aliases => 
	{
		mbs => 'move_to_bus',
		pcv => 'promote_current_version',
		hi => 'greet',
		djp => 'disable_jack_polling',
	},


## Commands section - user defined commands

commands => 
	{
			
		disable_jack_polling => 
			q{
				$engine->{events}->{poll_jack} = undef
			},
		promote_current_version =>
			q{
				my $v = $this_track->monitor_version;
				promote_version_to_track($this_track, $v);
			},
		greet => 
			q{
				my ($name,$adjective) = @_;
				print ("Hello $name! You look $adjective today!!\n");
			},
	},

# __END__
# 

# Syntax notes:

# 0. Quick Start - To avoid breaking this file:
#
#   + Be careful of matching curly brackets {}. (Also [] () if you use them.)
#     All should be properly paired.
#
#   + Closing brackets are usually followed by a comma, i.e,
#
#          key => q{ some 
#                    various
#                    stuff
#           }, 
#
# 
# 1. The => Operator
# 
#     The => operator is similar to the comma ",". It
#     is used to indicate a key-value pair, i.e.
#   
#          greeting => 'hello earthlings!',
#   
#          pi       => 3.14,
#   
# 2. The q{..} Notation
# 
#     The q{.....} notation is a kind of quoting, like "....."
#     It is special, in that it can contain quotes without choking i.e.
#   
#          q{"here is a message", "john","marilyn",'single'}
# 
# 3. Curly braces { }
# 
#     The outermost curly braces combine the following
#     commands and their defintions into a single
#     data structure called a 'hash' or 'dictionary'
# 
#          command => { magic_mix => q{ user code },
#                       death_ray => q{ more user code},
#                      }
# 
# (end of file)
