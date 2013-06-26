# ----------- Engine cleanup (post-recording) -----------
package ::;
use Modern::Perl;
use Cwd;
use ::Globals qw(:all);

sub rec_cleanup {  
	logsub("&rec_cleanup");
	logpkg('debug',"transport still running, can't cleanup"),return if transport_running();
	if( my (@files) = new_files_were_recorded() ){
		say join $/, "Now reviewing your recorded files...", (@files);
		if( grep /Mixdown/, @files){
			mixdown_postprocessing();
		}
		else { post_rec_configure() }
		reconfigure_engine();
	}
}

sub mixdown_postprocessing {
	logsub("&mixdown_postprocessing");
	process_command('mixplay');
	my ($oldfile) = $tn{Mixdown}->full_path =~ m{([^/]+)$};
	$oldfile = join_path('.wav',$oldfile);
	my $tag_name = join '-', $project->{name}, current_branch();
	my $version = $tn{Mixdown}->monitor_version;

	# simplify the tagname basename 
	# 
	# 	untitled-master        -> untitled
	#   untitled-premix-branch -> untitled-premix
	
	$tag_name =~ s/-branch$//;
	$tag_name =~ s/-master$//;
	$tag_name .= "_$version";

	delete_existing_mixdown_tag_and_convenience_encodings($tag_name);

	# create symlink in project_dir()
	
	my $was_in = getcwd;
	chdir project_dir() or die "couldn't chdir: $!";
	my $newfile = "$tag_name.wav";
	logpkg('debug',"symlinking oldfile: $oldfile, newfile: $newfile");
	symlink $oldfile, $newfile or say "symlink didn't work: $!";
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
	pager3($comment);	
	encode_mixdown_file($oldfile,$tag_name);
	chdir $was_in;
}
sub tag_mixdown_commit {
	logsub('&tag_mixdown_commit');
	my ($name, $newfile, $mixdownfile) = @_;
	logpkg('debug',"tag_mixdown_commit: @_");

	my ($sym) = $newfile =~ m([^/]+$);
	my ($mix) = $mixdownfile =~ m([^/]+$);

	# we want to tag the normal playback state
	mixoff('quiet');

	save_state();
	my $msg = "State for $sym ($mix)";
	git_snapshot($msg);
	git('tag', $name, '-m', $mix);

	# rec_cleanup wants to audition the mixdown
	mixplay('quiet');
}
sub delete_existing_mixdown_tag_and_convenience_encodings {
	logsub('&delete_existing_mixdown_tag_and_convenience_encodings');
	my $name = shift;
	logpkg('debug',"name: $name");
		git('tag', '-d', $name);
		foreach( qw(mp3 ogg wav) ){
			my $file = join_path(project_dir(),"$name.$_");
			unlink $file if -e $file;
		}
	}
sub encode_mixdown_file {
	state $shell_encode_command = {
		mp3 => q(lame -h --ta "$artist" --ty $year --tt "$title" $input_file $output_file),
		ogg => q(oggenc -o $output_file -a "$artist" -t "$title" -d "$date" $input_file)
	};	
	my($mixdownfile, $tag_name, @formats) = @_;
	@formats or @formats = split " ", $config->{mixdown_encodings};
	logpkg('debug',"formats: @formats");
	my $artist = $project->{artist} || qx(whoami);
	my $title = $project->{name};
	my $date = qx(date);
	chomp($date, $artist);
	my ($year) = $date =~ /(\d{4})$/;
	my $input_file = $mixdownfile;
	for my $format( @formats ){
		my $output_file = join_path(project_dir(),"$tag_name.$format");
		logpkg('debug',"artist $artist, title $title, date $date, year $year, input file $input_file, output file $output_file");
		my $cmd = eval qq(qq($shell_encode_command->{$format}));
		logpkg('debug',"Mixdown encoding command:\n$cmd");
		system $cmd; 
	}

}
		
sub adjust_offset_recordings {
	map {
		$_->set(playat => $setup->{offset_run}->{mark});
		say $_->name, ": offsetting to $setup->{offset_run}->{mark}";
	} ::ChainSetup::engine_wav_out_tracks();
}
sub post_rec_configure {

		$ui->global_version_buttons(); # recreate
		adjust_offset_recordings();

		# toggle recorded tracks to MON for auditioning
		
		map{ $_->set(rw => 'MON') } @{$setup->{_last_rec_tracks}};
		
		undef $mode->{offset_run} if ! defined $this_edit;
		$mode->{midish_transport_sync} = 'play' 
			if $mode->{midish_transport_sync} eq 'record';

		$ui->refresh();
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
		restart_wav_memoize();
		say join $/,"recorded:",@recorded;
	}
	map{ _get_wav_info($_) } @recorded;
	@recorded 
} 
1;
__END__

