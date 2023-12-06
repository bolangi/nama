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
our %bindings;    # keyname -> function e.g. right -> inrc_param_by_1 (from namarc hotkeys)
our @keynames;
our ($nama_keymap, $emacs_keymap, $nama_meta, $emacs_meta);


sub initialize_prompt {
	set_current_bus();
	print prompt();
	$term->Attribs->{already_prompted} = 0;
}

sub initialize_terminal {
	$term = Term::ReadLine->new("Ecasound/Nama");
	
	# keymap independent
	$term->add_defun('spacebar_action', \&spacebar_action);
	$term->add_defun('hotkey_dispatch', \&hotkey_dispatch);
	$term->Attribs->{attempted_completion_function} = \&complete;
	$term->Attribs->{already_prompted} = 1;


	initialize_nama_keymap();
	

=comment
	# store default bindings, just in case
 	$text->{default _bindings} = {};
 	for my $k (@keynames) {
 		my $str = $escape_code{$k};
		my $esc = eval qq("$str");
		#say "key $k, str: $str";
		my @function = ($term->function_of_keyseq($esc));
		(ref \@function) =~ /ARRAY/ and scalar @function or next;
		#say "ref: ",ref \@function;
		#say "func: @function";
 		my $func_name = $text->{default _bindings}->{$k} = $term->get_function_name($function[0]);
		say "key $k, seq: $str, func: $func_name";
 	}
=cut

	($text->{screen_lines}, $text->{screen_columns}) 
		= $term->get_screen_size();
	logpkg('debug', "screensize is $text->{screen_lines} lines x $text->{screen_columns} columns");

	revise_prompt();
	setup_event_loop(); 
}
sub restore_default_keymap {
	set_keymap('emacs');
}
sub initialize_nama_keymap {
	state $first_time = 1;
	my $nama;
	# delete old one
	if (not $first_time){
		$nama = $term->get_keymap_by_name('nama');
		$term->free_keymap($nama) if defined $nama;
		$first_time = 0;
	}
	
	# create new one
	$nama_keymap 	  = $term->copy_keymap(get_keymap('emacs'));
	$nama_meta = $term->copy_keymap(get_keymap('emacs-meta'));
	
	$term->set_keymap_name('nama',$nama);
	$term->set_keymap_name('nama_meta',$nama_meta);
	
	# activate it
	set_keymap('nama');
	
	# always enable spacebar toggle
	$term->bind_keyseq(' ','spacebar_action');

	# meta key
	$term->generic_bind("\e", $nama_meta);
	
}
sub toggle_hotkeys {
	state $mode = 0; # 0: spacebar_only, 1: current_hotkey_set
	initialize_nama_keymap(), 
	$mode = 0, return if $mode == 1; # we've reset the keymap, standard cursor commands
	$mode = 1;
	setup_hotkeys($text->{hotkey_mode}, 'quiet');# we've activated the hotkeys again.
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
	$text->{hotkey_mode} = $map;
	initialize_nama_keymap();
	%bindings = hotkey_map($map);
# 	say "bindings: " ;
# 	while( my($k,$v) = each %bindings){
# 		say "$k: $v";
# 	}
	for my $key (keys %bindings) {
		my $seq = (length $key == 1 ? $key : $escape_code{$key});
		$term->bind_keyseq($seq, 'hotkey_dispatch');
	}
	pager("\nHotkeys set for $map!") unless $quiet;
	list_hotkeys();
	display_status();
}
sub hotkey_dispatch {                                                                          
	my ($seq) = string_to_escape_code($term->Attribs->{executing_keyseq});
	my $name = length $seq == 1 ? $seq : $keyname{$seq};
	my $function = $bindings{$name};
	throw(qq("$name": key has no defined function.)), return if not $function;
	no strict 'refs';
	$function->();
	display_status();
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
	my %bindings_lc;
	while( my($key,$function) = each %bindings ){
		$bindings_lc{lc $key} = $function
	}
	%bindings = %bindings_lc;
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
		my $mark = join ' ', 'Current mark:', qq("$this_mark->name"), 'at', $this_mark->time;
		$bar .= $mark;
	}
	$bar .= "Jump size: $config->{playback_jump_seconds}s, ";
	$bar .= "Mark bump: $config->{mark_bump_seconds}s " ;
	$bar
}
sub beep_trim_start 	{ beep( $config->{beep}->{trim_start   })}
sub beep_trim_end   	{ beep( $config->{beep}->{trim_end     })}
sub beep_command_error 	{ beep( $config->{beep}->{command_error})}
sub beep_end_of_list    { beep( $config->{beep}->{end_of_list  })}

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
	this_param() > 1 ? set_current_parameter( this_param() - 1)
						: beep_end_of_list()
}
sub next_param {
	this_param()  < scalar this_op_o()->params->@* 
		? set_current_parameter( this_param() + 1)
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
sub setup_event_loop {
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

my @keynames_lc = map lc, @keynames;
@keynames = @keynames_lc;

my %escape_code_lc;
while( my($key,$seq) = each %escape_code ){
	$escape_code_lc{lc $key} = $seq;
}
%escape_code = %escape_code_lc;

%keyname = ( reverse %escape_code );

1;
__END__
