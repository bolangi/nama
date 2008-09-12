## refresh functions

sub refresh_t { # tracker group 
	$debug2 and print "&refresh_t\n";
	
	my %take_color = (REC  => 'LightPink', 
					MON => 'AntiqueWhite',
					OFF => $old_bg);
	
	
		my $status;
		if ( 	grep{ $_->rec_status eq 'REC'} 
				map{ $tn{$_} }
				$tracker->tracks ){

			$status = 'REC'

		}elsif(	grep{ $_->rec_status eq 'MON'} 
				map{ $tn{$_} }
				$tracker->tracks ){

			$status = 'MON'

		}else{ 
		
			$status = 'OFF' }


	croak "some crazy status |$status|\n" if $status !~ m/rec|mon|off/i;
		$debug and print "attempting to set $status color: ", $take_color{$status},"\n";

	$group_rw->configure(-background => $take_color{$status})
		if $group_rw;
}
sub refresh_c { # tracks
	
	@_ = discard_object(@_);
	my $n = shift;
	$debug2 and print "&refresh_c\n";
	
	my $rec_status = $ti[$n]->rec_status;
	$debug and print "track: $n rec_status: $rec_status\n";

	#	return unless $widget_c{$n}; # hidden track
		$widget_c{$n}->{rw}->configure(-text => $rec_status);
		 $widget_c{$n}->{ch_r}->configure( -text =>
		 $ti[$n]->ch_r || 1);
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
	elsif ( $rec_status eq "OFF" ) {
		 $widget_c{$n}->{name}->configure(-background => $old_bg);
		 $widget_c{$n}->{ch_r}->configure( -background => $old_bg); 
		 $widget_c{$n}->{ch_r}->configure( -foreground => 'Gray');
		 $widget_c{$n}->{ch_m}->configure( -background => $old_bg); 
		$widget_c{$n}->{ch_m}->configure( -foreground => 'Gray');
		}  
		else { carp "\$rec_status contains something unknown: $rec_status";}
}
sub refresh {  
	remove_small_wavs();
 	$ui->refresh_t(); 
	map{ $ui->refresh_c($_) } map{$_->n} ::Track::all();
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
