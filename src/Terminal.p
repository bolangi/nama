# ----------- Terminal related subroutines ---------

package ::;
use Modern::Perl;
no warnings 'uninitialized';
use Carp;
our (
[% qx(cat ./singletons.pl) %]
	$term,
	$attribs,
	$this_bus,
	$this_track,
	%event_id,
	$debug,
	$debug2,
	%effect_j,
	$press_space_to_start_transport,
	$use_pager,
	$previous_text_command,
	@keywords,
	%commands,
	%iam_cmd,
	%midish_command,
	$midish_enable,
);


sub issue_first_prompt {
	$term->stuff_char(10); # necessary to respond to Ctrl-C at first prompt 
	&{$attribs->{'callback_read_char'}}();
	set_current_bus();
	print prompt();
	$attribs->{already_prompted} = 0;
}

sub initialize_terminal {
	$term = new Term::ReadLine("Ecasound/Nama");
	$attribs = $term->Attribs;
	$attribs->{attempted_completion_function} = \&complete;
	$attribs->{already_prompted} = 1;
	detect_spacebar(); # if $press_space_to_start_transport;

	revise_prompt();
	# handle Control-C from terminal

	$SIG{INT} = \&cleanup_exit;
	$SIG{USR1} = sub { save_state() };
	#$event_id{sigint} = AE::signal('INT', \&cleanup_exit);

}
{my $override;
sub revise_prompt {
	# hack to allow suppressing prompt
	$override = $_[0] eq "default" ? undef : $_[0] if defined $_[0];
    $term->callback_handler_install($override//prompt(), \&process_line);
}
}
sub prompt {
	"nama [". ($this_bus eq 'Main' ? '': "$this_bus/").  
		($this_track ? $this_track->name : '') . "] ('h' for help)> "
}
sub check_for_spacebar_hit {
	$event_id{stdin} = AE::io(*STDIN, 0, sub {
		&{$attribs->{'callback_read_char'}}();
		if ( $attribs->{line_buffer} eq " " ){

			toggle_transport();	
			$attribs->{line_buffer} = q();
			$attribs->{point} 		= 0;
			$attribs->{end}   		= 0;
			$term->stuff_char(10);
			&{$attribs->{'callback_read_char'}}();
		}
	});
}
sub detect_spacebar {
	$event_id{stdin} = undef; # clean up after get_edit_mark()
	check_for_spacebar_hit() if $press_space_to_start_transport;
}

sub pager {
	$debug2 and print "&pager\n";
	my @output = @_;
	my ($screen_lines, $columns) = $term->get_screen_size();
	my $line_count = 0;
	map{ $line_count += $_ =~ tr(\n)(\n) } @output;
	if ( $use_pager and $line_count > $screen_lines - 2) { 
		my $fh = File::Temp->new();
		my $fname = $fh->filename;
		print $fh @output;
		file_pager($fname);
	} else {
		print @output;
	}
	print "\n\n";
}
sub file_pager {
	$debug2 and print "&file_pager\n";
	my $fname = shift;
	if (! -e $fname or ! -r $fname ){
		carp "file not found or not readable: $fname\n" ;
		return;
    }
	my $pager = $ENV{PAGER} || "/usr/bin/less";
	my $cmd = qq($pager $fname); 
	system $cmd;
}

1;
# command line processing routines

sub get_ecasound_iam_keywords {

	my %reserved = map{ $_,1 } qw(  forward
									fw
									getpos
									h
									help
									rewind
									quit
									q
									rw
									s
									setpos
									start
									stop
									t
									?	);
	
	local $debug = 0;
	%iam_cmd = map{$_,1 } 
				grep{ ! $reserved{$_} } split /[\s,]/, eval_iam('int-cmd-list');
}

sub process_line {
	$debug2 and print "&process_line\n";
	my ($user_input) = @_;
	$debug and print "user input: $user_input\n";
	if (defined $user_input and $user_input !~ /^\s*$/) {
		$term->addhistory($user_input) 
			unless $user_input eq $previous_text_command;
		$previous_text_command = $user_input;
		command_process( $user_input );
		reconfigure_engine();
		revise_prompt();
	}
}
sub load_keywords {
	@keywords = keys %commands;
	push @keywords, grep{$_} map{split " ", $commands{$_}->{short}} @keywords;
	push @keywords, keys %iam_cmd;
	push @keywords, keys %effect_j;
	push @keywords, keys %midish_command if $midish_enable;
	push @keywords, "Audio::Nama::";
}

sub complete {
    my ($text, $line, $start, $end) = @_;
#	print join $/, $text, $line, $start, $end, $/;
    return $term->completion_matches($text,\&keyword);
};

{ 	my $i;
sub keyword {
        my ($text, $state) = @_;
        return unless $text;
        if($state) {
            $i++;
        }
        else { # first call
            $i = 0;
        }
        for (; $i<=$#keywords; $i++) {
            return $keywords[$i] if $keywords[$i] =~ /^\Q$text/;
        };
        return undef;
} };
1;
__END__
