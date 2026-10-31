package ::;
use v5.36;
use Path::Tiny qw(path);

# Validate new names here so GUI, grammar and programmatic creation agree.
# Restoring existing objects deliberately does not pass through this routine.
sub valid_track_name ($name) {
    my $error;
    if (!defined $name || $name !~ /^[A-Za-z]/) {
        $error = 'needs to start with a letter';
    } elsif ($name =~ /:/) {
        $error = 'cannot contain a colon';
    } elsif ($tn{$name}) {
        $error = 'already exists';
    } elsif (grep { $name eq $_ } ($mastering->{track_names} // [])->@*) {
        $error = 'is reserved for mastering';
    } else {
        my $keyword = $name =~ s/-/_/gr;
        my %reserved = map { $_ => 1 } qw(nama midi rtm rtmidi rmd);
        for my $table ($text->{commands}, $text->{rtmidi_commands}) {
            next unless $table;
            for my $command (keys %$table) {
                $reserved{$command =~ s/-/_/gr} = 1;
                for my $short (split ' ', ($table->{$command}->{short} // '')) {
                    $reserved{$short =~ s/-/_/gr} = 1;
                }
            }
        }
        $error = 'conflicts with a command, shortcut or mode prefix'
            if $reserved{$keyword}
                || ($text->{command_shortcuts} // {})->{$keyword}
                || ($text->{midi_command_names} // {})->{$name}
                || ($text->{midi_command_names} // {})->{$keyword}
                || ($text->{iam} // {})->{$name}
                || ($text->{user_command} // {})->{$name};
    }
    if ($error) {
        ::throw('Track name "' . ($name // '') . '" ' . $error . '.');
        return;
    }
    return 1;
}

sub add_track {

	logsub((caller(0))[3]);
	my ($name, @params) = @_;
	my %vals = (name => $name, @params);
	return unless valid_track_name($vals{name});
	my $class = $vals{class} // '::Track';
	my $rw = $vals{rw};
	{ no warnings 'uninitialized';	
	logpkg('debug', "name: $name, ch_r: $gui->{_chr}, ch_m: $gui->{_chm}");
	}	

	# in order to increment serially
	::ChainSetup::remove_temporary_tracks();

	my $track = $class->new(%vals);
	return if ! $track; 
	logpkg('debug', "ref new track: ", ref $track); 
	$track->source($gui->{_chr}) if $gui->{_chr};
#		$track->send($gui->{_chm}) if $gui->{_chm};

	# normal tracks set to config->new_track_rw 
	# defaulting to MON
	# track aliases default to PLAY
	$track->set(rw => defined $rw
					?  $rw
					:  $track->{target}
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
	my ($project_name, $track, $name)  = @_;
	$project_name //= $::project->{name}; 
	my $dir =  join_path(project_root(), $project_name, '.wav'); 
	if ( -d $dir ){
		my @wavs = File::Find::Rule->file()->name("$track*.wav")->in($dir);
		if (@wavs){
			::notify("Found target WAV files.\n");
			::Waveform::generate_waveforms(@wavs);
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
				id => $ti{$n}->vol_id, # often undefined
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
				id => $ti{$n}->pan_id, # often undefined
				)->id;
	
	$ti{$n}->set(pan => $pan_id);  # save the id for next time
	$pan_id;
}
sub rename_track ($oldname, $newname, $statefile, $dir) {
    return unless valid_track_name($newname);
    if (grep { !defined $_ || m{[/\\\x00]} } ($oldname, $newname)) {
        throw('Track names must not contain path separators or NUL.');
        return;
    }
    my (@moves, @moved, $original_state, $state_path);
    my $ok = eval {
        my $wav_dir = path($dir)->absolute;
        $state_path = path($statefile)->absolute;
        die "Audio directory does not exist: $wav_dir\n" unless $wav_dir->is_dir;
        for my $source ($wav_dir->children) {
            my $name = $source->basename;
            next unless $name =~ /\A\Q$oldname\E(?=[_.]).*\.wav\z/
                || $name eq "$oldname.wav";
            next unless $source->is_file || -l $source;
            substr($name, 0, length $oldname, $newname);
            my $destination = $wav_dir->child($name);
            die "Destination already exists: $destination\n"
                if $destination->exists || -l $destination;
            push @moves, [$source, $destination];
        }
        project_snapshot();
        $original_state = $state_path->slurp_utf8;
        my $state = json_in($original_state);
        rename_track_state_references($state, $oldname, $newname);
        my $updated_state = json_out($state);
        for my $move (@moves) {
            my ($source, $destination) = @$move;
            # Path::Tiny::move can overwrite; check again immediately before use.
            die "Destination already exists: $destination\n"
                if $destination->exists || -l $destination;
            $source->move($destination);
            push @moved, $move;
        }
        $state_path->spew_utf8($updated_state);
        1;
    };
    unless ($ok) {
        my $error = $@;
        for my $move (reverse @moved) {
            my ($source, $destination) = @$move;
            eval {
                die "Original path is occupied: $source\n" if $source->exists || -l $source;
                $destination->move($source);
            } or $error .= "Rollback failed: $@";
        }
        throw("Cannot rename track $oldname to $newname: $error");
        return;
    }
    # Load the edited state before saving another snapshot of in-memory data.
    load_project(name => $project->{name});
    my $msg = "Rename track $oldname -> $newname";
    project_snapshot($msg);
    notify($msg);
    return 1;
}

sub rename_track_state_references ($node, $oldname, $newname) {
    if (ref $node eq 'ARRAY') {
        rename_track_state_references($_, $oldname, $newname) for @$node;
    } elsif (ref $node eq 'HASH') {
        my %fields = map { $_ => 1 } qw(
            track name group source send_id target current_edit source_id
            return_id wet_track dry_track host_track
        );
        for my $key (keys %$node) {
            if ($fields{$key} && defined $node->{$key} && !ref $node->{$key}
                    && $node->{$key} eq $oldname) {
                $node->{$key} = $newname;
            } else {
                rename_track_state_references($node->{$key}, $oldname, $newname);
            }
        }
    }
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
sub this_op_id { $this_track and $this_track->op }
sub this_effect { $this_track and $this_track->op and fxn($this_track->op) }
sub this_param { $this_track ? $this_track->param : ""}
sub this_stepsize { $this_track ? $this_track->stepsize : ""}
sub this_track_name { $this_track ? $this_track->name : "" }
