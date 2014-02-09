# ------------- Mute and Solo routines -----------

package ::;
use Modern::Perl;

sub mute {
	return if $config->{opts}->{F};
	return if $tn{Master}->rw eq OFF or ::ChainSetup::really_recording();
	$tn{Master}->mute;
}
sub unmute {
	return if $config->{opts}->{F};
	return if $tn{Master}->rw eq OFF or ::ChainSetup::really_recording();
	$tn{Master}->unmute;
}
sub fade_around {
	my ($coderef, @args) = @_;
	if( engine_running() )
	{
		mute();
		$coderef->(@args);
		unmute();
	}
	else { $coderef->(@args) }
}
sub fade {
	my ($id, $param, $from, $to, $seconds) = @_;

	# no fade without Timer::HiRes
	# no fade unless engine is running
	if ( ! engine_running() or ! $config->{hires_timer} ){
		effect_update_copp_set ( $id, --$param, $to );
		return;
	}

	my $steps = $seconds * $config->{fade_resolution};
	my $wink  = 1/$config->{fade_resolution};
	my $size = ($to - $from)/$steps;
	logpkg('debug', "id: $id, param: $param, from: $from, to: $to, seconds: $seconds");
	for (1..$steps - 1){
		modify_effect( $id, $param, '+', $size);
		sleeper( $wink );
	}		
}

sub fadein {
	my ($id, $to) = @_;
	my $from  = $config->{fade_out_level}->{fxn($id)->type};
	fade( $id, 1, $from, $to, $config->{engine_fade_length_on_start_stop});
}
sub fadeout {
	my $id    = shift;
	my $from  =	fxn($id)->params->[0];
	my $to	  = $config->{fade_out_level}->{fxn($id)->type};
	fade( $id, 1, $from, $to, $config->{engine_fade_length_on_start_stop} );
}

sub solo {
	my @args = @_;

	# get list of already muted tracks if I haven't done so already
	
	if ( ! @{$fx->{muted}} ){
		@{$fx->{muted}} = map{ $_->name } grep{ defined $_->old_vol_level} 
                         map{ $tn{$_} } 
						 ::Track::user();
	}

	logpkg('debug', join " ", "already muted:", sub{map{$_->name} @{$fx->{muted}}});

	# convert bunches to tracks
	my @names = map{ bunch_tracks($_) } @args;

	# use hashes to store our list
	
	my %to_mute;
	my %not_mute;
	
	# get dependent tracks
	
	my @d = map{ $tn{$_}->bus_tree() } @names;

	# store solo tracks and dependent tracks that we won't mute

	map{ $not_mute{$_}++ } @names, @d;

	# find all siblings tracks not in depends list

	# - get buses list corresponding to our non-muting tracks
	
	my %buses;
	$buses{Main}++; 				# we always want Main
	
	map{ $buses{$_}++ } 			# add to buses list
	map { $tn{$_}->group } 			# corresponding bus (group) names
	keys %not_mute;					# tracks we want

	# - get sibling tracks we want to mute

	map{ $to_mute{$_}++ }			# add to mute list
	grep{ ! $not_mute{$_} }			# those we *don't* want
	map{ $bn{$_}->tracks }			# tracks list
	keys %buses;					# buses list

	# mute all tracks on our mute list (do we skip already muted tracks?)
	
	do_many_tracks( { tracks => [ keys %to_mute ], method => 'mute' } );

	# unmute all tracks on our wanted list
	
	do_many_tracks( { tracks => [ keys %not_mute ], method => 'unmute' } );
	
	$mode->{soloing} = 1;
}

sub nosolo {
	# unmute all except in @{$fx->{muted}} list

	# unmute all tracks
	do_many_tracks( { tracks => [ ::Track::user() ], method => 'unmute' } );

	# re-mute previously muted tracks
	if (@{$fx->{muted}}){
		do_many_tracks( { tracks => [ @{$fx->{muted}} ], method => 'mute' } );
	}

	# remove listing of muted tracks
	@{$fx->{muted}} = ();
	
	$mode->{soloing} = 0;
}
sub all {

	# unmute all tracks
	do_many_tracks( { tracks => [ ::Track::user() ], method => 'unmute' } );

	# remove listing of muted tracks
	@{$fx->{muted}} = ();
	
	$mode->{soloing} = 0;
}

sub do_many_tracks {
	# args: { tracks => [ name list ], method => method_name }
	my $args = shift;
	my $method = $args->{method};
	my $delay = $args->{delay} || $config->{engine_muting_time};
	map{ $tn{$_}->$method('nofade'); sleeper($delay) } @{$args->{tracks}};
}

1;
__END__
