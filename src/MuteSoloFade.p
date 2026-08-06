# ------------- Mute and Solo routines -----------

package ::;
use v5.36;

sub mute {
	return if $config->{opts}->{F};
	return if $tn{Main}->rw eq OFF or ::ChainSetup::really_recording();
	$tn{Main}->mute;
}
sub unmute {
	return if $config->{opts}->{F};
	return if $tn{Main}->rw eq OFF or ::ChainSetup::really_recording();
	$tn{Main}->unmute;
}
sub fade_around {
	my ($coderef, @args) = @_;
	if( $this_engine->started() )
	{
		mute();
		$coderef->(@args);
		unmute();
	}
	else { $coderef->(@args) }
}
sub solo {
	my @args = @_;

	# get list of already muted tracks if I haven't done so already
	
	if ( ! @{$fx->{muted}} ){
		@{$fx->{muted}} = map{ $_->name } grep{ defined $_->old_vol_level} user_tracks() }

	logpkg('debug', join " ", "already muted:", sub{map{$_->name} @{$fx->{muted}}});

	# convert bunches to tracks
	my @names = map{ bunch_tracks($_) } @args;

	# use hashes to store our list
	
	my %to_mute;
	my %not_mute;
	
	# get dependent tracks
	
	my @dependents = map{ $tn{$_}->bus_tree() } @names;

	# store solo tracks and dependent tracks that we won't mute

	map{ $not_mute{$_}++ } @names, @dependents;

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

	transition_tracks({
		mute => [keys %to_mute],
		unmute => [keys %not_mute],
	});
	
	$mode->{soloing} = 1;
}

sub nosolo {
	# unmute all except in @{$fx->{muted}} list

	my %previously_muted = map { $_ => 1 } @{$fx->{muted}};
	transition_tracks({
		unmute => [
			map { $_->name }
			grep { ! $previously_muted{$_->name} }
			user_tracks()
		],
	});

	# remove listing of muted tracks
	@{$fx->{muted}} = ();
	
	$mode->{soloing} = 0;
}
sub all {

	# unmute all tracks
	transition_tracks({ unmute => [map { $_->name } user_tracks()] });

	# remove listing of muted tracks
	@{$fx->{muted}} = ();
	
	$mode->{soloing} = 0;
}

sub transition_tracks {
	# Apply one coordinated ramp so all tracks reach corresponding levels
	# together. Whole excluded buses already arrive here as their mix tracks;
	# individual members are used only for partly soloed buses.
	my $args = shift;
	my $seconds = $args->{delay} || $config->{engine_muting_time};
	my @transitions;

	for my $method (qw(mute unmute)){
		for my $name (@{$args->{$method} || []}){
			my $track = $tn{$name} or next;
			my $vol = $track->volume_effect or next;

			if ($method eq 'mute'){
				next if defined $track->old_vol_level;
				my $from = $vol->params->[0];
				$track->set(old_vol_level => $from);
				push @transitions,
					[$method, $track, $vol, $from, $vol->mute_level];
			}
			else {
				next unless defined $track->old_vol_level;
				push @transitions,
					[$method, $track, $vol, $vol->params->[0],
						$track->old_vol_level];
			}
		}
	}

	return unless @transitions;
	my $steps = ::Effect::fade_step_count($seconds);
	if ($steps and $this_engine->started() and $config->{hires_timer}){
		my $wink = $seconds / $steps;
		for my $step (1..$steps - 1){
			sleeper($wink);
			for my $transition (@transitions){
				my ($method, $track, $vol, $from, $to) = @$transition;
				$vol->_modify_effect(
					1,
					::Effect::fade_level($from, $to, $step, $steps),
				);
			}
		}
		sleeper($wink);
	}

	for my $transition (@transitions){
		my ($method, $track, $vol, $from, $to) = @$transition;
		$vol->_modify_effect(1, $to);
		$track->set(old_vol_level => undef) if $method eq 'unmute';
	}
}

1;
__END__
