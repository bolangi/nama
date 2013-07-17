# ------------- MIDI routines -----------

package ::;
use Modern::Perl;
use Carp;

{

my($error,$answer)=('','');
my ($pid, $sel);

sub start_midish {
	my $executable = qx(which midish);
	chomp $executable;
	$executable or say("Midish not found!"), return;
	$pid = open3(\*MIDISH_WRITE, \*MIDISH_READ,\*MIDISH_ERROR,"$executable -v")
		or warn "Midish failed to start!";

	$sel = new IO::Select();

	$sel->add(\*MIDISH_READ);
	$sel->add(\*MIDISH_ERROR);
	midish_command( qq(print "Welcome to Nama/Midish!"\n) );
}
sub start_midish_transport {
	my $sync = $mode->{midish_transport_sync};
	my $start_command;
	$start_command = 'p' if $sync eq 'play';
	$start_command = 'r' if $sync eq 'record';
	defined $start_command 
		or die "$mode->{midish_transport_sync}: illegal midish_transport_sync mode";
	midish_command($start_command);
}
sub stop_midish_transport { midish_command('s') }

sub midish_command {
	my $query = shift;
	print "\n";
	#$config->{use_midish} or say( qq($query: cannot execute Midish command 
#unless you set "midish_enable: 1" in .namarc)), return;
	#$query eq 'exit' and say("Will exit Midish on closing Nama."), return;

	#send query to midish
	print MIDISH_WRITE "$query\n";

	foreach my $h ($sel->can_read)
	{
		my $buf = '';
		if ($h eq \*MIDISH_ERROR)
		{
			sysread(MIDISH_ERROR,$buf,4096);
			if($buf){print "MIDISH ERR-> $buf\n"}
		}
		else
		{
			sysread(MIDISH_READ,$buf,4096);
			if($buf){map{say} grep{ !/\+ready/ } split "\n", $buf}
		}
	}
	print "\n";
}

sub close_midish {
	my $save_file = join_path(project_dir(), "$project->{name}.msh");
	say "saving midish as $save_file";
	midish_command("save $save_file");
	#sleeper(0.2);
	#say "exiting midish";
#	midish_command("exit;"); # isn't necessary, triggers a warning 
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
