## refresh functions

sub set_widget_color {
	my ($widget, $status) = @_;
	my %rw_foreground = (	REC  => $gui->{_nama_palette}->{RecForeground},
						 	MON => $gui->{_nama_palette}->{MonForeground},
						 	OFF => $gui->{_nama_palette}->{OffForeground},
						);

	my %rw_background =  (	REC  => $gui->{_nama_palette}->{RecBackground},
							MON  => $gui->{_nama_palette}->{MonBackground},
							OFF  => $gui->{_nama_palette}->{OffBackground});

	$widget->configure( -background => $rw_background{$status} );
	$widget->configure( -foreground => $rw_foreground{$status} );
}


	
sub refresh_group { 
	# main group, in this case we want to skip null group
	$debug2 and print "&refresh_group\n";
	
	
		my $status;
		if ( 	grep{ $_->rec_status eq 'REC'} 
				map{ $tn{$_} }
				$bn{Main}->tracks ){

			$status = 'REC'

		}elsif(	grep{ $_->rec_status eq 'MON'} 
				map{ $tn{$_} }
				$bn{Main}->tracks ){

			$status = 'MON'

		}else{ 
		
			$status = 'OFF' }

$debug and print "group status: $status\n";

	set_widget_color($gui->{group_rw}, $status); 



	croak "some crazy status |$status|\n" if $status !~ m/rec|mon|off/i;
		#$debug and print "attempting to set $status color: ", $take_color{$status},"\n";

	set_widget_color( $gui->{group_rw}, $status) if $gui->{group_rw};
}
sub refresh_track {
	
	my $ui = shift;
	my $n = shift;
	$debug2 and print "&refresh_track\n";
	
	my $rec_status = $ti{$n}->rec_status;
	$debug and print "track: $n rec_status: $rec_status\n";

	return unless $gui->{tracks}->{$n}; # hidden track
	
	# set the text for displayed fields

	$gui->{tracks}->{$n}->{rw}->configure(-text => $rec_status);
	$gui->{tracks}->{$n}->{ch_r}->configure( -text => 
				$n > 2
					? $ti{$n}->source
					:  q() );
	$gui->{tracks}->{$n}->{ch_m}->configure( -text => $ti{$n}->send);
	$gui->{tracks}->{$n}->{version}->configure(-text => $ti{$n}->current_version || "");
	
	map{ set_widget_color( 	$gui->{tracks}->{$n}->{$_}, 
							$rec_status)
	} qw(name rw );
	
	set_widget_color( 	$gui->{tracks}->{$n}->{ch_r},
				
 							($rec_status eq 'REC'
								and $n > 2 )
 								? 'REC'
 								: 'OFF');
	
	set_widget_color( $gui->{tracks}->{$n}->{ch_m},
							$rec_status eq 'OFF' 
								? 'OFF'
								: $ti{$n}->send 
									? 'MON'
									: 'OFF');
}

sub refresh {  
	::remove_riff_header_stubs();
 	$ui->refresh_group(); 
	#map{ $ui->refresh_track($_) } map{$_->n} grep{!  $_->hide} ::Track::all();
	#map{ $ui->refresh_track($_) } grep{$remove_track_widget{$_} map{$_->n}  ::Track::all();
	map{ $ui->refresh_track($_) } map{$_->n}  ::Track::all();
}
### end
