## refresh functions
package ::Graphical;
use Tk;

## clock and refresh functions

sub start_clock {
	$clock_id = $clock->repeat(1000, \refresh_clock);
}
sub update_clock {
	clock_display(-text => colonize(eval_iam('cs-get-position')));
}
sub restart_clock {
	eval q($clock_id->cancel);
	start_clock();
}
sub refresh_clock{
	clock_display(-text => colonize(eval_iam('cs-get-position')));
	my $status = eval_iam('engine-status');
	return if $status eq 'running' ;
	$clock_id->cancel;
	session_label_configure(-background => $old_bg);
	if ($status eq 'error') { new_engine();
		&connect_transport unless &really_recording; 
	}
	elsif ($status eq 'finished') {
		&connect_transport unless &really_recording; 
	}
	else { # status: stopped, not started, undefined
	&rec_cleanup if &really_recording();
	}

}

sub refresh_t { # buses
	$debug2 and print "&refresh_t\n";
	my %take_color = (rec  => 'LightPink', 
					mon => 'AntiqueWhite',
					mute => $old_bg);
	collect_chains();
	my @w = $take_frame->children;
	for my $t (1..@takes){
		# skip 0th item, the label
		my $status;
		#  rec if @record entry for this take
		if ( grep{$take{$_}==$t}@record ) { 
			$debug and print "t-rec $t\n";	
			$status = $::REC } 
		# 	mon if @monitor entry
		elsif ( grep{$take{$_}==$t}@monitor )
			{ 
			$debug and print "t-mon $t\n";	
			$status = $::MON }

		else  { $status = $::MUTE;
			$debug and print "t-mute $t\n";	
		
		}

	croak "some crazy status |$status|\n" if $status !~ m/rec|mon|mute/;
		$debug and print "attempting to set $status color: ", $take_color{$status},"\n";
	$debug and print "take_frame child: $t\n";

		$w[$t]->configure(-background => $take_color{$status});
	}
}
sub refresh_c { # tracks

	my $n = shift;
	$debug2 and print "&refresh_c\n";
	
		my $rec_status = rec_status($n);
#	$debug and print "track: $n rec_status: $rec_status\n";

		return unless $widget_c{$n}; # obsolete ??
		$widget_c{$n}->{rw}->configure(-text => $rec_status);
	
	if ($rec_status eq $::REC) {
		$debug and print "REC! \n";

		$widget_c{$n}->{name}->configure(-background => 'lightpink');
		$widget_c{$n}->{name}->configure(-foreground => 'Black');
		$widget_c{$n}->{ch_r}->configure(-background => 'LightPink');
		$widget_c{$n}->{ch_r}->configure(-foreground => 'Black');
		$widget_c{$n}->{ch_m}->configure( -background => $old_bg);
		$widget_c{$n}->{ch_m}->configure( -foreground => 'DarkGray');
		$widget_c{$n}->{version}->configure(-text => new_version);

	}
	elsif ( $rec_status eq $::MON ) {
		$debug and print "MON! \n";

		 $widget_c{$n}->{name}->configure(-background => 'AntiqueWhite');
		 $widget_c{$n}->{name}->configure(-foreground => 'Black');
		 $widget_c{$n}->{ch_r}->configure( -background => $old_bg);
		 $widget_c{$n}->{ch_r}->configure( -foreground => 'DarkGray');
		 $widget_c{$n}->{ch_m}->configure( -background => 'AntiqueWhite');
		 $widget_c{$n}->{ch_m}->configure( -foreground => 'Black');
		$widget_c{$n}->{version}->configure(-text => selected_version($n));

		}
	elsif ( $rec_status eq $::MUTE ) {
		$debug and print "MUTE! \n";
		 $widget_c{$n}->{name}->configure(-background => $old_bg);
		 $widget_c{$n}->{ch_r}->configure( -background => $old_bg); 
		 $widget_c{$n}->{ch_r}->configure( -foreground => 'Gray');
		 $widget_c{$n}->{ch_m}->configure( -background => $old_bg); 
		$widget_c{$n}->{ch_m}->configure( -foreground => 'Gray');
		$widget_c{$n}->{version}->configure(-text => selected_version($n));
		}  
		else { carp "\$rec_status contains something unknown: $rec_status";}
}
sub refresh {  
 	refresh_t(); 
	map{ refresh_c($_) } @all_chains ;
}
sub refresh_oids{ # OUTPUT buttons
	map{ $widget_o{$_}->configure( # uses hash
			-background => 
				$oid_status{$_} ?  'AntiqueWhite' : $old_bg,
			-activebackground => 
				$oid_status{$_} ? 'AntiqueWhite' : $old_bg
			) } keys %widget_o;
}
### end
