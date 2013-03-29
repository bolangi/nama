# ----------- Terminal related subroutines ---------

package ::;
use Modern::Perl;
no warnings 'uninitialized';
use Carp;
use ::Globals qw(:singletons $this_bus $this_track);

sub issue_first_prompt {
	$text->{term}->stuff_char(10); # necessary to respond to Ctrl-C at first prompt 
	&{$text->{term_attribs}->{'callback_read_char'}}();
	set_current_bus();
	print prompt();
	$text->{term_attribs}->{already_prompted} = 0;
}

sub initialize_terminal {
	$text->{term} = new Term::ReadLine("Ecasound/Nama");
	$text->{term_attribs} = $text->{term}->Attribs;
	$text->{term_attribs}->{attempted_completion_function} = \&complete;
	$text->{term_attribs}->{already_prompted} = 1;
	detect_spacebar(); 

	revise_prompt();
	# handle Control-C from terminal

	$SIG{INT} = \&cleanup_exit;
	$SIG{USR1} = sub { save_state() };
	#$engine->{events}->{sigint} = AE::signal('INT', \&cleanup_exit);

}
{my $override;
sub revise_prompt {
	# hack to allow suppressing prompt
	$override = $_[0] eq "default" ? undef : $_[0] if defined $_[0];
    $text->{term}->callback_handler_install($override//prompt(), \&process_line);
}
}

	
sub prompt {

		git_branch_display(). "nama [". ($this_bus eq 'Main' ? '': "$this_bus/").  
		($this_track ? $this_track->name : '') . "] ('h' for help)> "
}
sub detect_spacebar {

	# create a STDIN watcher to intervene when space
	# received in column one
	
	$engine->{events}->{stdin} = AE::io(*STDIN, 0, sub {
		&{$text->{term_attribs}->{'callback_read_char'}}();
		if ( $config->{press_space_to_start} and 
			$text->{term_attribs}->{line_buffer} eq " " ){

			toggle_transport();	
			$text->{term_attribs}->{line_buffer} = q();
			$text->{term_attribs}->{point} 		= 0;
			$text->{term_attribs}->{end}   		= 0;
			$text->{term}->stuff_char(10);
			&{$text->{term_attribs}->{'callback_read_char'}}();
		}
	});
}

sub throw {
	logsub("&throw");
	pager3(@_)
}
sub pager2 {
	logsub("&pager2");
	pager(join "", @_)
}
sub pager3 { map { my $s = $_; chomp $s; say $s} @_ }
	
sub pager {
	logsub("&pager");
	my @output = @_;
	my ($screen_lines, $columns) =
	$text->{term} ? $text->{term}->get_screen_size() : (); 
	my $line_count = 0;
	map{ $line_count += $_ =~ tr(\n)(\n) } @output;
	if 
	( 
		(ref $ui) =~ /Text/  # pager interferes with GUI
		and $config->{use_pager} 
		and ! $config->{opts}->{T}
		and $line_count > $screen_lines - 2
	) { 
		my $fh = File::Temp->new();
		my $fname = $fh->filename;
		print $fh @output;
		file_pager($fname);
	} else {
		print @output;
	}
	print "\n\n";
}

sub mandatory_pager {
	logsub("&mandatory_pager");
	my @output = @_;
	if 
	( 
		(ref $ui) =~ /Text/  # pager interferes with GUI
		and $config->{use_pager} 
	) { 
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
	logsub("&file_pager");
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
	
	%{$text->{iam}} = map{$_,1 } 
				grep{ ! $reserved{$_} } split /[\s,]/, eval_iam('int-cmd-list');
}

sub load_keywords {
	@{$text->{keywords}} = keys %{$text->{commands}};
	push @{$text->{keywords}}, grep{$_} map{split " ", $text->{commands}->{$_}->{short}} @{$text->{keywords}};
	push @{$text->{keywords}}, keys %{$text->{iam}};
	push @{$text->{keywords}}, keys %{$fx_cache->{partial_label_to_full}};
	push @{$text->{keywords}}, keys %{$midi->{keywords}} if $config->{use_midish};
	push @{$text->{keywords}}, "Audio::Nama::";
}

sub complete {
    my ($string, $line, $start, $end) = @_;
	#print join $/, $string, $line, $start, $end, $/;
	my $term = $text->{term};
    return $term->completion_matches($string,\&keyword);
};

sub keyword {
		state $i;	
        my ($string, $state) = @_;
        return unless $text;
        if($state) {
            $i++;
        }
        else { # first call
            $i = 0;
        }
        for (; $i<=$#{$text->{keywords}}; $i++) {
            return $text->{keywords}->[$i] 
				if $text->{keywords}->[$i] =~ /^\Q$string/;
        };
        return undef;
};
1;
__END__
