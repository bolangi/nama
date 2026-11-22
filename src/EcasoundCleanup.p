# ----------- Ecasound cleanup (post-recording) -----------
package ::EcasoundCleanup;
use Role::Tiny;
use v5.36;
our $VERSION = 1.0;
sub cleanup ($self) {
	::rec_cleanup();
}


package ::;
use v5.36;
use Path::Tiny qw(path);
use File::Spec::Functions qw(splitpath);
use ::Globals qw(:all);

sub rec_cleanup {  
	logsub((caller(0))[3]);
	logpkg('debug',"transport still running, can't cleanup"), return if $this_engine->running;
	if( my (@files) = new_files_were_recorded() )
	{
		::Waveform::generate_waveforms(@files);
		if( my @rec_tracks = ::ChainSetup::engine_wav_out_tracks() )
		{
			$project->{playback_position} = 0;
			$setup->{_last_rec_tracks} = \@rec_tracks;
			$setup->{_main_rw} = $tn{Main}->rw;
		}

		if( grep /Mixdown/, @files) { 
				mixdown_postprocessing() ;
				mixplay();
		}
		post_rec_configure() 
	}
}
sub mixdown_postprocessing {
	logsub((caller(0))[3]);
	nama_cmd('mixplay');
	my ($oldfile) = $tn{Mixdown}->full_path =~ m{([^/]+)$};
	$oldfile = join_path('.wav',$oldfile);
	my $tag_name = join '-', $project->{name}, current_branch();
	my $version = $tn{Mixdown}->playback_version;

	# simplify the tagname basename 
	# 
	# 	untitled-master        -> untitled
	#   untitled-premix-branch -> untitled-premix
	
	$tag_name =~ s/-branch$//;
	$tag_name =~ s/-master$//;
	$tag_name .= "_$version";

	delete_existing_mixdown_tag_and_convenience_encodings($tag_name);

	# create symlink in project_dir()
	
	my $newfile = "$tag_name.wav";
	logpkg('debug',"symlinking oldfile: $oldfile, newfile: $newfile");
	symlink $oldfile, path(project_dir())->child($newfile)
        or throw("symlink didn't work: $!");
	tag_mixdown_commit($tag_name, $newfile, $oldfile) if $config->{use_git};

	my $sha = git_sha(); # possibly undef
	my $encoding = $config->{mixdown_encodings};
	my $comment;
	if ($sha or $encoding){
		$comment .= "tagged " if $sha;
		$comment .= "and " if $sha and $encoding;
		$comment .= "encoded " if $encoding;
		$comment .= "as $tag_name ";
		$comment .= "(commit $sha)" if $sha;
	}
	$tn{Mixdown}->add_system_version_comment($version, $comment);
	::notify($comment);
	encode_mixdown_file(path(project_dir())->child($oldfile)->absolute, $tag_name);
}
sub tag_mixdown_commit {
	logsub((caller(0))[3]);
	my ($name, $newfile, $mixdownfile) = @_;
	logpkg('debug',"tag_mixdown_commit: @_");

	my ($sym) = $newfile =~ m([^/]+$);
	my ($mix) = $mixdownfile =~ m([^/]+$);

	# we want to tag the normal playback state
	
	local $quiet = 1;
	mixoff();

	my $msg = "State for $sym ($mix)";
	project_snapshot($msg);
	git('tag', $name, '-m', $mix);
}
sub delete_existing_mixdown_tag_and_convenience_encodings {
	logsub((caller(0))[3]);
	my $name = shift;
	logpkg('debug',"name: $name");
		git('tag', '-d', $name) if git_tag_exists($name);
		foreach( qw(mp3 ogg aac m4a opus flac wav) ){
			my $file = join_path(project_dir(),"$name.$_");
			unlink $file if -e $file;
		}
	}
# Mixdown and clip exports share encoder validation, metadata and paths.
sub encode_mixdown_file {
	my ($wav, $basename, @formats) = @_;
	@formats = split ' ', ($config->{mixdown_encodings} // '') unless @formats;
	my $plan = encoding_plan(@formats) or return;
	encode_audio_file($wav, $basename, $plan);
}
# Each plan entry contains the format, FFmpeg path, extension and codec options.
sub encoding_plan (@formats) {
	my %spec = (
		mp3  => ['mp3',  '-c:a', 'libmp3lame', '-q:a', '2'],
		ogg  => ['ogg',  '-c:a', 'libvorbis', '-q:a', '5'],
		aac  => ['aac',  '-c:a', 'aac', '-b:a', '192k'],
		alac => ['m4a',  '-c:a', 'alac'],
		opus => ['opus', '-c:a', 'libopus', '-b:a', '128k'],
		flac => ['flac', '-c:a', 'flac'],
	);
	for my $format (@formats) {
		throw("Unsupported audio encoding: $format"), return unless $spec{$format};
	}
	return [] unless @formats;
	my ($ffmpeg) = grep { -f $_ and -x $_ }
		map { path(length($_) ? $_ : '.')->child('ffmpeg')->absolute->stringify }
		split /:/, ($ENV{PATH} // ''), -1;
	throw('Cannot encode audio: ffmpeg is not installed.'), return unless $ffmpeg;
	my %seen;
	return [map { [$_, $ffmpeg, $spec{$_}->@*] } grep { !$seen{$_}++ } @formats];
}
sub encode_audio_file ($wav, $basename, $plan) {
	return 1 unless @$plan;
	throw('Cannot encode: rendered WAV is missing or empty.'), return
		unless defined $wav and -s $wav;
	require POSIX;
	my $artist = $project->{artist} || getpwuid($<) || '';
	my $title = $project->{name};
	my $date = POSIX::strftime('%Y-%m-%d', localtime);
	my $input = path($wav)->absolute->stringify;
	for my $encoder (@$plan) {
		my ($format, $ffmpeg, $extension, @options) = @$encoder;
		my $output = path(project_dir())->child("$basename.$extension")->absolute->stringify;
		notify("Encoding $basename as $format");
		my @command = ($ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin',
			'-y', '-i', $input, '-map', '0:a:0', '-vn',
			'-metadata', "artist=$artist", '-metadata', "title=$title",
			'-metadata', "date=$date", @options, $output);
		throw("Failed to encode $output"), return if system(@command) != 0;
	}
	return 1;
}

sub adjust_offset_recordings {
	for( ::ChainSetup::engine_wav_out_tracks()){
		no warnings 'uninitialized';
		if (my $mark = offset_run_positioning_mark()){
			$_->set(playat => $mark);
			logpkg('debug',$_->name, ": offsetting to $mark");
		}
	}
}
sub post_rec_configure {

		$ui->global_version_buttons(); # recreate
		adjust_offset_recordings();
		$tn{Main}->set(rw => MON);

		# toggle recorded tracks to PLAY for auditioning
		
		map{ $_->set(rw => PLAY) } $setup->{_last_rec_tracks}->@*;
		
		clear_timeline_adjustment() if is_offset_run_mode();
		$ui->refresh();
		request_setup();
		reconfigure_engine();
}
sub new_files_were_recorded {
 	return unless my @files = ::ChainSetup::really_recording();
	logpkg('debug',join $/, "intended recordings:", @files);
	my @recorded =
		grep { 	my ($name, $version) = /([^\/]+)_(\d+).wav$/;
				if (-e ) {
					if (-s  > 44100) { # 0.5s x 16 bits x 44100/s
						logpkg('debug',"File size >44100 bytes: $_");
						$tn{$name}->set(version => $version) if $tn{$name};
						$ui->update_version_button($tn{$name}->n, $version);
					1;
					}
					else { unlink $_; 0 }
				}
		} @files;
	if(@recorded){
		refresh_wav_cache();
		::notify(join " ", "recorded:", map{ filename($_) } @recorded);
	}
	map{ _get_wav_info($_) } @recorded;
	@recorded 
} 
sub filename {
	my $path = shift;
	my(undef, undef, $name) = splitpath($path);
	$name
}
1;
__END__
