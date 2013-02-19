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
			command_process('mixplay');
			mixdown_symlinking_tagging_encoding();
		}
		else { post_rec_configure() }
		undef $mode->{offset_run} if ! defined $this_edit;
		$mode->{midish_transport_sync} = 'play' 
			if $mode->{midish_transport_sync} eq 'record';
		reconfigure_engine();
	}
}

sub mixdown_symlinking_tagging_encoding {
	return if ! $config->{use_git};
	my $mixdownfile = $tn{Mixdown}->full_path;
	my $name = current_branch();
	my $version = $tn{Mixdown}->monitor_version;
	$name =~ s/-branch$//;
	$name .= "_$version";
	my $tag_name = $name;
	$name .= '.wav';
	my $symlinkpath = join_path(project_dir(), $name);
	symlink $mixdownfile, $symlinkpath;

	# tag the commit with the basename for the symlinked or
	# encoded files
					
	# we want to tag the playback mode just before
	# the mixdown command was given.
	# we tag it during cleanup so we are
	# sure that something happened.

	command_process('mixoff');
	save_state();
	my $msg = "Settings corresponding to $symlinkpath (".$tn{Mixdown}->full_path. ")";
	git_snapshot($msg);
	git_tag($tag_name, $msg);
	command_process('mixplay');

	# TODO announce also
	# will be linked for convenience to initial_mix_2.wav
	# in the project_dir()
	# will be encoded as initial_mix_2.mp3
	#
					

	my $sha = git_sha();
	$tn{Mixdown}->add_system_version_comment($version, join " ",$name, $sha);
	
	encode_mixdown_file($mixdownfile,$symlinkpath);
}
sub encode_mixdown_file {
	state $shell_encode_command = {
		mp3 => q(lame -h --ta "$artist" --ty $year --tt "$title" $input_file $output_file),
		ogg => q(oggenc -o $output_file -a "$artist" -t "$title" -d "$date" $input_file)
	};	
	my($mixdownfile, $tag_name, @formats) = @_;
	@formats or @formats = qw(ogg mp3);  # @{$config->{mixdown_encodings}};
	my $artist = $project->{artist} || qx(whoami);
	my $title = $project->{name};
	my $date = qx(date);
	chomp($date, $artist);
	my ($year) = $date =~ /(\d{4})$/;
	my $input_file = $mixdownfile;
	for my $format( @formats ){
		my $output_file = join_path(project_dir(),"$tag_name.$format");
		say "artist $artist, title $title, date $date, year $year, input file $input_file, output file $output_file";
		say eval qq(qq($shell_encode_command->{$format}));
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

