# ----------- Terminal related subroutines ---------

package ::;
use Modern::Perl '2020';
no warnings 'uninitialized';
use Carp;
use ::Globals qw(:singletons $this_bus $this_track);
use ::Log qw(logpkg logsub);
use Data::Dumper::Concise;
use List::MoreUtils qw(first_index);
# all keynames in vars defined below are lower case
our %escape_code; # keyname -> escape code
our %keyname;     # escape code -> keyname
our %bindings;    # keyname -> function e.g. right -> incr_param_by_1 (from namarc hotkeys)
our @keynames;
our ($nama_keymap, $emacs_keymap, $nama_meta, $emacs_meta);


sub initialize_prompt {
	set_current_bus();
	print prompt();
	$term->Attribs->{already_prompted} = 1;
}

sub setup_termkey {
	$project->{events}->{termkey} = AnyEvent::TermKey->new(
		term => \*STDIN,

		on_key => sub {
			my $key = shift;
			# exit on Ctrl-C
			exit_hotkey_mode(), cleanup_exit() if $key->type_is_unicode 
						and $key->utf8 eq "C" 
						and $key->modifiers & KEYMOD_CTRL;
			my $key_string = $key->termkey->format_key( $key, FORMAT_VIM );

			logpkg('debug',"got key: $key_string");

			# remove angle brackets around multi-character
			# sequences, e.g. <PageUp> -> PageUp
			# but leave a lone '<' or '>' 

			$key_string =~ s/[<>]//g if length $key_string > 1;
			 
			# Execute command if we get Enter

			process_line($text->{hotkey_buffer}), reset_hotkey_buffer(), print("\n"),return if $key_string eq 'Enter';

			my $dont_display;
			$key_string =~ s/ /Space/; # to suit our mapping file
			
			# we have a mapping for this key *and* cursor is in column one

			if (my $command = $bindings{$key_string}){
				 return if length $text->{hotkey_buffer} > 1; # skip printable characters
				$dont_display++ if $key_string eq 'Escape'
									or $key_string eq 'Space';

				say "command: $command";
				eval $command;
				$@ and throw("error was $@");
				undef $@;
				#try { $command->() }
				#catch { throw( qq(cannot execute "$command" for key "$key_string": $_") );  
				#		return; }
				

			print(
				"\x1b[$text->{screen_lines};0H", # go to screen bottom line, column 0
				"\x1b[2K",  # erase line
				status_bar(), 
			) unless $dont_display;

			return;
			}

			# assemble keystrokes and check them against the grammar
			 
			$key_string =~ s/Space/ /; # back to the character
			if ( length $key_string == 1) {
				$text->{hotkey_buffer} .= $key_string;
				print $key_string; 
				no warnings;
				#$text->{hotkey_parser}->command($text->{hotkey_buffer}) and reset_hotkey_buffer();
			}
		}
	);
}
sub reset_hotkey_buffer {
	$text->{hotkey_buffer} = "";
}
sub teardown_termkey {
	$project->{events}->{termkey}->termkey->stop(),
		delete $project->{events}->{termkey} if $project->{events}->{termkey}
}
sub destroy_readline {
	$term->deprep_terminal() if defined $term;
	#undef $term; # leave it alive 
	delete $project->{events}->{stdin};
}
sub setup_hotkey_grammar {
	$text->{hotkey_grammar} = get_data_section('hotkey_grammar');
	$text->{hotkey_parser} = Parse::RecDescent->new($text->{hotkey_grammar})
		or croak "Bad grammar!\n";
}
sub initialize_terminal {
	$term = Term::ReadLine->new("Ecasound/Nama");
	setup_readline();	
}
sub setup_readline {
	#$term->prep_terminal(1); # eight bit
	#$term->initialize();
	$term->Attribs->{attempted_completion_function} = \&complete;
	$term->Attribs->{already_prompted} = 1;
	$term->add_defun('spacebar_action', \&spacebar_action);
	$term->bind_keyseq(' ','spacebar_action');
	($text->{screen_lines}, $text->{screen_columns}) 
		= $term->get_screen_size();
	logpkg('debug', "screensize is $text->{screen_lines} lines x $text->{screen_columns} columns");
	revise_prompt();
	# none of below eliminate double echo
	#reset_terminal();
	#qx('reset');
	setup_readline_event_loop(); 
	#stty();
	
}
sub exit_hotkey_mode {
	pager("\narrow keys reset, hotkeys off.");
	teardown_termkey();
	#stty();                
	setup_readline();
}
sub toggle_hotkeys {
	state $mode = 0; # 0: readline 1: termkey with current hotkey bindings
	exit_hotkey_mode(), $mode = 0, return if $mode == 1; # we've reset the keymap, standard cursor commands
	$mode = 1;
	setup_hotkeys($text->{hotkey_mode});# we've activated the hotkeys again.
}
sub spacebar_action {
		my $buffer = $term->Attribs->{line_buffer};
		if ( length $buffer == 0 ) { 
			toggle_transport() 
		}
		else {  
			$term->insert_text(' '); 
		}
}
sub set_keymap { $term->set_keymap($term->get_keymap_by_name($_[0]))}
sub get_keymap { $term->get_keymap_by_name($_[0]) }

sub keymap_name {
	$term->get_keymap_name($term->get_keymap);
}
sub setup_hotkeys {
	my ($map, $quiet) = @_;
	$text->{hotkey_mode} = $map if defined $map;
	destroy_readline(); 
	setup_termkey(); 
	%bindings = hotkey_map($map);
	pager("\nHotkeys set for $map!") unless $quiet;
	list_hotkeys();
	display_status();
	print "\n"; # prompt
}
sub string_to_escape_code {
    my ($string) = @_;                                                                         
    my $esc = '';
    for my $char (split //, $string) {
		my $ord = ord($char);
        $char = '\e' if $ord == 27; 
        $esc .= $char;
    }
    $esc
} 

sub hotkey_map {
	my $mode = shift;
 	%bindings		= ( $config->{hotkeys}->{common}->%*, 
 							$config->{hotkeys}->{$text->{hotkey_mode}}->%* );
}

sub list_hotkeys { 
	pager_newline("Current hotkey mode: $text->{hotkey_mode}");
 	my %hots = hotkey_map($text->{hotkey_mode});
	my @list;
	for (@keynames){
		push @list, "$_: $hots{$_}" if $hots{$_};
	}
 	pager_newline("Hotkeys",@list);
}
sub termkey_list_hotkeys { 
	my $hots 		= dclone($config->{hotkeys});
	my %hots = %$hots;
	$hots{'='} 		= 'Enter numeric value';
	$hots{ 'mN' } 	= 'Change step size to 10 raised to the Nth power';
	$hots{ '#' }	= 'Engage hotkey mode (must be typed in column 1)';
	pager("Hotkeys\n",Dumper \%hots)
}

sub display_status {
			print(
				"\x1b[$text->{screen_lines};0H", # go to screen bottom line, column 0
				"\x1b[2K",  # erase line
				status_bar()
			) ;
}
sub status_bar { 
	my %bar = (param => \&param_status_bar,
	           jump  => \&jump_status_bar,
			   bump  => \&jump_status_bar );
	$bar{$text->{hotkey_mode}}->();
}
	
sub param_status_bar {
	my $name = "[".$this_track->name."]"; 
	return "$name has no selected effect" unless $this_track->op;
	my $effect_info = join " ", $name,
				this_op(), 
				this_op_o()->fxname;
# 	if (this_op_o()->no_params) {
# 		return "$effect_info (no parameters to adjust)";
# 	}
	my $param_pos = this_param() - 1;
	my $param_info = parameter_info(this_op(), $param_pos);
	if (this_op_o()->is_read_only ){
		return "$effect_info $param_info - no adjustment possible";
	}
	$param_info .= " Stepsize: ".param_stepsize();
	return "$effect_info $param_info";
}
sub jump_status_bar {
	return unless $this_track; 
	my $name = "[".$this_track->name."]";
	my $pos = ::ecasound_iam("getpos") // 0;
	my $bar = "$name: Playback at ${pos}s, ";
	if (defined $this_mark) {
		my $mark = join ' ', 'Current mark:', $this_mark->name, 'at', $this_mark->time;
		$bar .= $mark;
	}
	$bar .= "Jump size: $config->{playback_jump_seconds}s, ";
	$bar .= "Mark bump: $config->{mark_bump_seconds}s " ;
	$bar
}
sub keep_beep 			{ beep( $config->{beep}->{clip})}
sub till_beep 			{ beep( $config->{beep}->{clop})}
sub command_error_beep 	{ beep( $config->{beep}->{command_error})}
sub end_of_list_beep    { beep( $config->{beep}->{end_of_list  })}

sub beep { 
	my $args = shift;
	my($freq, $duration, $vol_percent) = split ' ', $args;
	my $cmd;
	if ($config->{beep}->{command} eq 'beep') {
		$duration *= 1000; # convert to milliseconds 
		$duration //= 200;
		$cmd = "beep -f $freq -l $duration";
	} else {
		$vol_percent //= 10;
		my $output_device = ::IO::to_alsa_soundcard_device::device_id;
		$cmd = "ecasound -i:tone,sine,$freq,$duration -ea $vol_percent -o:$output_device 2>&1 > /dev/null";
	}
	system($cmd);
}

sub previous_track {
	end_of_list_beep(), return if $this_track->n == 1;
	do{ $this_track = $ti{$this_track->n - 1} } until !  $this_track->hide;
}
sub next_track {
	end_of_list_beep(), return if ! $ti{ $this_track->n + 1 };
	do{ $this_track = $ti{$this_track->n + 1} } until ! $this_track->hide;
}
sub previous_effect {
	my $op = $this_track->op;
	my $pos = $this_track->pos;
	end_of_list_beep(), return if $pos == 0;
	$pos--;
	set_current_op($this_track->ops->[$pos]);
}
sub next_effect {
	my $op = $this_track->op;
	my $pos = $this_track->pos;
	end_of_list_beep(),return if $pos == scalar @{ $this_track->ops } - 1;
	$pos++;
	set_current_op($this_track->ops->[$pos]);
}
sub previous_param {
	this_param() > 1 ? set_current_param( this_param() - 1)
						: end_of_list_beep()
}
sub next_param {
	this_param()  < scalar this_op_o()->params->@* 
		? set_current_param( this_param() + 1)
		: end_of_list_beep()
}
{my $override;
sub revise_prompt {
	logsub((caller(0))[3]);
	# hack to allow suppressing prompt
	$override = ($_[0] eq "default" ? undef : $_[0]) if defined $_[0];
    $term->callback_handler_install($override//prompt(), \&process_line)
		if $term;
	initialize_prompt() if $term;
}
}

sub reset_terminal { $term->reset_terminal() }
sub stty { system('stty 6006:5:bf:a39:3:0:7f:15:4:0:1:0:11:13:0:0:12:f:17:16:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0') }
	
sub prompt { 
	logsub((caller(0))[3]);
	join ' ', 'nama', git_branch_display(), bus_track_display(),'> '
}
sub setup_readline_event_loop {
	$project->{events}->{stdin} = AE::io(*STDIN, 0, sub { $term->Attribs->{'callback_read_char'}->() });
	# handle Control-C from terminal
	$project->{events}->{sigint} = AE::signal('INT', \&cleanup_exit); 
	# responds in a more timely way than $SIG{INT} = \&cleanup_exit; 
	$SIG{USR1} = sub { project_snapshot() };
}
sub throw {
	logsub((caller(0))[3]);
	pager_newline(@_)
}
sub pagers { &pager_newline(join "",@_) } # pass arguments along

sub pager_newline { 

	# Add a newline if necessary to each line
	# push them onto the output buffer
	# print them to the screen
	
	my @lines = @_;
	for (@lines){ $_ .= "\n" if  ! /\n$/ }
	push @{$text->{output_buffer}}, @lines;
	print(@lines);
}

sub paging_allowed {

		# The pager interferes with GUI and testing
		# so do not use the pager in these conditions
		# or if use_pager config variable is not set.
		
		$config->{use_pager} 
		and ! $config->{opts}->{T}
}
sub pager {

	# push array onto output buffer, add two newlines
	# and print on terminal or view in pager
	# as appropriate
	
	logsub((caller(0))[3]);
	my @output = @_;
	@output or return;
	chomp $output[-1];
	$output[-1] .= "\n\n";
	push @{$text->{output_buffer}}, @output;
	page_or_print(@output);
	1
}

sub init_output_buffer { $text->{output_buffer} //= [] };

sub linecount {
	my @output = @_;
	my $linecount = 0;
	for (@output){ $linecount += $_ =~ tr(\n)(\n) }
	$linecount
}

sub page_or_print {
	my (@output) = @_;
	@output = map{"$_\n"} map{ split "\n"} @output;
	return unless scalar @output;
	print(@output), return if !paging_allowed() or scalar(@output) <= $text->{screen_lines} - 2;
	write_to_temp_file_and_view(@output)
}
sub write_to_temp_file_and_view {
	my @output = @_;
	my $fh = File::Temp->new();
	my $fname = $fh->filename;
	print $fh @output;
	file_pager($fname);
}
sub file_pager {

	# given a filename, run the pager on it
	
	logsub((caller(0))[3]);
	my $fname = shift;
	if (! -e $fname or ! -r $fname ){
		carp "file not found or not readable: $fname\n" ;
		return;
    }
	my $pager = $ENV{PAGER} || "/usr/bin/less";
	$pager =~ /less/ and $pager .= qq( -M -i -PM"q=quit pager, /=search, PgUp/PgDown=scroll (line %lt/%L)");
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
				grep{ ! $reserved{$_} } split /[\s,]/, ecasound_iam('int-cmd-list');
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
	push @keywords, keys %{$text->{midi_cmd}} if $config->{use_midi};
	push @keywords, "Audio::Nama::";
	@{$text->{keywords}} = @keywords
}

sub complete {
    my ($string, $line, $start, $end) = @_;
	#print join $/, $string, $line, $start, $end, $/;
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

%escape_code = @keynames = qw(
[% qx(cat ./escape_codes) %]
);

# get them in order
my @i = reverse(1..@keynames/2);
for my $i (@i){ splice @keynames, 2 * $i - 1, 1 }
my @printable = map{chr $_} 33..126;
@keynames = (@printable, @keynames);

%keyname = ( reverse %escape_code );

1;
__END__
