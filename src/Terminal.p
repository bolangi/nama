# ----------- Terminal related subroutines ---------

package ::;
use Modern::Perl '2020';
no warnings 'uninitialized';
use Carp;
use ::Globals qw(:singletons $this_bus $this_track);
use ::Log qw(logpkg logsub);
use Data::Dumper::Concise;
use List::MoreUtils qw(first_index);
our %escape_code; # key name -> escape code
our %keyname;     # escape code -> key name
our %bindings;    # key name -> nama function (from namarc hotkeys)

sub initialize_prompt {
	$term->stuff_char(10); # necessary to respond to Ctrl-C at first prompt 
	$term->Attribs->{'callback_read_char'}->();
	set_current_bus();
	print prompt();
	$term->Attribs->{already_prompted} = 0;
}

sub initialize_terminal {
	$term = Term::ReadLine->new("Ecasound/Nama");
	new_keymap();
	setup_hotkeys('jump', 'quiet');
	$term->Attribs->{attempted_completion_function} = \&complete;
	$term->Attribs->{already_prompted} = 1;
	($text->{screen_lines}, $text->{screen_columns}) 
		= $term->get_screen_size();
	logpkg('debug', "screensize is $text->{screen_lines} lines x $text->{screen_columns} columns");
	detect_spacebar(); 

	revise_prompt();

	# handle Control-C from terminal
	$project->{events}->{sigint} = AE::signal('INT', \&cleanup_exit); 
	# responds in a more timely way than $SIG{INT} = \&cleanup_exit; 

	$SIG{USR1} = sub { project_snapshot() };
}
sub new_keymap {
	# backup default bindings, we will modify a copy
	$text->{default_keymap} = $term->get_keymap;
	$text->{nama_keymap} = $term->copy_keymap($text->{default_keymap});
	$term->set_keymap_name('nama', $text->{nama_keymap});
	$term->set_keymap($text->{nama_keymap});
}
sub keymap_name {
	$term->get_keymap_name($term->get_keymap);
}

sub setup_hotkeys {
	my ($map, $quiet) = @_;
	new_keymap();
	$text->{hotkey_mode} = $map;
	%bindings = ($config->{hotkeys}->{common}->%*, 
					$config->{hotkeys}->{$map}->%*);
	my %bindings_lc;
	while( my($key,$function) = each %bindings ){
		$bindings_lc{lc $key} = $function
	}
	%bindings = %bindings_lc;

	my $func_name = 'hotkey_dispatch';
	my $coderef = \&hotkey_dispatch;
	$term->add_defun($func_name, $coderef);
	while ( my ($keyname,$seq) = each %escape_code) {
	$term->bind_keyseq($seq, $func_name);
	}
	pager("\nHotkeys set for $map!") unless $quiet;
}
sub hotkey_dispatch {                                                                          
	my ($seq) = string_to_escape_code($term->Attribs->{executing_keyseq});
	my $name = $keyname{$seq};
	my $func_name = $bindings{$name};
	say "Special key: $name, escape sequence: $seq, triggers $func_name";
	no strict 'refs';
	$func_name->();
	#display_status();
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

sub list_hotkeys { 
	my %hots 		= ( $config->{hotkeys}->{common}->%*, 
						$config->{hotkeys}->{$text->{hotkey_mode}->%*} );
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
			   bump  => \&bump_status_bar );
	$bar{$text->{hotkey_mode}}
}
	
sub param_status_bar {
	my $name = "[".$this_track->name."]"; 
	return "$name has no selected effect" unless $this_track->op;
	join " ", $name,
				"Stepsize: ",$this_track->stepsize,
				fxn($this_track->op)->fxname,
				parameter_info($this_track->op, $this_track->param - 1);
}
sub jump_status_bar {
	my $pos = ::ecasound_iam("getpos");
	my $bar = "Playback at ${pos}s, ";
	if (defined $this_mark) {
		my $mark = join ' ', 'Mark', qq("$this_mark->name"), 'at', $this_mark->time;
		$bar .= $mark;
	}
	$bar .= "jump size: $config->{playback_jump_seconds}s, ";
	$bar .= "mark bump: $config->{mark_bump_seconds}s " ;
	$bar
}
sub beep_trim_start 	{ beep( $config->{beep}->{trim_start   }->@* )}
sub beep_trim_end   	{ beep( $config->{beep}->{trim_end     }->@* )}
sub beep_command_error 	{ beep( $config->{beep}->{command_error}->@* )}
sub beep_end_of_list    { beep( $config->{beep}->{end_of_list  }->@* )}

sub beep { 
	my($freq, $duration, $vol_percent) = @_; 
	my $cmd;
	if ($config->{beep}->{command} eq 'beep') {
		$duration *= 1000; # convert to milliseconds 
		$duration //= 200;
		$cmd = "beep -f $freq -l $duration";
	} else {
		$vol_percent //= 10;
		$cmd = "ecasound -i:tone,sine,$freq,$duration -ea $vol_percent";
	}
	my @cmd = split ' ',$cmd;
	system(@cmd);
}

sub destroy_readline {
	$term->rl_deprep_terminal() if $term;
	undef $term; 
	delete $project->{events}->{stdin};
}
sub previous_track {
	beep_end_of_list(), return if $this_track->n == 1;
	do{ $this_track = $ti{$this_track->n - 1} } until !  $this_track->hide;
}
sub next_track {
	beep_end_of_list(), return if ! $ti{ $this_track->n + 1 };
	do{ $this_track = $ti{$this_track->n + 1} } until ! $this_track->hide;
}
sub previous_effect {
	my $op = $this_track->op;
	my $pos = $this_track->pos;
	beep_end_of_list(), return if $pos == 0;
	$pos--;
	set_current_op($this_track->ops->[$pos]);
}
sub next_effect {
	my $op = $this_track->op;
	my $pos = $this_track->pos;
	beep_end_of_list(),return if $pos == scalar @{ $this_track->ops } - 1;
	$pos++;
	set_current_op($this_track->ops->[$pos]);
}
sub previous_param {
	my $param = $this_track->param;
	$param > 1  ? set_current_param($this_track->param - 1)
				: beep_end_of_list()
}
sub next_param {
	my $param = $this_track->param;
	$param < scalar @{ fxn($this_track->op)->params }
		? $project->{current_param}->{$this_track->op}++ 
		: beep_end_of_list()
}
{my $override;
sub revise_prompt {
	logsub((caller(0))[3]);
	# hack to allow suppressing prompt
	$override = ($_[0] eq "default" ? undef : $_[0]) if defined $_[0];
    $term->callback_handler_install($override//prompt(), \&process_line)
		if $term
}
}

	
sub prompt { 
	logsub((caller(0))[3]);
	join ' ', 'nama', git_branch_display(), 
						bus_track_display() ," ('h' for help)> "
}
sub detect_spacebar {

	# create a STDIN watcher to intervene when space
	# received in column one
	
	$project->{events}->{stdin} = AE::io(*STDIN, 0, sub {
		$term->Attribs->{'callback_read_char'}->();
		my $buffer = $term->Attribs->{line_buffer};
		my $trigger = ' ';
		if ( $config->{press_space_to_start} 
				and ($buffer eq $trigger)
				and ! ($mode->song or $mode->live) )
		{ 	
			toggle_transport();	

			# reset command line, read next char
			
			$term->Attribs->{line_buffer} = q();
			$term->Attribs->{point} 		= 0;
			$term->Attribs->{end}   		= 0;
			$term->stuff_char(10);
			$term->Attribs->{'callback_read_char'}->();

			
		}
	});
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

%escape_code = qw(

  Escape  	\\e

  F1		\\eOP
  F2		\\eOQ
  F3		\\eOR
  F4		\\eOS
  F5		\\e[15~ 
  F6		\\e[17~ 
  F7		\\e[18~ 
  F8		\\e[19~ 
  F9		\\e[20~ 
  F10		\\e[21~ 
  F11		\\e[23~ 
  F12		\\e[24~ 

  Insert  	\\e[2~
  Delete  	\\e[3~
  Home  	\\e[1~
  End  		\\e[4~
  PageUp  	\\e[5~
  PageDown  \\e[6~

  Up  		\\e[A
  Left  	\\e[D
  Down  	\\e[B
  Right  	\\e[C


  Keypad/	\\eOo
  Keypad*	\\eOj
  Keypad-   \\eOm
  Keypad+   \\eOk
  Keypad7   \\eOw
  Keypad8   \\eOx
  Keypad9   \\eOy
  Keypad4   \\eOt
  Keypad5   \\eOu
  Keypad6   \\eOv
  Keypad1   \\eOq
  Keypad2   \\eOr
  Keypad3   \\eOs
  Keypad0   \\eOp
  Keypad.   \\eOn
  KeypadEnter   \\eOM
  
  ShiftF1	\\e[23~
  ShiftF2 \\e[24~
  ShiftF3 \\e[25~
  ShiftF4 \\e[26~
  ShiftF5 \\e[28~
  ShiftF6 \\e[29~
  ShiftF7 \\e[31~
  ShiftF8 \\e[32~
  ShiftF9 \\e[33~
  ShiftF10 \\e[34~
  ShiftF11 \\e[23$
  ShiftF12 \\e[24$

  ShiftInsert [11^
  ShiftDelete \\e[3$
  ShiftHome	  \\e[7$
  ShiftEnd	  \\e[8$ 
  ShiftUp	\\e[a
  ShiftDown \\e[b
  ShiftLeft \\e[d
  ShiftRight \\e[c

  ControlF1	\\e[11^
  ControlF2 \\e[12^
  ControlF3 \\e[13^
  ControlF4 \\e[14^
  ControlF5 \\e[15^
  ControlF6 \\e[17^
  ControlF7 \\e[18^
  ControlF8 \\e[19^
  ControlF9 \\e[20^
  ControlF10 \\e[21^
  ControlF11 \\e[23^
  ControlF12 \\e[24^

  ControlInsert \\e[2^
  ControlDelete \\e[3^
  ControlHome	 \\e[7^
  ControlEnd   \\e[8^
  ControlPageUp \\e[5^
  ControlPageDown \\e[6^
  ControlUp      \\eOa
  ControlDown    \\eOb
  ControlLeft    \\eOd
  ControlRight   \\eOc

  AltInsert  	\\e\\e[2~
  AltDelete  	\\e\\e[3~
  AltHome  	\\e\\e[1~
  AltEnd  		\\e\\e[4~
  AltPageUp  	\\e\\e[5~
  AltPageDown  \\e\\e[6~

  AltUp  		\\e\\e[A
  AltLeft  	\\e\\e[D
  AltDown  	\\e\\e[B
  AltRight  	\\e\\e[C

  AltKeypad/	\\e\\eOo
  AltKeypad*	\\e\\eOj
  AltKeypad-   \\e\\eOm
  AltKeypad+   \\e\\eOk
  AltKeypad7   \\e\\eOw
  AltKeypad8   \\e\\eOx
  AltKeypad9   \\e\\eOy
  AltKeypad4   \\e\\eOt
  AltKeypad5   \\e\\eOu
  AltKeypad6   \\e\\eOv
  AltKeypad1   \\e\\eOq
  AltKeypad2   \\e\\eOr
  AltKeypad3   \\e\\eOs
  AltKeypad0   \\e\\eOp
  AltKeypad.   \\e\\eOn
  AltKeypadEnter   \\e\\eOM
  
  AltF1		\\e\\eOP
  AltF2		\\e\\eOQ
  AltF3		\\e\\eOR
  AltF4		\\e\\eOS
  AltF5		\\e\\e[15~ 
  AltF6		\\e\\e[17~ 
  AltF7		\\e\\e[18~ 
  AltF8		\\e\\e[19~ 
  AltF9		\\e\\e[20~ 
  AltF10		\\e\\e[21~ 
  AltF11		\\e\\e[23~ 
  AltF12		\\e\\e[24~ 
  
);
my %escape_code_lc;
while( my($key,$seq) = each %escape_code ){
	$escape_code_lc{lc $key} = $seq;
}
%escape_code = %escape_code_lc;

%keyname = ( reverse %escape_code );



1;
__END__
