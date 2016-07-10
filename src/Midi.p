# ------------- MIDI routines -----------

package ::;
use Modern::Perl;
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
	midi_command( qq(print "Midish is ready.") );
}
sub start_midi_transport {
	my $sync = $mode->{midi_transport_sync};
	my $start_command;
	$start_command = 'p' if $sync eq PLAY;
	$start_command = 'r' if $sync eq REC;
	defined $start_command 
		or die "$mode->{midi_transport_sync}: illegal midi_transport_sync mode";
	midi_command($start_command);
}
sub stop_midi_transport { midi_command('s') }

sub midi_command {
	my $query = shift;
	print "\n";
	#$config->{use_midi} or say( qq($query: cannot execute Midish command 
#unless you set "midi_enable: 1" in .namarc)), return;
	#$query eq 'exit' and say("Will exit Midish on closing Nama."), return;

	#send query to midish
	print $fh_midi_write "$query\n";

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
	my $save_file = join_path(project_dir(), "$project->{name}.msh");
	say "saving midish as $save_file";
	midi_command("save $save_file");
	#my $fh;
	#$_->close for $fh_midi_read, $fh_midi_write, $fh_midi_error;
	#sleeper(0.2);
	#say "exiting midish";
	#midi_command("exit"); # isn't necessary, triggers a warning 
	#$_->flush for @handles; # doesn't help warning
# 	sleeper(0.1);
# 	kill 15,$pid;
# 	sleeper(0.1);
# 	kill 9,$pid;
# 	sleeper(0.1);
# 	waitpid($pid, 1);
# It is important to waitpid on your child process,  
# otherwise zombies could be created. 
}	
}
1;
__END__
