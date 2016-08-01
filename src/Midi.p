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

sub save_midish {
	my $fname = $file->midi_store;
	midish( qq<save "$fname">);
}

sub close_midish {
	save_midish();
	say "reaping midish";
	waitpid $pid, 0;
}	
}
1;
__END__
