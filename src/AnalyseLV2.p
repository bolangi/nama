package AnalyseLV2;
# Initialise our global variables:
# Store the plugin info:
my %plugin = my %scalepoints;

# Path to utilities
my $lv2info = my $lv2ls;

# Various internals:
my $currentport;

# Temporary declaration to make strict happy.
my @contents;




sub _analyse_lv2 {
	# Some variables used here.
	my ($uri) = @_;
	my $linecount = my $match;

	$currentport = -1;
	unless (acquire_lv2($uri)) 
	{ $plugin{'ERROR'} = "Plugin not found."; return \%plugin; }

	foreach my $line (@contents) {
		print "Parsing $line" if $debug;
		$linecount++;
		$plugin{'GENERAL'}{'URI'} = $line if ($linecount == 1);
		if ($line =~ /^(\t| )+Name\:(\t| )+(.*+)/
			&& $currentport == -1)
		{ $plugin{'GENERAL'}{'NAME'} = $3; }
		if (($line =~ /^(\t| )+Class\:(\t| )+(.*+)/) && !($line =~ /(\:\/\/)/) )
		{ $plugin{'GENERAL'}{'CLASS'} = $3; }
		if ($line =~ /^(\t| )+Author\:(\t| )+(.*+)/)
		{ $plugin{'GENERAL'}{'AUTHOR'} = $3; }
		if ($line =~ /^(\t| )+Has latency\:(\t| )+(.*+)/)
		{ $plugin{'GENERAL'}{'HAS_LATENCY'} = $3; }
		# Next we embark on port data collection.
		# ...fffirst acquire current port.
		if ($line =~ /(\t| )+Port (\d+)\:$/) { 
			$currentport = $2;
			print "Acquiring info for $currentport\n" if $debug;
		}
		# type
		if ($line =~ /lv2core#(.+)Port$/) {
			$match = $1;
			if ($match =~ /Input|Output/) {
				$plugin{$currentport}{'IOTYPE'} = $match;
				print "IOTYPE $plugin{$currentport}{'IOTYPE'}\n" if $debug;
			} else {
				if (exists($plugin{$currentport}{'ETYPE'})) {
					$plugin{$currentport}{'ETYPE'} .= " ";
				}
				$plugin{$currentport}{'ETYPE'} .= $match;
				print "Acquired ETYPE $1 \n" if $debug;
			}
		}
		# A special case for events.
		if ($line =~ /http.+\#(.+)Event$/ ) {
			$match = $1;
			if ( exists($plugin{$currentport}{'ETYPE'}) ) {
				$plugin{$currentport}{'ETYPE'} .= ", ";
			}
			$plugin{$currentport}{'ETYPE'} .= $match;
		}

		# Name
		if ($line =~ /(\t| )+Name\:(\t| )+(.+$)/
			&& ($currentport != -1)) {
			$plugin{$currentport}{'NAME'} = $3;
			print "Port name is $plugin{$currentport}{'NAME'}\n" 
			if $debug;	
		}
		# MINVAL/MAXVAL/DEFVAL
		if ($line =~ /(\t| )+Minimum\:(\t| )+(.+$)/) {
			$plugin{$currentport}{'MINVAL'} = $3;
			print "Acquired minval $plugin{$currentport}{'MINVAL'}\n" if $debug;
		}
		if ($line =~ /(\t| )+Maximum\:(\t| )+(.+$)/) {
			$plugin{$currentport}{'MAXVAL'} = $3;
		}
		if ($line =~ /(\t| )+Default\:(\t| )+(.+$)/) {
			$plugin{$currentport}{'DEFVAL'} = $3;
		}
		# Properties
		if ($line =~ /extportinfo#(.+$)/) {
			if (exists($plugin{$currentport}{'PROPS'})) {
				$plugin{$currentport}{'PROPS'} .= ", ";
			}
			$plugin{$currentport}{'PROPS'} .= $1;
		}
		if ($currentport != -1 && $line =~ /Scale Points\:/) {
			$plugin{$currentport}{'SCALEPOINTS'} = 0;
		}
		if ($line =~ /(\t+| +)+(-?\d+) = \"(.*)\"$/
			&& exists($plugin{$currentport}{'SCALEPOINTS'})) {
			$plugin{$currentport}{'SCALEPOINTS'}++;
			$scalepoints{$currentport}{$2} = $3;
		}
	}




	$plugin{'GENERAL'}{'MAXPORT'} = $currentport;
	$currentport = -1;


# We iterate over the ports to add the selector property.
	for ($currentport = 0; $currentport <= $plugin{'GENERAL'}{'MAXPORT'};
		$currentport++) {
		if (exists($plugin{$currentport}{'SCALEPOINTS'})) {
			if (exists($plugin{$currentport}{'PROPS'})) {
				$plugin{$currentport}{'PROPS'} .= ", ";
			}
			$plugin{$currentport}{'PROPS'} .= $plugin{$currentport}{'SCALEPOINTS'} . "-way Selector";
		}
	}

	return (\%plugin, \%scalepoints);

} # end of sub crunch

sub stripzeros {
	my ($value) = @_;
	$value =~ s/\.0+$|0+$//;
	return $value;
}

sub generateportinfo {
	my $portinfo;
	$portinfo .= "\"$plugin{$currentport}{'NAME'}\" ";
	$portinfo .= "$plugin{$currentport}{'IOTYPE'}, ";
	$portinfo .= "$plugin{$currentport}{'ETYPE'}";
	$portinfo .= ", " . &stripzeros($plugin{$currentport}{'MINVAL'})
	if exists($plugin{$currentport}{'MINVAL'});
	$portinfo .= " to " . &stripzeros($plugin{$currentport}{'MAXVAL'})
	if exists($plugin{$currentport}{'MAXVAL'});
	$portinfo .= ", default " . &stripzeros($plugin{$currentport}{'DEFVAL'})
	if (exists($plugin{$currentport}{'DEFVAL'})

		&& $plugin{$currentport}{'DEFVAL'} ne "nan");
	$portinfo .= ", " . filterprops($plugin{$currentport}{'PROPS'})
	if (exists($plugin{$currentport}{'PROPS'})
		&& filterprops($plugin{$currentport}{'PROPS'}) ne "");
	$portinfo .= "\n";
	return $portinfo;
}

sub filterprops { # Try to limit output
	my ($props) = @_;
	# Cut HasStrictBounds is long, uuuuuuseless?, and not in ladspa
	$props =~ s/, hasStrictBounds|hasStrictBounds, |hasStrictBounds//;
	# Don't just leave a comma and space
	$props =~ s/^, $|^ +$//;
	print "props: $props\n" if $debug;
	return $props;;
}

sub print_lv2 {
	my @buffer;
	push @buffer, "Name: $plugin{'GENERAL'}{'NAME'}\n" 
	if exists($plugin{'GENERAL'}{'NAME'});
	push @buffer, "URI: $plugin{'GENERAL'}{'URI'}";
	push @buffer, "Class: $plugin{'GENERAL'}{'CLASS'}\n"
	if exists($plugin{'GENERAL'}{'CLASS'});
	push @buffer, "Author: $plugin{'GENERAL'}{'AUTHOR'}\n"
	if exists($plugin{'GENERAL'}{'AUTHOR'});
	push @buffer, "Latency: $plugin{'GENERAL'}{'HAS_LATENCY'}\n"
	if exists($plugin{'GENERAL'}{'HAS_LATENCY'});
	for ($currentport = 0; $currentport <= $plugin{'GENERAL'}{'MAXPORT'}; $currentport++) {
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
	print "Acquiring contents for $uri\n" if $debug;
#	print "$contents[0]\n";
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
		push @buffer, "Printing full information for ports with scale points in plugin...\n$plugin{'GENERAL'}{'NAME'}\n";
		foreach my $port (sort(keys(%scalepoints))) {
			$currentport = $port;
			push @buffer, "Port $currentport: " . generateportinfo();
			foreach my $point ( sort(keys(%{ $scalepoints{$currentport} })) ) {
				push @buffer, "\t $point \= $scalepoints{$currentport}{$point}\n";
			}
		}
	}
	else { push @buffer, "Plugin $plugin{'GENERAL'}{'NAME'} does not have any port with scale points.\n\n"; }
	return @buffer;
}

sub analyse_lv2 {
	my ($uri) = @_;
	if ( find_utils() ) {
		return _analyse_lv2($uri);
	} else {
		$plugin{'ERROR'} = "Utilities not found.";
		return \%plugin;
	}
}

1;
