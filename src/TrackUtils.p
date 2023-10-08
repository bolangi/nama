package ::;
use Modern::Perl '2020';

sub add_track {

	logsub((caller(0))[3]);
	my ($name, @params) = @_;
	my %vals = (name => $name, @params);
	my $class = $vals{class} // '::Track';
	{ no warnings 'uninitialized';	
	logpkg('debug', "name: $name, ch_r: $gui->{_chr}, ch_m: $gui->{_chm}");
	}	
	::throw("$name: track name already in use. Skipping."), return 
		if $tn{$name};
	::throw("$name: reserved track name. Skipping"), return
	 	if grep $name eq $_, @{$mastering->{track_names}}; 

	# in order to increment serially
	::ChainSetup::remove_temporary_tracks();

	my $track = $class->new(%vals);
	return if ! $track; 
	logpkg('debug', "ref new track: ", ref $track); 
	$track->source($gui->{_chr}) if $gui->{_chr};
#		$track->send($gui->{_chm}) if $gui->{_chm};

	my $bus = $bn{$track->group}; 
	$bus->set(rw => MON) unless $track->target; # not if is alias

	# normal tracks set to config->new_track_rw 
	# defaulting to MON
	# track aliases default to PLAY
	$track->set(rw => $track->{target}
					?  PLAY
					:  $config->{new_track_rw} || MON );
	$gui->{_track_name} = $gui->{_chm} = $gui->{_chr} = undef;

	set_current_bus();
	logpkg('debug', "Added new track!\n", sub{$track->dump});
	$track;
}

# create read-only track pointing at WAV files of specified
# name in current project

sub add_track_alias {
	my ($name, $track) = @_;
	my $target; 
	if 		( $tn{$track} ){ $target = $track }
	elsif	( $ti{$track} ){ $target = $ti{$track}->name }
	add_track(  $name, target => $target, width => $tn{$target}->width);
}
# create read-only track pointing at WAV files of specified
# track name in a different project

sub add_track_alias_project {
	my ($name, $track, $project_name) = @_;
	$project_name //= $::project->{name}; 
	my $dir =  join_path(project_root(), $project_name, '.wav'); 
	if ( -d $dir ){
		if ( glob "$dir/$track*.wav"){
			::pager("Found target WAV files.\n");
			my @params = (
				target => $track, 
				project => $project_name,
			);
			add_track( $name, @params );
		} else { ::throw("$project_name:$track - No WAV files found.  Skipping.\n"), return; }
	} else { 
		::throw("$project_name: project does not exist.  Skipping.\n");
		return;
	}
}
# vol/pan requirements of mastering and mixdown tracks

{ my %volpan = (
	Eq => {},
	Low => {},
	Mid => {},
	High => {},
	Boost => {vol => 1},
	Mixdown => {},
);

sub need_vol_pan {

	my ($track_name, $type) = @_;

	# $type: vol | pan
	
	# Case 1: track already exists
	
	return 1 if $tn{$track_name} and $tn{$track_name}->$type;

	# Case 2: track not yet created

	if( $volpan{$track_name} ){
		return($volpan{$track_name}{$type}	? 1 : 0 )
	}
	return 1;
}
}

# track width in words

sub width {
	my $count = shift;
	return 'mono' if $count == 1;
	return 'stereo' if $count == 2;
	return "$count channels";
}


sub add_volume_control {
	my $n = shift;
	return unless need_vol_pan($ti{$n}->name, "vol");
	
	my $vol_id = ::Effect->new(
				chain => $n, 
				type => $config->{volume_control_operator},
				id => $ti{$n}->vol, # often undefined
				)->id;
	
	$ti{$n}->set(vol => $vol_id);  # save the id for next time
	$vol_id;
}
sub add_pan_control {
	my $n = shift;
	return unless need_vol_pan($ti{$n}->name, "pan");

	my $pan_id = ::Effect->new(
				chain => $n, 
				type => 'epp',
				id => $ti{$n}->pan, # often undefined
				)->id;
	
	$ti{$n}->set(pan => $pan_id);  # save the id for next time
	$pan_id;
}
sub rename_track {
	use Cwd;
	use File::Slurp;
	my ($oldname, $newname, $statefile, $dir) = @_;
	project_snapshot();
	my $old_dir = cwd();
	chdir $dir;

	# rename audio files
	
	qx(rename 's/^$oldname(?=[_.])/$newname/' *.wav);


	# rename in State.json when candidate key
	# is part of the specified set and the value 
	# exactly matches $oldname
	
	my $state = read_file($statefile);

	$state =~ s/
		"					# open quote
		(track| 		# one of specified fields
		name| 
		group| 
		source| 
		send_id| 
		target| 
		current_edit| 
		source_id| 
		return_id| 
		wet_track| 
		dry_track| 
		track| 
		host_track)
		"				# close quote
		\ 				# space
		:				# colon
		\ 				# space
		"$oldname"/"$1" : "$newname"/gx;

	write_file($statefile, $state);
	my $msg = "Rename track $oldname -> $newname";
	project_snapshot($msg);
	::pager($msg);
	load_project(name => $::project->{name});
}
sub user_tracks_present {
	my $i = 0;
	$i++ for user_tracks();
	$i
}
sub all_tracks { sort{$a->n <=> $b->n } values %::Track::by_name }
sub audio_tracks { grep { $_->class !~ /Midi/ } all_tracks() }
sub rec_hookable_tracks { 
	grep{ $_->group ne 'Temp' and $_->group ne 'Insert' } all_tracks() 
}
sub user_tracks { grep { ! $_->is_system_track } all_tracks() }
sub system_tracks { grep { $_->is_system_track } all_tracks() }
sub this_op { $this_track and $this_track->op }
sub this_op_o { $this_track and $this_track->op and fxn($this_track->op) }
sub this_param { $this_track ? $this_track->param : ""}
sub this_stepsize { $this_track ? $this_track->stepsize : ""}
sub this_track_name { $this_track ? $this_track->name : "" }

