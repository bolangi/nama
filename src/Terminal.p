# ----------- Terminal related subroutines ---------

use v5.36;

# A Scroller item has no window of its own, so it cannot directly contain the
# command Entry widget.  This one-line item reserves the Entry's place in the
# Scroller; its render callback keeps a floating child window over that line.
package ::TerminalEntryItem;

sub new ($class, %args) {
	bless { on_render => $args{on_render} }, $class
}

sub height_for_width ($self, $width) { 1 }

sub render ($self, $rb, %args) {
	for my $line ($args{firstline} .. $args{lastline}) {
		$rb->goto($line, 0);
		$rb->erase_to($args{width});
	}
	$self->{on_render}->() if $self->{on_render};
}

package ::;
use v5.36;
no warnings 'uninitialized';
use Carp;
use ::Globals qw(:singletons $this_bus $this_track $text);
use ::Log qw(logpkg logsub emit_output set_output_sink);
use Data::Dumper::Concise;
use List::MoreUtils qw(first_index);
use File::Basename qw(fileparse);
use File::Temp qw(tempfile);
#use DDP;



=begin comment

widget tree:

tickit
	term
rootwin
	vbox
		scroller
			item
			item
    entry

=end comment

=cut

{
my ($rootwin, $vbox, $tickit, $term, $scroller, $entry);
my ($entry_item, $entrywin, $scrollerwin, $scroller_geom_ev);
my $entry_widget_present;
$text->{loop} = IO::Async::Loop->new;

sub initialize_terminal {
	$vbox =	Tickit::Widget::VBox->new; 
	$scroller = Tickit::Widget::Scroller->new;
	$text->{tickit}  = $tickit  = Tickit::Async->new( root => $vbox);
	# Nama owns the IO::Async loop.  Attach Tickit explicitly so the text and
	# graphical interfaces both service the same loop rather than allowing
	# Tickit::Async to create one implicitly.
	$text->{loop}->add($tickit);
	$text->{term}    = $term    = $tickit->term;
	$text->{rootwin} = $rootwin = $tickit->rootwin;
	my $lines = $term->lines;
	$vbox->add($scroller, valign => 'top', force_size => $lines - 2); 

	$entry_item = ::TerminalEntryItem->new(
		on_render => \&position_entry_widget,
	);
	$scroller->set_on_scrolled(sub { position_entry_widget() });
}

sub finish_terminal_startup {
	create_entry_widget();
	setup_key_bindings();
	$tickit->later(\&install_entry_item);
}

sub install_tk_tickit_bridge {
	can_load(modules => { '::TkTickitBridge' => undef })
		or croak 'Unable to load TkTickitBridge';
	$text->{tk_tickit_bridge} = ::TkTickitBridge->new(
		widget => $gui->{mw},
		term   => $term,
	)->install;
}

sub create_entry_widget {

	my $do_command = sub { my ( $self, $line ) = @_; 
							print_to_terminal($line); 
							$line =~ s/^.+?>\s*//;
							process_line($line); 
							show_prompt();
						}; 

	$text->{entry} = $entry = Tickit::Widget::Entry->new( 
		text 	 => prompt(),
		on_enter => $do_command,
	);

	show_prompt();
}

sub install_entry_item {
	return if $entry_widget_present;

	unless ($scroller->window) {
		$tickit->later(\&install_entry_item);
		return;
	}

	$scroller->push($entry_item);
	$entry_widget_present = 1;
	set_output_sink(sub ($message) {
		$tickit->later(sub { print_to_terminal($message) });
	});
	$scroller->scroll_to_bottom;
	position_entry_widget();
}

sub position_entry_widget {
	return unless $entry_widget_present;

	my $parent = $scroller->window or return;

	if (!defined $scrollerwin or "$scrollerwin" ne "$parent") {
		if (defined $scrollerwin and defined $scroller_geom_ev) {
			$scrollerwin->unbind_event_id($scroller_geom_ev);
		}
		if (defined $entrywin) {
			$entry->set_window(undef);
			$entrywin->close if $entrywin->can('close');
			undef $entrywin;
		}

		$scrollerwin = $parent;
		$scroller_geom_ev = $scrollerwin->bind_event(
			geomchange => sub { position_entry_widget() },
		);
	}

	my ($line, $offscreen) = $scroller->item2line($entry_item, 0, 1);
	if (!defined $line or defined $offscreen) {
		$entrywin->hide if defined $entrywin and $entrywin->is_visible;
		return;
	}

	if (!defined $entrywin) {
		$entrywin = $scrollerwin->make_float(
			$line, 0, 1, $scrollerwin->cols,
		);
		$entry->set_window($entrywin);
		$entry->take_focus;
		return;
	}

	my $was_visible = $entrywin->is_visible;
	$entrywin->change_geometry($line, 0, 1, $scrollerwin->cols);
	unless ($was_visible) {
		$entrywin->show;
		$entry->take_focus;
	}
}
sub setup_key_bindings {

	my $completion_engine = Tickit::Widget::Entry::Plugin::Completion->apply($entry,
		gen_words => \&gen_words, 
		use_popup => 0, 
		ignore_case => 1); 

	my $backspace  = sub { 
		my $stop_pos = length prompt();
		$entry->text_delete( $entry->position - 1, 1 ) 
			unless $entry->position <= $stop_pos 
	};
	my $left = sub { 
		my $stop_pos = length prompt();
		$entry->set_position( $entry->position - 1 ) 
			unless $entry->position <= $stop_pos 
	};

	my $toggle_transport = sub {
		if ( $config->{press_space_to_start}
				and $entry->position == length prompt()
				) 
		{ toggle_transport() }
		else { $entry->on_text(' ') }
	};

	sub beginning_of_line     		{ $entry->set_position( length prompt() ) }
	sub delete_to_end_of_line 		{ $entry->text_delete(  $entry->position, 999) }
	sub delete_to_beginning_of_line { $entry->text_delete(  length prompt(), 
															$entry->position - length prompt() ) }

	$text->{entry_bindings} = {

    ' '			=> $toggle_transport,
	'Left'		=> $left,
	'C-h'   	=> $backspace,
	'Backspace' => $backspace,
	'Up' 		=> \&previous_command, 
	'Down'		=> \&next_command, 
	'C-a'	  	=> \&beginning_of_line,
	'Home'  	=> \&beginning_of_line,
	'C-k'		=> \&delete_to_end_of_line,
	'C-u'   	=> \&delete_to_beginning_of_line,
	'C-c'       => \&cleanup_exit,
	'C-z'		=> \&suspend,
	 user_hotkeys(),
};

	$entry->bind_keys( $text->{entry_bindings}->%*	); 
	$entry->bind_keys(
		Tab => sub {
			$entry->text_splice($entry->position, 0, ' ')
				if command() =~ /^\s*(?:load|load-project|link|link-track)$/;
			my $completing_project =
				command() =~ /^\s*(?:load|load-project|link|link-track)\s+$/;
			$completion_engine->key_complete($completing_project);
		},
	);

}
sub user_hotkeys {
	my $mappings = $config->{hotkeys}->{user};
	return unless defined $mappings;
	no strict 'refs';
	map{ $_ => \&{$mappings->{$_}} } keys $mappings->%*
	#map{ $_ => eval '\&'. $mappings->{$_} } keys $mappings->%*
}
	

sub disable_entry_bindings {
	$entry->bind_keys( map {$_, undef} keys $text->{entry_bindings}->%* );
	
}

sub suspend
{
	$term->pause;
	# Suspend the entire foreground job, including any audio-engine children.
	# Stopping only Nama leaves those children running, so the shell does not
	# regain control until the terminal sends a second stop signal.
	kill STOP => 0;
	$term->resume;

	# Commands run by the shell while Nama is stopped may have changed any part
	# of the terminal.  Tickit still has the old screen contents in its damage
	# model, so invalidate the whole window after fg instead of waiting for a
	# focus or resize event to happen to repaint it.
	$rootwin->expose;
}

sub show_prompt {
	$entry->set_text(prompt());
	$entry->set_position(99); 
}

sub terminal_print (@text) {
	my $output = join q(), map { defined $_ ? $_ : q() } @text;
	emit_output($output, \*STDOUT);
}

sub terminal_say (@text) {
	my $output = join q(), map { defined $_ ? $_ : q() } @text;
	$output .= "\n" unless $output =~ /\n\z/;
	terminal_print($output);
}

sub terminal_warn (@text) {
	my $output = join q(), map { defined $_ ? $_ : q() } @text;
	emit_output($output, \*STDERR);
}
 
sub print_to_terminal (@text) {
	return unless defined $scroller;
	my $output = join q(), map { defined $_ ? $_ : q() } @text;
	$output =~ s/\n\z//;

	if ($entry_widget_present) {
		$scroller->pop(1);
		$entry_widget_present = 0;
	}
	$scroller->push(
		Tickit::Widget::Scroller::Item::Text->new($output),
	);
	if (defined $entry_item and $scroller->window) {
		$scroller->push($entry_item);
		$entry_widget_present = 1;
	}
	$scroller->scroll_to_bottom;
	position_entry_widget();
}

sub prompt_for_text {}
sub prompt_approve {}

sub prompt (@args) {
	return confirmation_prompt(@args) if @args;

	logsub((caller(0))[3]);
	join ' ', 'nama', git_branch_display(), bus_track_display(),'> ';
}

sub confirmation_prompt ($message, $default) {
	my $default_answer = $default =~ /^(?:1|y|yes)$/i ? 1
		: $default =~ /^(?:0|n|no)$/i ? 0
		: croak "prompt default must be yes or no";
	my $choices = $default_answer ? '[y]/n' : 'y/[n]';
	my $answer;

	$entry->set_text("$message $choices");
	$entry->set_position(length $entry->text);

	my $set_answer = sub ($value) {
		$answer = $value;
	};
	$entry->bind_keys(
		y     => sub { $set_answer->(1) },
		Y     => sub { $set_answer->(1) },
		n     => sub { $set_answer->(0) },
		N     => sub { $set_answer->(0) },
		Enter => sub { $set_answer->($default_answer) },
	);

	$text->{loop}->loop_once while !defined $answer;

	$entry->bind_keys(
		y     => undef,
		Y     => undef,
		n     => undef,
		N     => undef,
		Enter => 'key_enter_line',
	);
	print_to_terminal("$message $choices ".($answer ? 'y' : 'n'));
	show_prompt();
	return $answer;
}
sub next_command {
	$text->{command_index}++ unless $text->{command_index} == scalar $text->{command_history}->@*;
	print_command();
}
sub previous_command {
	$text->{command_index}-- unless $text->{command_index} == 0;
	print_command();
}
sub print_command {
	$entry->set_text(prompt().$text->{command_history}->[$text->{command_index}]);
	$entry->set_position(99);
}

 
sub command {
	substr( $entry->text, length prompt() )
}


# bottom line status bar for hot key modes

{
my ($popup, $expose_ev, $key_ev, $status, $mode, $hotkeys_active);
sub enable_hotkeys  { 
	popup($mode), $hotkeys_active = 1 if defined $mode
}
sub disable_hotkeys { 
	return unless defined $expose_ev;
	$popup->unbind_event_id($_) for ($expose_ev, $key_ev); 
	$hotkeys_active = 0; 
	$entry->take_focus 
}
sub toggle_hotkeys { if (hotkeys_active()){  disable_hotkeys() } else { enable_hotkeys() } }
sub hotkeys_active { defined $popup and $popup->is_focused }

sub popup ($mode) {
	my ($top, $left, $lines, $cols) = ($text->{rootwin}->lines - 1, 0, 1, $text->{rootwin}->cols); 
	
   $text->{popup} = $popup = $rootwin->make_popup($top, $left, $lines, $cols);

	$popup->pen->chattrs({ bg => 'yellow', fg => 'black' });

	$status = status_bar($mode);
	$popup->take_focus;

	# We use expose event to update text, because event
	# provides render buffer. 
	$expose_ev = $popup->bind_event( expose => sub ( $win, $, $info, @ ) {
    	 my $rb = $info->rb;
         $rb->goto(0, 0 );
         $rb->erase_to( $rootwin->cols );
         $rb->text_at( 0,0,$status, $popup->pen);
    });
   $key_ev = $popup->bind_event( key => sub ( $rootwin, $, $info, @ ) { process_keystrokes($mode, $info) } );
   $popup->take_focus;
   $popup->show;


}

{
my $i = 0;
sub process_keystrokes ($mode, $info) {
	$i++;
	my $str = $info->str;
	my $action = $config->{hotkeys}->{$mode}->{$str};
	if (defined $action){
		no strict 'refs';
		&$action();	
		set_popup_text(status_bar($mode));
	}
	else {
		# throw("$str: no binding found in $mode hotkey mode.");
	}
	return 1
}
}

sub set_popup_text ($str) { 
		return if not defined $popup; 
		$status = $str; 
		$popup->expose 
}

sub set_hotkey_mode ($m) {
	popup($m);
	$mode = $m;	
	$hotkeys_active = 1;
}
sub activate_effect_hotkeys { set_hotkey_mode('effect') }

} # popup 

} # tickit UI
BEGIN { $SIG{__WARN__} = \&filter_print_to_terminal }
$SIG{INT} = \&cleanup_exit;
sub filter_print_to_terminal {
	terminal_warn(@_) unless $_[0] =~ /ScrollBox/;
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
}
=begin comment
	logsub((caller(0))[3]);
	# hack to allow suppressing prompt
	$override = ($_[0] eq "default" ? undef : $_[0]) if defined $_[0];
	$override//prompt()

=end comment

=cut
}

sub throw (@text) {
	logsub((caller(0))[3]);
	terminal_say(@text)
}
sub pager {
	logsub((caller(0))[3]);
	my $output = join q(), map { defined $_ ? $_ : q() } @_;
	return unless length $output;
	return unless $text->{term};

	my $width = $text->{term}->cols;
	my $lines = 0;
	$lines += int(((length($_) || 1) - 1) / ($width || 1)) + 1
		for split /\n/, $output, -1;
	if ($lines <= $text->{term}->lines - 1) {
		terminal_print($output, $output =~ /\n\z/ ? "\n" : "\n\n");
		return;
	}

	my ($fh, $filename) = tempfile(UNLINK => 1);
	print {$fh} $output;
	close $fh;

	$text->{term}->pause;
	system 'less', '-R', $filename;
	$text->{term}->resume;
	$text->{rootwin}->expose;
	$text->{term}->flush;
	$text->{entry}->take_focus;
}
sub file_pager {};
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
	push @keywords, keys %{$text->{iam}};
	push @keywords, (keys $text->{midi_cmd}->%*) if $config->{use_midi};
	my %seen;
	# Silently ignore duplicate command names, which is the
	# case for *-register
	@keywords = grep { ! $seen{$_}++ } @keywords;
	$text->{keywords}    = [sort {$a cmp $b} @keywords ];
	$text->{autocomplete_keywords}->@* = grep { not /_/ } $text->{keywords}->@*;
	#$text->{executables} = executables(); # too many for our current algorithm
	$text->{project_list} = project_list();
	$text->{effects}     =  [sort {$a cmp $b} keys $fx_cache->{partial_label_to_full}->%*];
}

sub project_list { 
	my $root = path(project_root());
	[ sort { $a cmp $b }
	 	map { $_-> basename } 
		grep { -d } 
		$root->children ]; 
}

sub gen_words {
	state $pwd = path(getcwd);
	my %args = @_;
	my $word = $args{word};
	my $entry = $args{entry};
	my $wordpos = $args{wordpos};
	my $plen = length $word;
	my $keywords = [];
	my $is_command;

	if (command() =~ /^\s*(?:load|load-project|link|link-track) / )
	{
		$keywords = project_list();
	}
#	elsif (command() =~ /^! / )
#	{
#		$keywords = $text->{executables}
#	}

	### handle file paths - import command only

	elsif (command() =~ /imp(ort)?(-audio|-midi)? / ) # followed by a space
	{
	#print_to_terminal("word: $word");

		## substitute environment variable 

		my ($var);
		if ( ($var) = $word =~ m[  \$ (\w+) $ ]x  and $ENV{$var}){
			#print_to_terminal("var: $var");
			$pwd = path($ENV{$var});
			my $item = $pwd->stringify;
			if ($pwd->is_dir){
				$item =~ s(/*$)(/);
			}
			$entry->text_splice($wordpos, $plen, $item) ;
			return;
		}
		if ( $word eq '~' or $word =~ m(^~/) )
		{
			#say "got tilde";
			$word =~ s{~/?}{$ENV{HOME}/};
			$pwd = path($ENV{HOME});
			$entry->text_splice($wordpos, $plen, $word) ;
			return
		}
		my ($stub, $dir) =  fileparse($word);
		#print_to_terminal("word: $word, dir: $dir, stub: $stub");

		$pwd = path($dir);

		if ( $word =~ m(/) )
		{
			@$keywords = sort { $a cmp $b } map { $_->stringify} $pwd->children;
			if ($stub =~ /\S/)
			{
				@$keywords = grep { m(  / $stub [^/]* $ )x } @$keywords;
			}
		}
		else {
			@$keywords = sort { $a cmp $b } map { $_->basename} $pwd->children;
			if ($stub =~ /\S/)
			{
				@$keywords = grep { /^$stub/ } @$keywords;
			}
		}
		map { path($_)->is_dir and s{$}{/} } @$keywords;
		#print_to_terminal("found",scalar @$keywords , "files in this directory");
		#print_to_terminal($_) for @$keywords; 
		
	}
	elsif ( command() =~ /^ \s* ! /x )
	{ 
	   	$keywords = $text->{executables};
	}
	elsif ( command() =~ / (afx) | (add.effect) /x )
	{ 
	   	$keywords = $text->{effects};
	}
	else { 
		$keywords = $text->{autocomplete_keywords} ;
		$is_command++;
	}

	#print_to_terminal("found ".scalar @$keywords. " keywords");
	#print_to_terminal($_) for @$keywords[0..10];
	my $first = undef;
	my $last = scalar @$keywords - 1;
	for (my $i = 0;      $i <= $last; $i++)  { $first = $i,     last if @$keywords[$i] =~ /^$word/i }
	return unless defined $first;
	for (my $i = $first; $i <= $last; $i++)  { $last  = $i - 1, last if @$keywords[$i] !~ /^$word/i }
	my @result = @$keywords[$first .. $last];

	# don't print if full paths;
	#unless (grep { m(/) } @result)
	#{
	 if (@result > 8) {
	 	print_to_terminal("found", scalar @result, "matches");
	 	my $width = 2;
	 	for (@result) {
	 		$width = length($_) + 2 if length($_) + 2 > $width;
	 	}
	 	my $columns = int($text->{term}->cols / $width) || 1;
	 	my $rows = int((@result + $columns - 1) / $columns);
	 	for my $row (0 .. $rows - 1) {
	 		my @items = map $result[$row + $_ * $rows], 0 .. $columns - 1;
	 		pop @items while @items and not defined $items[-1];
	 		print_to_terminal(join '', map { sprintf "%-*s", $width, $_ } @items);
	 	}
	 }
	 else {
	 	print_to_terminal($_) for @result;
	 }
	 print_to_terminal(' ');
	#}

	@result;
}
	
sub executables {
	# if starts with letter, return executables for that letter
	# if starts with ./ ../ ~/ / return the appropriate set of executables
	#my @path = "$ENV{HOME}/bin";
	my @path = split ':', $ENV{PATH};
	my @executables = ();
	for my $dir	(@path)
	{
		my $p = path($dir);
		push @executables, grep { -x $_ } map { $_->stringify} $p->children;
	}
	@executables = sort @executables;
	\@executables
}
sub status_bar { 
	my $hotkey_mode = shift;
	my %bar = (effect => \&param_status_bar,
	           jump  => \&jump_status_bar,
			   bump  => \&jump_status_bar );
	my $status = $bar{$hotkey_mode}->();
	my $name  = $this_track->name; 
	$status =  "[$name] [$hotkey_mode] $status";
}

sub bump_status_bar {}

	
sub param_status_bar {
	return " no selected effect" unless $this_track->op;
	return " no effect found"    unless defined this_effect();
	my $effect_info = join " ",
				this_op_id(), 
				this_effect()->fxname ? this_effect()->fxname : '(unnamed)';
# 	if (this_effect()->no_params) {
# 		return "$effect_info (no parameters to adjust)";
# 	}
	my $param_pos = this_param() - 1;
	my $param_info = parameter_info(this_op_id(), $param_pos);
	if (this_effect()->is_read_only ){
		return "$effect_info $param_info - no adjustment possible";
	}
	$param_info .= " Step: ". ::Effect::param_stepsize();
	return "$effect_info $param_info";
}
sub jump_status_bar {
	return unless $this_track; 
	my $pos = ::current_timeline_position();
	my $bar = "playback at ${pos}s, ";
	if (defined $this_mark) {
		my $mark = join ' ', 'Current mark:', $this_mark->name, 'at', $this_mark->time;
		$bar .= $mark;
	}
	$bar .= "Jump size: $config->{playback_jump_seconds}s, ";
	$bar .= "Mark bump: $config->{mark_bump_seconds}s " ;
	$bar
}
sub clip_start_beep 	{ beep( $config->{beep}->{clip_start})}
sub clip_end_beep       { beep( $config->{beep}->{clip_end})}
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
1;
