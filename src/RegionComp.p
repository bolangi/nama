### edit region computations

# Get a dispatch table for the current parameter set

sub dispatch_table {

my $edit_params = shift;

my( %playat, %region_start, %region_end);
my $table = {}; # return value

%region_start = (
    out_of_bounds_near				=> sub{ "*" },
    out_of_bounds_far				=> sub{ "*" },	

	play_start_during_playat_delay	=> sub {$edit_params->{region_start} },
	no_region_play_start_during_playat_delay => sub { 0 },

	play_start_within_region 
				=> sub {$edit_params->{region_start} + $edit_params->{edit_play_start} - $edit_params->{playat} },
	no_region_play_start_after_playat_delay
				=> sub {$edit_params->{region_start} + $edit_params->{edit_play_start} - $edit_params->{playat} },
);
map{$table->{region_start}->{$_} = $region_start{$_}} values %region_start;
%playat = (
    out_of_bounds_near				=> sub{ "*" },
    out_of_bounds_far				=> sub{ "*" },	

	play_start_during_playat_delay	=> sub{ $edit_params->{playat} - $edit_params->{edit_play_start} },
	no_region_play_start_during_playat_delay
									=> sub{ $edit_params->{playat} - $edit_params->{edit_play_start} },

	play_start_within_region   				=> sub{ 0 },
	no_region_play_start_after_playat_delay => sub{ 0 },

);
map{$table->{playat}->{$_} = $playat{$_}} values %playat;
%region_end = (
    out_of_bounds_near				=> sub{ "*" },
    out_of_bounds_far				=> sub{ "*" },	

	play_start_during_playat_delay	
		=> sub { $edit_params->{region_start} + $edit_params->{edit_play_end} - $edit_params->{playat} },
	no_region_play_start_during_playat_delay 
		=> sub {                 $edit_params->{edit_play_end} - $edit_params->{playat} },

	play_start_within_region 
		=> sub { $edit_params->{region_start} + $edit_params->{edit_play_end} - $edit_params->{playat} },
	no_region_play_start_after_playat_delay
		=> sub {                 $edit_params->{edit_play_end} - $edit_params->{playat} },
);
map{$table->{region_end}->{$_} = $region_end{$_}} values %region_end;
}

sub new_playat       { my $table = shift; $table->{playat}{edit_case()}->() };
sub new_region_start { $region_start{edit_case()}->() };
sub new_region_end   
	{   
		my $end = $region_end{edit_case()}->();
		return $end if $end eq '*';
		$end < $edit_params->{setup_length} ? $end : $edit_params->{setup_length}
	};
# the following value will always allow enough time
# to record the edit. it may be longer than the 
# actual WAV file in some cases. (I doubt that
# will be a problem.)

sub edit_case {
	my $edit_params = shift;

	# logic for no-region case
	
    if ( ! $edit_params->{region_start} and ! $edit_params->{region_end}  )
	{
		if( $edit_params->{edit_play_end} < $edit_params->{playat})
			{ "out_of_bounds_near" }
		elsif( $edit_params->{edit_play_start} > $edit_params->{playat} + $edit_params->{setup_length})
			{ "out_of_bounds_far" }
		elsif( $edit_params->{edit_play_start} >= $edit_params->{playat})
			{"no_region_play_start_after_playat_delay"}
		elsif( $edit_params->{edit_play_start} < $edit_params->{playat} and $edit_params->{edit_play_end} > $edit_params->{playat} )
			{ "no_region_play_start_during_playat_delay"}
	} 
	# logic for region present case
	
	elsif ( defined $edit_params->{region_start} and defined $edit_params->{region_end} )
	{ 
		if ( $edit_params->{edit_play_end} < $edit_params->{playat})
			{ "out_of_bounds_near" }
		elsif ( $edit_params->{edit_play_start} > $edit_params->{playat} + $edit_params->{region_end} - $edit_params->{region_start})
			{ "out_of_bounds_far" }
		elsif ( $edit_params->{edit_play_start} >= $edit_params->{playat})
			{ "play_start_within_region"}
		elsif ( $edit_params->{edit_play_start} < $edit_params->{playat} and $edit_params->{playat} < $edit_params->{edit_play_end})
			{ "play_start_during_playat_delay"}
		else {carp "$edit_params->{trackname}: fell through if-then"}
	}
	else { carp "$edit_params->{trackname}: improperly defined region" }
}

sub set_edit_vars {
	my $track = shift;
	$edit_params->{trackname}      = $track->name;
	$edit_params->{playat} 		= $track->playat_time;
	$edit_params->{region_start}   = $track->region_start_time;
	$edit_params->{region_end} 	= $track->region_end_time;
	$edit_params->{edit_play_start}= play_start_time();
	$edit_params->{edit_play_end}	= play_end_time();
	$edit_params->{setup_length} 		= wav_length($track->full_path);
}
# depends on $this_edit
sub edit_vars {
	my $track = $tn{this_edit->host_track};
	{
	trackname      	=> $track->name,
	playat 			=> $track->playat_time,
	region_start   	=> $track->region_start_time,
	region_end 		=> $track->region_end_time,
	edit_play_start => play_start_time(),
	edit_play_end	=> play_end_time(),
	setup_length 	=> wav_length($track->full_path),
	}
}


sub play_start_time {
	defined $this_edit 
		? $this_edit->play_start_time 
		: $setup->{offset_run}->{start_time} # zero unless offset run mode
}
sub play_end_time {
	defined $this_edit 
		? $this_edit->play_end_time 
		: $setup->{offset_run}->{end_time}   # undef unless offset run mode
}
sub set_edit_vars_testing {
	($edit_params->{playat}, $edit_params->{region_start}, $edit_params->{region_end}, $edit_params->{edit_play_start}, $edit_params->{edit_play_end}, $edit_params->{setup_length}) = @_;
}
}
