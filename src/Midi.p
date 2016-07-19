# ------------- MIDI routines -----------

package ::;
use Modern::Perl;
#use ::Log qw(logpkg);
use Carp;

{
my($error,$answer)=('','');
my ($pid, $sel);
my @handles = my ($fh_midi_write, $fh_midi_read, $fh_midi_error) = map{ IO::Handle->new() } 1..3;
map{ $_->autoflush(1) } @handles;

sub start_midish {
	my $executable = qx(which midish);
	chomp $executable;
	$executable or say("Midish not found!"), return;
	$pid = open3($fh_midi_write, $fh_midi_read, $fh_midi_error,"$executable -v")
		or warn "Midish failed to start!";

	$sel = IO::Select->new();
	$sel->add($fh_midi_read);
	$sel->add($fh_midi_error);
	midish( qq(print "Midish is ready.") );
}
sub start_midi_transport {
	# assuming that we have midi tracks, either REC or PLAY
	my $start_command = $bn{Midi}->midi_rec_tracks ? 'r' : 'p';
	midish($start_command);
}
sub stop_midi_transport { midish('s') }

sub midish {
	my $command = shift;
	
	print "\n";
	print "midi command: $command\n";
	print $fh_midi_write "$command\n";

	my $length = 2**16;
	sleeper(0.05);
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
			if($buf){map{say} grep{ !/\+ready/ } split "\n", $buf}
		}
	}
	print "\n";
}

sub close_midish {
	my $save_file = $file->midi_store;
	$save_file = qq("$save_file");
	say "\nsaving midish as $save_file";
	midish("save $save_file");
	sleeper(0.1);
	say "killing midish";
	kill 15, $pid;
	sleeper(0.1);
	kill 9, $pid;
}	
}
1;
__END__
