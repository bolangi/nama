package ::Sequence;
use v5.36;
use ::Assign qw(json_out);
use ::Log qw(logpkg);
use ::Effect  qw(fxn modify_effect);
use ::Object qw( items clip_counter );
use ::Globals qw(PLAY OFF);
our @ISA = '::SubBus';
our $VERSION = 1.0;
use SUPER;
our %by_name; # alias to %::Bus::by_name
*by_name = \%::Bus::by_name; 

sub new { 
	my ($class,%args) = @_;
	# take out args we will process
	my $items = delete $args{items};
	my $counter = delete $args{clip_counter};
	#logpkg('debug', "items: ",map{json_out($_->as_hash)}map{$::tn{$_}}@$items) if $items;
	$items //= [];
	@_ = ($class, %args);
	my $self = super();
	logpkg('debug',"new object: ", json_out($self->as_hash));
	logpkg('debug', "items: ",json_out($items));
	$self->{clip_counter} = $counter;
	$self->{items} = $items;
	$::this_sequence = $self;
	$self;
} 
sub clip {
	my ($self, $index) = @_;
	return 0 if $index <= 0;
	$::tn{$self->{items}->[$index - 1]}
}
sub rw ($self) {
	::timeline_adjustment_active() ? OFF : $self->{rw}
}
# perl indexes arrays at zero, for nama users we number items from one
sub insert_item ($self, $item, $index) {
	$self->append_item($item), return if $index == $self->{items}->@* + 1;
	$self->verify_item($index) or die "$index: sequence index out of range";
	splice $self->{items}->@*, $index - 1,0, $item->name 
}
sub verify_item {
	my ($self, $index) = @_;
	$index >= 1 and $index <= scalar $self->items->@* 
}
sub delete_item ($self, $index) {
	$self->verify_item($index) or die "$index: sequence index out of range";
	my $trackname = splice($self->{items}->@*, $index - 1, 1);
	$::tn{$trackname} and $::tn{$trackname}->remove;
}
sub append_item ($self, $item) {
	push( $self->{items}->@*, $item->name );
}
sub item ($self, $index) {
	return 0 if $index <= 0;
	$::tn{$self->{items}->[$index - 1]};
}
sub list_output ($self) {
	my $i;
	join "\n","Sequence $self->{name} clips:",
		map { join " ", 
				++$i, 
				$::tn{$_}->n,
				$_,
				sprintf("%.3f %.3f", $::tn{$_}->duration, $::tn{$_}->timeline_endpoint),
		} $self->items->@*
}
sub remove {
	my $sequence = shift;

	# delete all clips
	map{$::tn{$_}->remove } $by_name{$sequence->name}->tracks;

	# delete clip array
	delete $sequence->{items};
	
	my $mix_track = $::tn{$sequence->name};

	if ( defined $mix_track ){
	 
		$mix_track->set(rw => OFF);
	
		# remove mix track unless it has some WAV files

		$mix_track->remove unless scalar $mix_track->versions->@*;
	}

	# remove sequence from index
	
	delete $by_name{$sequence->name};
} 
sub new_clip {
	my ($self, $track, %args) = @_; # $track can be object or name
	my $markpair = delete $args{region};
	logpkg('debug',json_out($self->as_hash), json_out($track->as_hash));
	$track isa '::Track' or $track = $::tn{$track}
		or die("$track: track not found."); 
	my %region_args = (
		region_start => $markpair && $markpair->[0]->name || $track->region_start,
		region_end	 => $markpair ? ($markpair->[1] ? $markpair->[1]->name : 'END') : $track->region_end
	);
	my $clip = ::Clip->new(
		target => $track->basename,
		name => $self->unique_clip_name($track->name, $track->playback_version),
		rw => PLAY,
		group => $self->name,
		version => $track->playback_version,
		hide => 1,
		%region_args,
		%args
	);
	modify_effect( $clip->vol_id, 1, undef, fxn($track->vol_id)->params->[0]);
	modify_effect( $clip->pan_id, 1, undef, fxn($track->pan_id)->params->[0]);
	$clip
}
sub new_spacer {
	my( $self, %args ) = @_;
	my $position = delete $args{position};
	my $spacer = ::Spacer->new( 
		duration => $args{duration},
		name => $self->unique_spacer_name(),
		rw => OFF,
		group => $self->name,
	);
	$self->insert_item( $spacer, $position || ( scalar $self->{items}->@* + 1 ))
}
sub unique_clip_name {
	my ($self, $trackname, $version) = @_;
	join '-', $self->name , ++$self->{clip_counter}, $trackname, 'v'.$version;
}
sub unique_spacer_name ($self) {
	join '-', $self->name, ++$self->{clip_counter}, 'spacer';
}
package ::;

sub new_sequence {

	my %args = @_;
	my $name = $args{name};
	my @tracks = defined $args{tracks} ? $args{tracks}->@* : ();
	my $group = $args{group} || 'Main';
	my $mix_track = $tn{$name} || add_track($name, group => $group);
	return unless $mix_track;
	$mix_track->set( rw => MON,
					 source_type => 'bus',
					 source_id	 => $name,
					);
	my $sequence = ::Sequence->new(
		name => $name,
	);
;
	map{ $sequence->append_item($_) }
	map{ $sequence->new_clip($_)} @tracks;
	$this_sequence = $sequence;

}
sub compose_sequence {
	my ($sequence_name, $track, $markpairs) = @_;
	logpkg('debug',"sequence_name: $sequence_name, track:", $track->name, 
			", markpairs: ",::Dumper $markpairs);

	my $sequence = new_sequence( name => $sequence_name) or return;
	logpkg('debug',"sequence\n",::Dumper $sequence);
	my @clips = map { 
		$sequence->new_clip($track, region => $_) 
	} @$markpairs;
	map{ $sequence->append_item($_) } @clips;
	$sequence
}
# Resolve the source even after separate_clips has turned the track OFF.
sub clip_source ($track) {
	my $file = $track->targets->{$track->playback_version};
	return unless defined $file;
	join_path($track->dir, $file)
}

sub clip_definitions ($track) {
	my $source = clip_source($track);
	unless (defined $source and -f $source) {
		throw('Select a track with an audio file.');
		return;
	}
	my (%starts, %ends);
	for my $mark (::Mark::all()) {
		next unless $mark isa '::ClipMark';
		my $index = $mark->clip_index;
		my $set = $mark->clip_start ? \%starts : \%ends;
		if (exists $set->{$index}) {
			throw("Duplicate endpoint for Clip $index. No action taken.");
			return;
		}
		$set->{$index} = $mark;
	}
	unless (keys %starts) {
		throw('No clips defined. No action taken.');
		return;
	}
	for my $index (keys %ends) {
		unless ($starts{$index}) {
			throw("No start mark for Clip $index. No action taken.");
			return;
		}
	}
	my $length = wav_length($source);
	my @clips;
	for my $index (sort { $a <=> $b } keys %starts) {
		my ($start, $end) = ($starts{$index}, $ends{$index});
		my $name = "clip $index";
		$name .= ' ' . $start->clip_name if length($start->clip_name // '');
		my $endpoint = $end ? $end->time : $length;
		unless (defined $length and $start->time >= 0
			and $endpoint > $start->time and $endpoint <= $length) {
			throw("Invalid boundaries for $name. No action taken.");
			return;
		}
		push @clips, { name => $name, start => $start, end => $end };
	}
	for my $clip (@clips) {
		next if $clip->{end};
		my $label = ucfirst $clip->{name};
		unless (prompt_yn("No end mark for $label. Use end of audio file?", 'no')) {
			throw('No action taken.');
			return;
		}
	}
	return \@clips;
}

sub separate_clips {
	my $track = $this_track or do { throw('Select a track with an audio file.'); return };

	# in future put clips from 
	# track 'lecture' into Bus 'lecture-clips'
	# my $bus_name = $track->name . '-clips';

	my $clips = clip_definitions($track) or return;
	my $width = ::Util::channels(wav_format(clip_source($track)));
	unless (defined $width and $width =~ /\A[1-9][0-9]*\z/) {
		throw('Cannot detect source channel count. No action taken.');
		return;
	}
	for my $clip (@$clips) {
		return unless valid_track_name($clip->{name});
	}

	return unless confirm_clip_source($track,
		"Create separate clip tracks from source track '" . $track->name . "'?");
	my @outputs;
	# add_bus($bus_name);
	for my $clip (@$clips) {
		my %arg = ( rw => PLAY,
					target => $track->basename, 
					version => $track->playback_version, 
					group => $track->group,
					input_channels => $width,
					region_start => $clip->{start}->name,
					region_end => $clip->{end} ? $clip->{end}->name : 'END',
					);
		defined $track->project and $arg{project} = $track->project;

		my $output = add_track($clip->{name}, %arg) or return;
		push @outputs, $output->name;
	}
	$track->set(rw => OFF);
	$project->{clip_tracks} = \@outputs;
}

sub confirm_clip_source ($track, $message) {
	my @users = user_tracks();
	return 1 if @users == 1 and $users[0] == $track;
	prompt_yn($message, 'no')
}

sub join_clips ($name) {
	my $track = $this_track or do { throw('Select a track with an audio file.'); return };
	my $clips = clip_definitions($track) or return;
	return unless valid_track_name($name);
	if ($bn{$name}) {
		throw("$name: bus name already in use. No action taken.");
		return;
	}
	return unless confirm_clip_source($track,
		"Create track '$name' joining clips from source track '" . $track->name . "'?");
	my @pairs = map { [$_->{start}, $_->{end}] } @$clips;
	my $sequence = compose_sequence($name, $track, \@pairs) or return;
	$track->set(rw => OFF);
	$project->{clip_tracks} = [$name];
	return $sequence;
}

# Render the last set of clip outputs, independent of the current selection.
sub write_clips {
	my @names = ($project->{clip_tracks} // [])->@*;
	unless (@names) {
		throw('No clip output tracks. Use separate-clips or join-clips first.');
		return;
	}
	if ($this_engine->started or $setup->{cache_track_args}) {
		throw('Stop the transport before rendering clips.');
		return;
	}
	for my $name (@names) {
		unless ($tn{$name} and not $tn{$name}->candidate_off) {
			throw("$name: clip output track is missing or OFF. No action taken.");
			return;
		}
	}
	my @formats = split ' ', ($config->{mixdown_encodings} // '');
	my $encoders = encoding_plan(@formats) or return;
	my $message = "Render clip tracks: " . join(', ', @names) . "?";
	$message .= " Encode as: " . join(', ', @formats) . '.' if @formats;
	return unless prompt_yn($message, 'no');
	return render_next_clip(\@names, $encoders);
}

# Each completion starts at most one more render on the same Ecasound engine.
sub render_next_clip ($names, $encoders) {
	unless (@$names) {
		notify('Finished rendering clips.');
		return 1;
	}
	my $name = shift @$names;
	my $track = $tn{$name};
	return cache_track($track, 0, sub ($wav) {
		my $basename = $name . '_' . $track->playback_version;
		return unless encode_audio_file($wav, $basename, $encoders);
		render_next_clip($names, $encoders);
	});
}

1
__END__
