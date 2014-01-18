# ----------------- Analyse LV2 Plugins ------------------

# contributed by S. Massy
#
package ::AnalyseLV2;
use ::Log qw(logpkg);
# Initialise our global variables:
# Store the plugin info:

use strict;

my %plugin;
my %scalepoints;

# Path to utilities
my $lv2info;
my $lv2ls;

# Various internals:
my $currentport;

my @contents;

sub _analyse_lv2 {
	%plugin = ();
	# Some variables used here.
	my ($uri) = @_;
	my $linecount = my $match;

	$currentport = -1;
	unless (acquire_lv2($uri)) 
	{ $plugin{error} = "Plugin not found."; return \%plugin; }

	foreach my $line (@contents) {
		logpkg('debug',"Parsing $line");
		$linecount++;
		$plugin{general}{uri} = $line if ($linecount == 1);
		if ($line =~ /^(\t| )+Name\:(\t| )+(.*+)/
			&& $currentport == -1)
		{ $plugin{general}{name} = $3; }
		if (($line =~ /^(\t| )+Class\:(\t| )+(.*+)/) && !($line =~ /(\:\/\/)/) )
		{ $plugin{general}{class} = $3; }
		if ($line =~ /^(\t| )+Author\:(\t| )+(.*+)/)
		{ $plugin{general}{author} = $3; }
		if ($line =~ /^(\t| )+Has latency\:(\t| )+(.*+)/)
		{ $plugin{general}{has_latency} = $3; }
		# Next we embark on port data collection.
		# ...fffirst acquire current port.
		if ($line =~ /^(\t| )+file\:\/\/.*\.ttl$/ 
		&& ($currentport == -1) ) {
			chomp($line);
			$line =~ s/(\t| )+file\:\/\///;
			$plugin{'general'}{'datafile'} = $line;
			logpkg('debug',"datafile: $plugin{'general'}{'datafile'}\n");
		}
		if ($line =~ /(\t| )+Port (\d+)\:$/) { 
			$currentport = $2;
			logpkg('debug',"Acquiring info for $currentport\n");
		}
		# type
		if ($line =~ /lv2core#(.+)Port$/) {
			$match = $1;
			if ($match =~ /Input|Output/) {
				$plugin{$currentport}{iotype} = $match;
				logpkg('debug',"IOTYPE $plugin{$currentport}{iotype}\n");
			} else {
				if (exists($plugin{$currentport}{etype})) {
					$plugin{$currentport}{etype} .= " ";
				}
				$plugin{$currentport}{etype} .= $match;
				logpkg('debug',"Acquired ETYPE $1 \n");
			}
		}
		# A special case for events.
		if ($line =~ /http.+\#(.+)Event$/ ) {
			$match = $1;
			if ( exists($plugin{$currentport}{etype}) ) {
				$plugin{$currentport}{etype} .= ", ";
			}
			$plugin{$currentport}{etype} .= $match;
		}

		# Name
		if ($line =~ /(\t| )+Name\:(\t| )+(.+$)/
			&& ($currentport != -1)) {
			$plugin{$currentport}{name} = $3;
			logpkg('debug',"Port name is $plugin{$currentport}{name}\n");
		}
		# MINVAL/MAXVAL/DEFVAL
		if ($line =~ /(\t| )+Minimum\:(\t| )+(.+$)/) {
			$plugin{$currentport}{minval} = $3;
			logpkg('debug',"Acquired minval $plugin{$currentport}{minval}\n");
		}
		if ($line =~ /(\t| )+Maximum\:(\t| )+(.+$)/) {
			$plugin{$currentport}{maxval} = $3;
		}
		if ($line =~ /(\t| )+Default\:(\t| )+(.+$)/) {
			$plugin{$currentport}{defval} = $3;
		}
		# Properties
		if ($line =~ /extportinfo#(.+$)/) {
			if (exists($plugin{$currentport}{props})) {
				$plugin{$currentport}{props} .= ", ";
			}
			$plugin{$currentport}{props} .= $1;
		}
		if ($currentport != -1 && $line =~ /Scale Points\:/) {
			$plugin{$currentport}{scalepoints} = 0;
		}
		if ($line =~ /(\t+| +)+(-?\d+\.?\d*) = \"(.*)\"$/
			&& exists($plugin{$currentport}{scalepoints})) {
			$plugin{$currentport}{scalepoints}++;
			$scalepoints{$currentport}{$2} = $3;
		}
	}




	$plugin{general}{maxport} = $currentport;
	$currentport = -1;


# We iterate over the ports to add the selector property.
	for ($currentport = 0; $currentport <= $plugin{general}{maxport};
		$currentport++) {
		if (exists($plugin{$currentport}{scalepoints})) {
			if (exists($plugin{$currentport}{props})) {
				$plugin{$currentport}{props} .= ", ";
			}
			$plugin{$currentport}{props} .= $plugin{$currentport}{scalepoints} . "-way Selector";
		}
	}

	# Gather info from datafile
	proc_datafile($plugin{'general'}{'datafile'});

	return (\%plugin, \%scalepoints);

} # end of sub crunch

sub stripzeros {
	my ($value) = @_;
	$value =~ s/\.0+$|0+$//;
	return $value;
}

sub generateportinfo {
	my $portinfo;
	$portinfo .= "\"$plugin{$currentport}{'name'}";
	# For units
	if (exists($plugin{$currentport}{'units'})) {
		$portinfo .= " (" . cunits($plugin{$currentport}{'units'}) . ")";
	}
	$portinfo .= "\" ";
	$portinfo .= "$plugin{$currentport}{iotype}, ";
	$portinfo .= "$plugin{$currentport}{etype}";
	$portinfo .= ", " . &stripzeros($plugin{$currentport}{minval})
	if exists($plugin{$currentport}{minval});
	$portinfo .= " to " . &stripzeros($plugin{$currentport}{maxval})
	if exists($plugin{$currentport}{maxval});
	$portinfo .= ", default " . &stripzeros($plugin{$currentport}{defval})
	if (exists($plugin{$currentport}{defval})

		&& $plugin{$currentport}{defval} ne "nan");
	$portinfo .= ", " . filterprops($plugin{$currentport}{props})
	if (exists($plugin{$currentport}{props})
		&& filterprops($plugin{$currentport}{props}) ne "");
	$portinfo .= "\n";
	return $portinfo;
}

sub filterprops { # Try to limit output
	my ($props) = @_;
	# Cut HasStrictBounds is long, uuuuuuseless?, and not in ladspa
	$props =~ s/, hasStrictBounds|hasStrictBounds, |hasStrictBounds//;
	# Don't just leave a comma and space
	$props =~ s/^, $|^ +$//;
	logpkg('debug',"props: $props\n");
	return $props;;
}

sub print_lv2 {
	my @buffer;
	push @buffer, "Name: $plugin{general}{name}\n" 
	if exists($plugin{general}{name});
	push @buffer, "URI: $plugin{general}{uri}";
	push @buffer, "Class: $plugin{general}{class}\n"
	if exists($plugin{general}{class});
	push @buffer, "Author: $plugin{general}{author}\n"
	if exists($plugin{general}{author});
	push @buffer, "Latency: $plugin{general}{has_latency}\n"
	if exists($plugin{general}{has_latency});
	for ($currentport = 0; $currentport <= $plugin{general}{maxport}; $currentport++) {
		if ($currentport == 0) {
			push @buffer, "Ports:  ";
		} else {
			push @buffer, "\t";
		}
		push @buffer, generateportinfo();
	}
	push @buffer, "\n";
	return @buffer;
}

sub acquire_lv2 {
	my ($uri) = @_;
	@contents = `$lv2info $uri`;
	logpkg('debug',"Acquiring contents for $uri\n");
#	logpkg('debug',"$contents[0]\n";
	return 0 if ($contents[0] eq "");
	return 1;
}

sub find_utils {
	my $output;
	$output = `which lv2info`;
	chomp($output);
	if ( $output =~ /^\/.+lv2info$/ ) {
		$lv2info = $output;;
	} else { return 0; }
	$output = `which lv2ls`;
	chomp($output);
	if ( $output =~ /^\/.+lv2ls$/ ) {
		$lv2ls = $output;
	} else { return 0; }
	return 1;
}

sub trymatch {
	my ($string) = @_;
	my @lv2lsoutput = `$lv2ls`;
	my @results;
	foreach my $uline (@lv2lsoutput) {
		chomp($uline);
		push(@results, ($uline)) if ($uline =~ /$string/i);
	}
	return @results;
}

sub print_lv2_scalepoints {
	my @buffer;
	if (keys(%scalepoints) > 0) {
		push @buffer, "Printing full information for ports with scale points in plugin...\n$plugin{general}{name}\n";
		foreach my $port (sort {$a <=> $b} (keys(%scalepoints))) {
			$currentport = $port;
			push @buffer, "Port $currentport: " . generateportinfo();
			foreach my $point ( sort {$a <=> $b} (keys(%{ $scalepoints{$currentport} })) ) {
				push @buffer, "\t $point \= $scalepoints{$currentport}{$point}\n";
			}
		}
	}
	else { push @buffer, "Plugin $plugin{general}{name} does not have any port with scale points.\n\n"; }
	return @buffer;
}

sub analyse_lv2 {
	my ($uri) = @_;
	if ( find_utils() ) {
		return _analyse_lv2($uri);
	} else {
		$plugin{error} = "Utilities not found.";
		return \%plugin;
	}
}

sub lv2_help {
	my $uri = shift;
	find_utils();
	analyse_lv2($uri);
	print_lv2();
}

#print lv2_help('http://plugin.org.uk/swh-plugins/zm1');
#print lv2_help('urn:50m30n3:plugins:SO-404');

sub proc_datafile {
	my ($file) = @_;
	open(my $fh, "<", $file) || return 0;
	$currentport = -1;
	while (my $curline = <$fh>) {
		if ($curline =~ /lv2\:index +(\d+) *;$/ ) {
			$currentport = $1;
		}
		if ($curline =~ /ue\:unit +ue\:([a-zA-Z0-9_]+) *;$/ 
			&& ($currentport != -1)) {
			$plugin{$currentport}{'units'} = $1;
		}
	}
	close($fh);
	$currentport = -1;
	return 1;
}

sub cunits {
	(my $units) = @_;
	$units =~ s/pc/\%/ if $units =~ /pc/;
	return $units;
}


1;
