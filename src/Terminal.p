# ----------- Terminal related subroutines ---------

package ::;
use v5.36;
no warnings 'uninitialized';
use Carp;
use ::Globals qw(:singletons $this_bus $this_track $text);
use ::Log qw(logpkg logsub);
use Data::Dumper::Concise;
use List::MoreUtils qw(first_index);
use File::Basename qw(fileparse);
#use DDP;



=comment

widget tree:

tickit
	term
vbox (root) 
	scroller
		item
		item
    entry

=cut

{
my ($root, $tickit, $term, $scroller, $entry);
$text->{loop} = IO::Async::Loop->new;

sub initialize_terminal {
	$root =	Tickit::Widget::VBox->new; 
	$scroller = Tickit::Widget::Scroller->new;
	$tickit = Tickit::Async->new( root => $root);
	$text->{tickit} = $tickit;
	$text->{term} = $term = $tickit->term;
	my $lines = $term->lines;
	create_entry_widget();
	setup_key_bindings();
	$root->add($scroller, valign => 'top', force_size => $lines - 2); 
	$root->add($entry, valign => 'top');
}

sub create_entry_widget {

	my $do_command = sub { my ( $self, $line ) = @_; 
							print_to_terminal($line); 
							$line =~ s/^.+?>\s*//;
							process_line($line); 
							show_prompt();
						}; 

	$entry = Tickit::Widget::Entry->new( 
		text 	 => prompt(),
		on_enter => $do_command,
	);

	show_prompt();
}
sub setup_key_bindings {

	Tickit::Widget::Entry::Plugin::Completion->apply($entry, 
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

	my $spacebar = sub {
		if ( $config->{press_space_to_start}
				and $entry->position == length prompt()
				and ! ($mode->song or $mode->live) )
		{ toggle_transport() }
		else { $entry->on_text(' ') }
	};

	$entry->bind_keys( 
	'Up' 		=> sub { previous_command() }, 
	'Down'		=> sub { next_command()     }, 
	'Left'		=> $left,
	'C-a'	  	=> sub { $entry->set_position( length prompt() ) },
	'Home'  	=> sub { $entry->set_position( length prompt() ) },
	'C-k'		=> sub { $entry->text_delete(  $entry->position, 999) },
	'C-u'   	=> sub { $entry->text_delete(  
							length prompt(), 
							$entry->position - length prompt() ) },
	'C-h'   	=> $backspace,
	'Backspace' => $backspace,
    ' '			=> $spacebar,
	'C-z'		=> \&suspend,
	); 

}

sub suspend
{
	$term->pause;
	kill STOP => $$;
	$term->resume;
}

sub show_prompt {
	$entry->set_text(prompt());
	$entry->set_position(99); 
}
 
sub command {
	substr( $entry->text, length prompt() )
}

sub print_to_terminal (@text) {
	chomp for @text;
	$scroller->push( Tickit::Widget::Scroller::Item::Text->new( join ' ', @text ));
	$scroller->scroll_to_bottom;
}

sub prompt { 
	logsub((caller(0))[3]);
		my $prompt = join ' ', 'nama', git_branch_display(), bus_track_display(),'> ';
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
	$entry->set_text(join " ",prompt(),$text->{command_history}->[$text->{command_index}])
}
 
sub command {
	substr( $entry->text, length prompt() )
}

}
our ($old_output_fh);
sub redirect_stdout {
	open(FH, '>', '/dev/null') or die; 
	FH->autoflush;
	$old_output_fh = select FH;
   	tie *FH, 'Tie::Simple', '', 
     		WRITE     => sub {  },
			PRINT 		=> sub { my $text = $_[1]; print_to_terminal($text) },
             PRINTF    => sub {  },
             READ      => sub {  },
             READLINE  => sub {  },
             GETC      => sub {  },
             CLOSE     => sub {  };
			
}
BEGIN { $SIG{__WARN__} = \&filter_print_to_terminal }
$SIG{INT} = \&cleanup_exit;
sub filter_print_to_terminal {
	print_to_terminal(@_) unless $_[0] =~ /ScrollBox/;
}

sub restore_stdout {
	select $old_output_fh;
	close FH;
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
=comment
	logsub((caller(0))[3]);
	# hack to allow suppressing prompt
	$override = ($_[0] eq "default" ? undef : $_[0]) if defined $_[0];
    $override//prompt()
=cut
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
	@output = map{"$_\n"} map{ split "\n"} @output;
	return unless scalar @output;
	print for @output;
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
	push @keywords, keys %{$text->{midi_cmd}} if $config->{use_midi};
	$text->{keywords}    = [sort {$a cmp $b} @keywords ];
	$text->{autocomplete_keywords}->@* = grep { not /_/ } $text->{keywords}->@*;
	$text->{executables} = [sort {$a cmp $b} executables()];
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

	if (command() =~ /load(.project)? / )
	{
		$keywords = $text->{project_list};
	}

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
	 print_to_terminal("found", scalar @result, "matches") if @result > 10;
	 print_to_terminal($_) for @result;
	 print_to_terminal(' ');
	#}

	@result;
}
	
sub executables {
	# if starts with letter, return executables for that letter
	# if starts with ./ ../ ~/ / return the appropriate set of executables
	my @path = "$ENV{HOME}/bin";
	# split ':', $ENV{PATH};
	my @executables = ();
	for my $dir	(@path)
	{
		my $p = path($dir);
		push @executables, grep { -x $_ } map { $_->stringify} $p->children;
	}
	@executables
}
1;
