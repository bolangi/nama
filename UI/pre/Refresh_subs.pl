## refresh functions

sub refresh_t { # buses
	$debug2 and print "&refresh_t\n";
	local $debug = $debug3;
	my %take_color = (REC  => 'LightPink', 
					MON => 'AntiqueWhite',
					MUTE => $old_bg);
	my @w = $take_frame->children;
	for my $t (1..scalar @w - 1){
		# skip 0th item, the label
		my $status;
		if ( 	grep{ $_->rec_status eq 'REC'} 
				map{ $tn{$_} }
				$::Group::by_name{Tracker}->tracks ){

			$status = 'REC'

		}elsif(	grep{ $_->rec_status eq 'MON'} 
				map{ $tn{$_} }
				$::Group::by_name{Tracker}->tracks ){

			$status = 'MON'

		}else{ 
		
			$status = 'MUTE' }


	croak "some crazy status |$status|\n" if $status !~ m/rec|mon|mute/i;
		$debug and print "attempting to set $status color: ", $take_color{$status},"\n";
	$debug and print "take_frame child: $t\n";

		$w[$t]->configure(-background => $take_color{$status});
	}
}
sub refresh_c { # tracks
	local $debug = 1;
	shift @_ if (ref $_[0]) =~ /UI/; # discard object XXX
	my $n = shift;
	$debug2 and print "&refresh_c\n";
	
	$debug and print "track: $n\n"; # rec_status: $rec_status\n";
		my $rec_status = $ti[$n]->rec_status;
	$debug and print "track: $n rec_status: $rec_status\n";

	#	return unless $widget_c{$n}; # hidden track
		$widget_c{$n}->{rw}->configure(-text => $rec_status);
		 $widget_c{$n}->{ch_r}->configure( -text => $ti[$n]->ch_r);
		 $widget_c{$n}->{ch_m}->configure( -text => $ti[$n]->ch_m);
		$widget_c{$n}->{version}->configure(-text => $ti[$n]->current_version);
	
	if ($rec_status eq "REC") {

		$widget_c{$n}->{name}->configure(-background => 'lightpink');
		$widget_c{$n}->{name}->configure(-foreground => 'Black');
		$widget_c{$n}->{ch_r}->configure(-background => 'LightPink');
		$widget_c{$n}->{ch_r}->configure(-foreground => 'Black');
		$widget_c{$n}->{ch_m}->configure( -background => $old_bg);
		$widget_c{$n}->{ch_m}->configure( -foreground => 'DarkGray');

	}
	elsif ( $rec_status eq "MON" ) {

		 $widget_c{$n}->{name}->configure(-background => 'AntiqueWhite');
		 $widget_c{$n}->{name}->configure(-foreground => 'Black');
		 $widget_c{$n}->{ch_r}->configure( -background => $old_bg);
		 $widget_c{$n}->{ch_r}->configure( -foreground => 'DarkGray');
		 $widget_c{$n}->{ch_m}->configure( -background => 'AntiqueWhite');
		 $widget_c{$n}->{ch_m}->configure( -foreground => 'Black');

		}
	elsif ( $rec_status eq "MUTE" ) {
		 $widget_c{$n}->{name}->configure(-background => $old_bg);
		 $widget_c{$n}->{ch_r}->configure( -background => $old_bg); 
		 $widget_c{$n}->{ch_r}->configure( -foreground => 'Gray');
		 $widget_c{$n}->{ch_m}->configure( -background => $old_bg); 
		$widget_c{$n}->{ch_m}->configure( -foreground => 'Gray');
		}  
		else { carp "\$rec_status contains something unknown: $rec_status";}
}
sub refresh {  
 	# $ui->refresh_t(); 
	collect_chains;
	map{ $ui->refresh_c($_) } @all_chains ;
}
sub refresh_oids{ # OUTPUT buttons
	map{ $widget_o{$_}->configure( # uses hash
			-background => 
				$oid_status{$_} ?  'AntiqueWhite' : $old_bg,
			-activebackground => 
				$oid_status{$_} ? 'AntiqueWhite' : $old_bg
			) } keys %widget_o;
}

sub restore_time_marker_labels {
	
	# restore time marker labels
	
	map{ $time_marks[$_]->configure( 
		-text => $marks[$_]
			?  colonize($marks[$_])
			:  $_,
		-background => $marks[$_]
			?  $old_bg
			: q(lightblue),
		)
	} 1..$#time_marks;

 }


### end
