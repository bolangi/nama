## refresh functions

sub set_widget_color {
	my ($widget, $status) = @_;
	my %rw_foreground = (	REC  => $namapalette{RecForeground},
						 	MON => $namapalette{MonForeground},
						 	OFF => $namapalette{OffForeground},
						);

	my %rw_background =  (	REC  => $rec,
							MON  => $mon,
							OFF  => $off );
		
#	print "namapalette:\n",yaml_out( \%namapalette);
#	print "rec: $rec, mon: $mon, off: $off\n";

	$widget->configure( -background => $rw_background{$status} );
	$widget->configure( -foreground => $rw_foreground{$status} );
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
	
	#my $debug = 1;
	@_ = discard_object(@_);
	my $n = shift;
	$debug2 and print "&refresh_track\n";
	
	my $rec_status = $ti[$n]->rec_status;
	$debug and print "track: $n rec_status: $rec_status\n";

	#return unless $track_widget{$n}; # hidden track
	
	# set the text for displayed fields

	$track_widget{$n}->{rw}->configure(-text => $rec_status);
	$track_widget{$n}->{ch_r}->configure( -text => 
				$n > 2
					? $ti[$n]->source
					:  q() );
	$track_widget{$n}->{ch_m}->configure( -text => $ti[$n]->send);
	$track_widget{$n}->{version}->configure(-text => $ti[$n]->current_version);
	
	map{ set_widget_color( 	$track_widget{$n}->{$_}, 
							$rec_status)
	} qw(name rw );
	
	set_widget_color( 	$track_widget{$n}->{ch_r},
							$rec_status eq 'REC'
								? 'MON'
								: 'OFF');
	
	set_widget_color( $track_widget{$n}->{ch_m},
							$rec_status eq 'OFF' 
								? 'OFF'
								: $ti[$n]->send 
									? 'MON'
									: 'OFF');
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
