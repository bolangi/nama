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
		region_end	 => $markpair && $markpair->[1]->name || $track->region_end
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

	my $sequence = new_sequence( name => $sequence_name);
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
		notify('Select a track with an audio file.');
		return;
	}
	my (%starts, %ends);
	for my $mark (::Mark::all()) {
		next unless $mark isa '::ClipMark';
		my $index = $mark->clip_index;
		my $set = $mark->clip_start ? \%starts : \%ends;
		if (exists $set->{$index}) {
			notify("Duplicate endpoint for Clip $index. No action taken.");
			return;
		}
		$set->{$index} = $mark;
	}
	unless (keys %starts) {
		notify('No clips defined. No action taken.');
		return;
	}
	for my $index (keys %ends) {
		unless ($starts{$index}) {
			notify("No start mark for Clip $index. No action taken.");
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
			notify("Invalid boundaries for $name. No action taken.");
			return;
		}
		push @clips, { name => $name, start => $start, end => $end };
	}
	for my $clip (@clips) {
		next if $clip->{end};
		my $label = ucfirst $clip->{name};
		unless (prompt_yn("No end mark for $label. Use end of audio file?", 'no')) {
			notify('No action taken.');
			return;
		}
	}
	return \@clips;
}

sub separate_clips {
	my $track = $this_track or return;

	# in future put clips from 
	# track 'lecture' into Bus 'lecture-clips'
	# my $bus_name = $track->name . '-clips';

	my $clips = clip_definitions($track) or return;
	for my $clip (@$clips) {
		if ($tn{$clip->{name}}) {
			notify("$clip->{name}: track name already in use. No action taken.");
			return;
		}
	}

	# add_bus($bus_name);
	for my $clip (@$clips) {
		my %arg = ( rw => PLAY,
					target => $track->basename, 
					version => $track->playback_version, 
					group => $track->group,
					width => $track->width,
					region_start => $clip->{start}->name,
					region_end => $clip->{end} ? $clip->{end}->name : 'END',
					);
		defined $track->project and $arg{project} = $track->project;

		add_track($clip->name, %arg)
	}
	$track->set(rw => OFF);
	request_setup();
}

sub write_clips {
	my $track = $this_track or return;
	my $clips = clip_definitions($track) or return;
	my $source = clip_source($track);
	my $length = wav_length($source);
	my $format = wav_format($source);
	my @exports;
	for my $clip (@$clips) {
		my $name = $clip->{name};
		if ($name =~ m{[/\\\x00]}) {
			notify("$name: invalid WAV filename. No action taken.");
			return;
		}
		my $output = join_path(this_wav_dir(), "$name.wav");
		if ($output eq $source) {
			notify('Cannot overwrite the source audio. No action taken.');
			return;
		}
		push @exports, [$clip, $output];
	}
	for my $export (@exports) {
		my ($clip, $output) = @$export;
		my $start = $clip->{start}->time;
		my $end = $clip->{end} ? $clip->{end}->time : $length;
		require File::Temp;
		my ($fh, $temporary) = File::Temp::tempfile('clip-XXXXXX',
			DIR => this_wav_dir(), SUFFIX => '.wav', UNLINK => 0);
		close $fh;
		my $status = system('ecasound', '-q', '-b:1024',
			'-i:select,' . $start . ',' . ($end - $start) . ',' . $source,
			"-f:$format", "-o:$temporary");
		if ($status != 0 or ! -s $temporary) {
			unlink $temporary;
			notify("Failed to write $output.");
			return;
		}
		unless (rename $temporary, $output) {
			my $error = $!;
			unlink $temporary;
			notify("Cannot replace $output: $error");
			return;
		}
		notify("Wrote $output");
	}
}
1
__END__
