# ----------- Engine cleanup (post-recording) -----------
package ::;
use Modern::Perl;
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
	my $mixdownfile = $tn{Mixdown}->full_path;
	my $linkname = current_branch() || $project->{name};
	my $version = $tn{Mixdown}->monitor_version;
	$linkname =~ s/-branch$//;
	$linkname .= "_$version";
	my $tag_name = $linkname;
	$linkname .= '.wav';
	my $symlinkpath = join_path(project_dir(), $linkname);
	symlink $mixdownfile, $symlinkpath;
	#process_command('branch');
	tag_mixdown_commit($tag_name, $symlinkpath, $mixdownfile) if $config->{use_git};
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
	encode_mixdown_file($mixdownfile,$tag_name);
}
sub tag_mixdown_commit {
	logsub('&tag_mixdown_commit');
	my ($name, $symlinkpath, $mixdownfile) = @_;
	logpkg('debug',"tag_mixdown_commit: @_");

	my ($sym) = $symlinkpath =~ m([^/]+$);
	my ($mix) = $mixdownfile =~ m([^/]+$);

	# we want to tag the normal playback state
	mixoff('quiet');

	save_state();
	my $msg = "State for $sym ($mix)";
	git_snapshot($msg);
	git_tag($name, $msg);

	# rec_cleanup wants to audition the mixdown
	mixplay('quiet');
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
		rememoize();
		say join $/,"recorded:",@recorded;
	}
	map{ _get_wav_info($_) } @recorded;
	@recorded 
} 
1;
__END__

