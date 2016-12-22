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

sub start_midish_process {
	logsub('&start_midish_process');
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
	$pid
}
sub midish {
	my $command = shift;
	logsub('&midish');
	return unless $config->{use_midi};
	
	print $fh_midi_write "$command\n";
	say "applied midish command: $command";
	$project->{midi_history} //=[];
	push  @{ $project->{midi_history} },$command;

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
	# Make sure we have recording track
	
	# TODO XXX this conditional will cause future tests for MIDI-related code to break 
	add_midi_track($midi_rec_buf, hide => 1) 
		if midi_tracks()
		and not $tn{$midi_rec_buf} 
		and not $config->{opts}->{T};  

	my $midi_rec = $tn{$midi_rec_buf};

	# mute all

	my @all = $bn{Midi}->track_o;
	$_->mute for @all;

	# unmute audible

	my @audible = grep{ $_->mon or $_->play } @all;
	$_->unmute for @audible;

	# unset filters

	do { $_->select_track; midish("fdel ".$_->name) } for @all;

	# set filters for PLAY and MON tracks

	do { $_->select_track; midish(join ' ', 'rnew', $_->source_id, $_->send_id) } for @audible;

	my ($rec) = my @rec = $bn{Midi}->midi_rec_tracks;

	# maybe we're done?
	
	return unless @rec;
 	throw("more than one midi REC track ", join " ", map{$_->name} @rec),
		return if @rec > 1;

	# mute the actual track since we'll record using the special-purpose track
	
	$rec->mute; 	
	$midi_rec->select_track;

	# use routing of target track on $midi_rec track

	my $cmd = 'rnew';
	$cmd = join ' ', $cmd, $rec->source_id, $rec->send_id;
	midish($cmd);
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
}
sub midi_rec_cleanup {
	my $length = midish('print [mend]');
	return unless $bn{Midi}->midi_rec_tracks and $length > 0; 
	my ($track) = $bn{Midi}->midi_rec_tracks; # first and only
		$track->select_track;
		$track->set(rw => PLAY);
		my $version = $track->current_version;
		push @{$track->{midi_versions}}, $version;
		$track->set_version($version);
		my $cmd = join ' ', 'chdup', $midi_rec_buf, $track->source_id, $track->current_midi;
		say "cmd: $cmd";
		midish($cmd);
		midish("clr $midi_rec_buf $length");
		save_midish();
}
}
sub write_aux_midi_commands {
	write_file($file->aux_midi_commands,  get_data_section('aux_midi_commands'))
		unless -e $file->aux_midi_commands
}
sub add_midi_track {
	my ($name, @args) = @_;
	my $track = ::add_track( 
		$name, 
		class => '::MidiTrack',
		group => 'Midi', 
		source_id => 'midi', 
		source_type => 'midi',
		midi_versions => [],
		novol => 1,
		engine_group => $config->{midi_engine_name},
		nopan => 1,
		@args,
	);
}
sub midi_tracks { grep { $_->class =~ /Midi/ } all_tracks() }

	
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
