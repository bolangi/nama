## refresh functions

sub refresh_waveform_window {
	$gui->{wwcanvas}->delete('waveform',$_->name) for all_tracks();
 	my @playable = grep{ $_->play} user_tracks();
	map{ $_->waveform->display() } @playable;
	configure_waveform_window();
	generate_timeline(
			widget => $gui->{wwcanvas}, 
			y_pos => 600,
	);
}
sub height { $_[0] % 5 ? 5 : 10 }
sub generate_timeline {
	my %args = @_;
	my $length = ecasound_iam('cs-get-length');
	$length = int($length + 5.5);
	$args{seconds} = $length;
	my $pps = $config->{waveform_pixels_per_second};
	for (0..$args{seconds})
	{
		my $xpos = $_ * $pps;
		if ($_ % 10 == 0)
		{
			$args{widget}->createText( 
							$xpos, $args{y_pos} - 20, 
							-font => 'lucidasanstypewriter-bold-14', 
							-text => $_,
							);
		}
		$args{widget}->createLine(
			$xpos, $args{y_pos} - height($_),
			$xpos, $args{y_pos},
			-fill => 'black',
			-width => 1,
			-tags => 'timelime'
		);
	}

}
sub set_widget_color {
	my ($widget, $status) = @_;
	my %rw_foreground = (	REC  => $gui->{_nama_palette}->{RecForeground},
						 	PLAY => $gui->{_nama_palette}->{MonForeground},
						 	MON => $gui->{_nama_palette}->{MonForeground},
						 	OFF => $gui->{_nama_palette}->{OffForeground},
						);

	my %rw_background =  (	REC  => $gui->{_nama_palette}->{RecBackground},
							PLAY  => $gui->{_nama_palette}->{MonBackground},
						 	MON => $gui->{_nama_palette}->{MonBackground},
							OFF  => $gui->{_nama_palette}->{OffBackground});

	$widget->configure( -background => $rw_background{$status} );
	$widget->configure( -foreground => $rw_foreground{$status} );
}
sub refresh_group { 
	# main group, in this case we want to skip null group
	logsub("&refresh_group");
	
	
		my $status;
		if ( 	grep{ $_->rec} 
				map{ $tn{$_} }
				$bn{Main}->tracks ){

			$status = REC

		}elsif(	grep{ $_->play} 
				map{ $tn{$_} }
				$bn{Main}->tracks ){

			$status = PLAY

		}else{ 
		
			$status = OFF }

logit('::Refresh','debug', "group status: $status");

	set_widget_color($gui->{group_rw}, $status); 



	croak "some crazy status |$status|\n" if $status !~ m/rec|mon|off/i;
		#logit('::Refresh','debug', "attempting to set $status color: ", $take_color{$status});

	set_widget_color( $gui->{group_rw}, $status) if $gui->{group_rw};
}
sub refresh_track {
	
	my $ui = shift;
	my $n = shift;
	logsub("&refresh_track");
	
	my $rec_status = $ti{$n}->rec_status;
	logit('::Refresh','debug', "track: $n rec_status: $rec_status");

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
				
 							($rec_status eq REC
								and $n > 2 )
 								? REC
 								: OFF);
	
	set_widget_color( $gui->{tracks}->{$n}->{ch_m},
							$rec_status eq OFF
								? OFF
								: $ti{$n}->send 
									? MON
									: OFF);
}

sub refresh {  
	::remove_riff_header_stubs();
	map{ $ui->refresh_track($_) } map{$_->n}  ::audio_tracks();
	refresh_waveform_window() if $gui->{wwcanvas};
}
### end
