# ----------- Engine cleanup (post-recording) -----------
package ::;
use Modern::Perl;
use ::Globals qw(:all);

sub rec_cleanup {  
	logsub("&rec_cleanup");
	logpkg('debug',"transport still running, can't cleanup"),return if transport_running();
	if( my (@files) = new_files_were_recorded() ){
		say join $/, "Now reviewing your recorded files...", (@files);
		(grep /Mixdown/, @files) 
			? do { command_process('mixplay');
				   symlink_branchname_to_mixdown_file()
				 }
			: post_rec_configure();
		undef $mode->{offset_run} if ! defined $this_edit;
		$mode->{midish_transport_sync} = 'play' 
			if $mode->{midish_transport_sync} eq 'record';
		reconfigure_engine();
	}
}

sub symlink_branchname_to_mixdown_file {
	return if ! $config->{use_git};
	my $oldfile = $tn{Mixdown}->full_path;
	my $name = current_branch();
	my $version = $tn{Mixdown}->monitor_version;
	$name =~ s/-branch$//;
	$name .= "_$version.wav";
	my $newfile = join_path(project_dir(), $name);
	#say("updating symlink $newfile"), unlink $newfile if -e $newfile;
	symlink $oldfile, $newfile;
	my $sha = git_sha();
	$tn{Mixdown}->add_system_version_comment($version, join " ",$name, $sha);
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
		# toggle buses of recorded tracks to MON

		map{ $_->set(rw => 'MON') } @{$setup->{_last_rec_tracks}};
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

