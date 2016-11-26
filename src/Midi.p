# ------------- MIDI routines -----------

package ::;
use Modern::Perl;
#use ::Log qw(logpkg);
use Carp;

{
my $midi_rec_buf = 'midi_record_buffer'; # a midish track that is the target for all recording
my ($pid, $sel);
my @handles = my ($fh_midi_write, $fh_midi_read, $fh_midi_error) = map{ IO::Handle->new() } 1..3;
map{ $_->autoflush(1) } @handles;

sub start_midish {
	logsub('&start_midish');
	my $executable = qx(which midish);
	chomp $executable;
	$executable or say("Midish not found!"), return;
	$pid = open3($fh_midi_write, $fh_midi_read, $fh_midi_error,"$executable -v")
		or warn "Midish failed to start!";

	$sel = IO::Select->new();
	$sel->add($fh_midi_read);
	$sel->add($fh_midi_error);
	midish( qq(print "Midish is ready.") );
	write_aux_midi_commands();
	midish( q(exec ").$file->aux_midi_commands.q(") );
}
sub midish {
	my $command = shift;
	return unless $config->{use_midi};
	
	print $fh_midi_write "$command\n";

	my $length = 2**16;
	sleeper(0.05);
	my @result;
	foreach my $h ($sel->can_read) 
	{
		my $buf = '';
		if ($h eq $fh_midi_error)
		{
			sysread($fh_midi_error,$buf,$length);
			if($buf){print "MIDISH ERR-> $buf\n"}
		}
		else
		{
			sysread($fh_midi_read,$buf,$length);
			if($buf){push @result, grep{ !/\+ready/ } split "\n", $buf}
		}
	}
	join "\n", @result;
}

sub close_midish {
	save_midish();
	say "reaping midish";
	kill_and_reap($pid);
}	
sub save_midish {
	my $fname = $file->midi_store;
	midish( qq<save "$fname">);
}

sub reconfigure_midi {
	my $midi_rec = $tn{$midi_rec_buf};
	my @all = $bn{Midi}->track_o;
	map{ $_->mute } @all;
	my @audible = grep{ $_->mon or $_->play } @all;
	map{ $_->unmute } @audible;
	# unset filters
	map{ $_->select; midish("fdel $_->name") } @all;
	# set filters for PLAY and MON tracks
	map{ $_->select; midish(join ' ', 'rnew', $_->source_id, $_->send_id) } @audible;
	my @rec = $bn{Midi}->midi_rec_tracks;
	return unless @rec;
 	throw("more than one midi REC track ", join " ", map{$_->name} @rec),
		return if @rec > 1;
	$rec[0]->mute; 	
	$midi_rec->select;
	$midi_rec->set(rw => REC);
	midish("fdel ".$midi_rec->name);
	my $i;
	# use routing of target track on $midi_rec track
	for (@rec)
	{
		# run rnew for first time
		my $cmd = $i ? 'radd' : 'rnew';
		$cmd = join ' ', $cmd, $_->source_id, $_->send_id;
		midish($cmd);
		$i++;
	}
}
sub start_midi_transport {
	my $start_command = $bn{Midi}->midi_rec_tracks ? 'r' : 'p';
	midish($start_command);
	$setup->{midish_running}++;
}
sub stop_midi_transport {
	return unless midish_running();
	midish('s'); 
	delete $setup->{midish_running};
	my $current_track = $this_track;
	# TODO set position at ecasound stop position
	my $length = midish('print [mend]');
	sync_transport_position(); # TODO move after ecasound stops
	return unless $bn{Midi}->midi_rec_tracks and $length > 0; 
	for my $track ($bn{Midi}->midi_rec_tracks)
	{
		$track->select;
		$track->set(rw => PLAY);
		push @{$track->{midi_versions}}, $track->current_version;
		# save project
		my $cmd = join ' ', 'chdup', $midi_rec_buf, $track->source_id, $track->current_midi;
		say "cmd: $cmd";
		midish($cmd);
		midish("clr $midi_rec_buf $length");
		# save project
	}
}
}
sub write_aux_midi_commands {
	write_file($file->aux_midi_commands,  get_data_section('aux_midi_commands'))
		unless -e $file->aux_midi_commands
}
	
=comment
chdup aux_recorder dx7 piano 
		
tnew synth                                                                                               
rnew nord nord # play the nord keyboard sound with the nord keyboard                                     
tnew piano                                                                                               
rnew tr dx7 # route the tr keyboard to the dx7 synth sound engine                                        
tnew aux_recorder                                                                                        
rnew nord nord                                                                                           
radd tr dx7 # not sure if this works, must recheck my code                                               
r                                                                                                        
s                                                                                                        

let complete_length = [mend];                                                                            
2. clear the auxiliary track                                                                             
clr aux_recorder $complete_length  
=cut
1;
__END__
