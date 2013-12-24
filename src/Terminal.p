# ----------- Terminal related subroutines ---------

package ::;
use Modern::Perl;
no warnings 'uninitialized';
use Carp;
use ::Globals qw(:singletons $this_bus $this_track);
use ::Log qw(logpkg logsub);
use List::MoreUtils qw(first_index);

sub initialize_prompt {
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
	($text->{screen_lines}, $text->{screen_columns}) 
		= $text->{term}->get_screen_size();
	detect_spacebar(); 

	revise_prompt();

	# handle Control-C from terminal

	# does nothing
	#$SIG{INT} = \&cleanup_exit; 

	# doesn't do anything either
	#$this_engine->{events}->{sigint} = AE::signal('INT', \&cleanup_exit); 

	$SIG{USR1} = sub { git_snapshot() };
}

sub setup_hotkeys {
	say "\nHotkeys on!";
	destroy_readline(); 
	setup_termkey(); 
	1
}
sub setup_termkey {
	$this_engine->{events}->{termkey} = AnyEvent::TermKey->new(
		term => \*STDIN,

		on_key => sub {
			my $key = shift;
			my $key_string = $key->termkey->format_key( $key, FORMAT_VIM );
			logpkg('debug',"got key: $key_string");
			# remove angle brackets around multi-character
			# sequences, e.g. <PageUp> -> PageUp
			$key_string =~ s/[<>]//g if length $key_string > 1;

			exit_hotkey_mode(), cleanup_exit() if $key->type_is_unicode 
						and $key->utf8 eq "C" 
						and $key->modifiers & KEYMOD_CTRL;
			 
			# execute callback if we have one keystroke 
			# and it has an "instant" mapping
			 
			my $suppress_status;
			$key_string =~ s/ /Space/; # to suit our mapping file
			if ( my $command = $config->{hotkeys}->{$key_string} 
				and ! length $text->{hotkey_buffer}) {


				$suppress_status++ if $key_string eq 'Escape'
									or $key_string eq 'Space';


				try { eval "$command()" }
				catch { throw( qq(cannot execute subroutine "$command" for key "$key_string": $_") ) }
			}

			# otherwise assemble keystrokes and check
			# them against the grammar
			 
			else {
			$key_string =~ s/Space/ /; # back to the character
			$text->{hotkey_buffer} .= $key_string;
			print $key_string if length $key_string == 1;
#			push $text->{hotkey_object_buffer}, $key;
			$text->{hotkey_parser}->command($text->{hotkey_buffer})
 				and reset_hotkey_buffers();
 			}
			print(
				"\x1b[$text->{screen_lines};0H", # go to screen bottom line, column 0
				"\x1b[2K",  # erase line
				hotkey_status_bar(), 
			) if $text->{hotkey_buffer} eq undef and ! $suppress_status;
		},
	);
}
sub hotkey_status_bar {
	join " ", "[".$this_track->name."]", extended_name($this_track->op), 
				parameter_info($this_track->op, $this_track->param - 1),
				"Stepsize: ",$this_track->stepsize;
				
;
}
sub reset_hotkey_buffers {
	$text->{hotkey_buffer} = "";
	$text->{hotkey_object_buffer} = [];
}
sub exit_hotkey_mode {
	teardown_hotkeys();
	initialize_terminal(); 
	initialize_prompt();
};
sub teardown_hotkeys {
	$this_engine->{events}->{termkey}->termkey->stop(),
		delete $this_engine->{events}->{termkey} if $this_engine->{events}->{termkey}
}
sub destroy_readline {
	$text->{term}->rl_deprep_terminal() if $text->{term};
	delete $text->{term}; 
	delete $this_engine->{events}->{stdin};
}
sub setup_hotkey_grammar {
	$text->{hotkey_grammar} = get_data_section('hotkey_grammar');
	$text->{hotkey_parser} = Parse::RecDescent->new($text->{hotkey_grammar})
		or croak "Bad grammar!\n";
}
sub end_of_list_sound { system( $config->{hotkey_beep} ) }

sub previous_track {
	end_of_list_sound(), return if $this_track->n == 1;
	do{ $this_track = $ti{$this_track->n - 1} } until !  $this_track->hide;
}
sub next_track {
	end_of_list_sound(), return if ! $ti{ $this_track->n + 1 };
	do{ $this_track = $ti{$this_track->n + 1} } until ! $this_track->hide;
}
sub previous_effect {
	my $op = $this_track->op;
	my $pos = $this_track->pos;
	end_of_list_sound(), return if $pos == 0;
	$pos--;
	set_current_op($this_track->ops->[$pos]);
}
sub next_effect {
	my $op = $this_track->op;
	my $pos = $this_track->pos;
	end_of_list_sound(),return if $pos == scalar @{ $this_track->ops } - 1;
	$pos++;
	set_current_op($this_track->ops->[$pos]);
}
sub previous_param {
	my $param = $this_track->param;
	$param > 1  ? set_current_param($this_track->param - 1)
				: end_of_list_sound()
}
sub next_param {
	my $param = $this_track->param;
	$param < scalar @{ fxn($this_track->op)->params }
		? $project->{current_param}->{$this_track->op}++ 
		: end_of_list_sound()
}
{my $override;
sub revise_prompt {
	# hack to allow suppressing prompt
	$override = $_[0] eq "default" ? undef : $_[0] if defined $_[0];
    $text->{term}->callback_handler_install($override//prompt(), \&process_line)
		if $text->{term}
}
}

	
sub prompt { join ' ', 'nama', git_branch_display(), 
						bus_track_display() ," ('h' for help)> "
}
sub detect_spacebar {

	# create a STDIN watcher to intervene when space
	# received in column one
	
	$this_engine->{events}->{stdin} = AE::io(*STDIN, 0, sub {
		&{$text->{term_attribs}->{'callback_read_char'}}();
		if ( $config->{press_space_to_start} and 
			$text->{term_attribs}->{line_buffer} eq " " 
				and ! ($mode->song or $mode->live) )
		{ 	
			toggle_transport();	
			$text->{term_attribs}->{line_buffer} = q();
			$text->{term_attribs}->{point} 		= 0;
			$text->{term_attribs}->{end}   		= 0;
			$text->{term}->stuff_char(10);
			&{$text->{term_attribs}->{'callback_read_char'}}();
		}
		elsif (  $text->{term_attribs}->{line_buffer} eq "#" ){
			setup_hotkeys();
		}
	});
}
sub throw {
	logsub("&throw");
	pager_newline(@_)
}
sub pager_join {
	logsub("&pager_join");
	pager(join "", @_)
}
sub pager_newline { map { my $s = $_; chomp $s; say $s} @_ }
	
sub pager {
	logsub("&pager");
	my @output = @_;
	my $line_count = 0;
	map{ $line_count += $_ =~ tr(\n)(\n) } @output;
	if 
	( 
		(ref $ui) =~ /Text/  # pager interferes with GUI
		and $config->{use_pager} 
		and ! $config->{opts}->{T}
		and $line_count > $text->{screen_lines} - 2
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
	my @keywords = keys %{$text->{commands}};
 	# complete hyphenated forms as well
 	my %hyphenated = map{my $h = $_; $h =~ s/_/-/g; $h => $_ }grep{ /_/ } @keywords;
	$text->{hyphenated_commands} = \%hyphenated;
	push @keywords, keys %hyphenated;
	push @keywords, grep{$_} map{split " ", $text->{commands}->{$_}->{short}} @keywords;
	push @keywords, keys %{$text->{iam}};
	push @keywords, keys %{$fx_cache->{partial_label_to_full}};
	push @keywords, keys %{$midi->{keywords}} if $config->{use_midish};
	push @keywords, "Audio::Nama::";
	@{$text->{keywords}} = @keywords
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
