## refresh functions

sub set_widget_color {
	my ($widget, $status) = @_;
	my %rw_foreground = (REC  => 'Black', 
					MON => 'Black',
					OFF => 'Black');
	my %rw_background =  (REC  => 'LightPink', 
					MON => 'AntiqueWhite',
					OFF => $old_bg);

	$widget->configure( -background => $rw_background{$status} );
}


	
sub refresh_group { # tracker group 
	$debug2 and print "&refresh_group\n";
	
	
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

$debug and print "group status: $status\n";

	set_widget_color($group_rw, $status); 



	croak "some crazy status |$status|\n" if $status !~ m/rec|mon|off/i;
		#$debug and print "attempting to set $status color: ", $take_color{$status},"\n";

	set_widget_color( $group_rw, $status) if $group_rw;
}
sub refresh_track {
	
	@_ = discard_object(@_);
	my $n = shift;
	$debug2 and print "&refresh_track\n";
	
	my $rec_status = $ti[$n]->rec_status;
	$debug and print "track: $n rec_status: $rec_status\n";

	#	return unless $track_widget{$n}; # hidden track
		$track_widget{$n}->{rw}->configure(-text => $rec_status);
		 $track_widget{$n}->{ch_r}->configure( -text =>
		 $ti[$n]->ch_r || 1);
		 #$track_widget{$n}->{ch_m}->configure( -text => $ti[$n]->ch_m);
		$track_widget{$n}->{version}->configure(-text => $ti[$n]->current_version);
	
	if ($rec_status eq "REC") {

		$track_widget{$n}->{name}->configure(-background => 'lightpink');
		$track_widget{$n}->{name}->configure(-foreground => 'Black');
		$track_widget{$n}->{ch_r}->configure(-background => 'LightPink');
		$track_widget{$n}->{ch_r}->configure(-foreground => 'Black');
		$track_widget{$n}->{rw}->configure(-background => 'LightPink');
		$track_widget{$n}->{rw}->configure(-foreground => 'Black');
		#$track_widget{$n}->{ch_m}->configure( -background => $old_bg);
		#$track_widget{$n}->{ch_m}->configure( -foreground => 'DarkGray');

	}
	elsif ( $rec_status eq "MON" ) {

		 $track_widget{$n}->{name}->configure(-background => 'AntiqueWhite');
		 $track_widget{$n}->{name}->configure(-foreground => 'Black');
		 $track_widget{$n}->{ch_r}->configure( -background => $old_bg);
		 $track_widget{$n}->{ch_r}->configure( -foreground => $old_bg);
		# $track_widget{$n}->{ch_m}->configure( -background => 'AntiqueWhite');
		# $track_widget{$n}->{ch_m}->configure( -foreground => 'Black');
		$track_widget{$n}->{rw}->configure(-background => 'AntiqueWhite');
		$track_widget{$n}->{rw}->configure(-foreground => 'Black');

		}
	elsif ( $rec_status eq "OFF" ) {
		 $track_widget{$n}->{name}->configure(-background => $old_bg);
		 $track_widget{$n}->{ch_r}->configure( -background => $old_bg); 
		 $track_widget{$n}->{ch_r}->configure( -foreground => $old_bg);
		 #$track_widget{$n}->{ch_m}->configure( -background => $old_bg); 
		# $track_widget{$n}->{ch_m}->configure( -foreground => 'Gray');
		$track_widget{$n}->{rw}->configure(-background => $old_bg);
		$track_widget{$n}->{rw}->configure(-foreground => 'Black');
		}  
		else { carp "\$rec_status contains something unknown: $rec_status";}
}
sub refresh {  
	remove_small_wavs();
 	$ui->refresh_group(); 
	map{ $ui->refresh_track($_) } map{$_->n} ::Track::all();
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
