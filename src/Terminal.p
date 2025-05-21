# ----------- Terminal related subroutines ---------

package ::;
use v5.36;
no warnings 'uninitialized';
use Carp;
use ::Globals qw(:singletons $this_bus $this_track);
use ::Log qw(logpkg logsub);
use Data::Dumper::Concise;
use List::MoreUtils qw(first_index);

sub initialize_prompt {
	print prompt();
}

sub initialize_terminal {

=comment

vbox - root
	scrollbox 
		vbox 
		   static
		   static
		   ...
	entry

=cut

my $root = 		Tickit::Widget::VBox->new; 
my $vbox = 		Tickit::Widget::VBox->new; # contains multiple items to scroll through
my $scrollbox = Tickit::Widget::ScrollBox->new->set_child( $vbox );
for (1..100){
my $a = 100 - $_;
$vbox->add( Tickit::Widget::Static->new( text   => "a thousand bottles minus $_ is $a \n" ))
}

my $tickit = Tickit->new( root => $root);
my $term = $tickit->term;
my $lines = $term->lines;
 
$root->add($scrollbox, force_size => $lines - 1); # , expand => 1);
my $entry = 	Tickit::Widget::Entry->new( 
	text 	 => $prompt,
	on_enter => sub {
      	my ( $self, $line ) = @_;
		prompt();
	}
	);
$root->add($entry);
 
=comment - doesn't work except on console - use event bindings
my $win = $tickit->rootwin;

$win->bind_key('M-Home', 
	sub{ 	my($console,$key) = @_;
			$scroller->scroll_to_top;
		} );
$win->bind_key('M-End', 
	sub{ 	my($console,$key) = @_;
			$scroller->scroll_to_bottom;
		} );

=cut
prompt();
$tickit->run;
	# handle Control-C from terminal

	
	$project->{events}->{sigint} = AE::signal('INT', \&cleanup_exit); 
	# responds in a more timely way than $SIG{INT} = \&cleanup_exit; 

	$SIG{USR1} = sub { project_snapshot() };
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
	logsub((caller(0))[3]);
	# hack to allow suppressing prompt
	$override = ($_[0] eq "default" ? undef : $_[0]) if defined $_[0];
    $text->{term}->callback_handler_install($override//prompt(), \&process_line)
		if $text->{term}
}
}

	
sub prompt { 
	logsub((caller(0))[3]);
	join ' ', 'nama', git_branch_display(), bus_track_display(),'> '
}
sub detect_spacebar {

	# create a STDIN watcher to intervene when space
	# received in column one
	
	$project->{events}->{stdin} = AE::io(*STDIN, 0, sub {
		&{$text->{term_attribs}->{'callback_read_char'}}();
		my $buffer = $text->{term_attribs}->{line_buffer};
		my $trigger = ' ';
		if ( $config->{press_space_to_start} 
				and ($buffer eq $trigger)
				and ! ($mode->song or $mode->live) )
		{ 	
			toggle_transport();	

			# reset command line, read next char
			
			$text->{term_attribs}->{line_buffer} = q();
			$text->{term_attribs}->{point} 		= 0;
			$text->{term_attribs}->{end}   		= 0;
			$text->{term}->stuff_char(10);
			&{$text->{term_attribs}->{'callback_read_char'}}();

			
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
	@output = map{"$_\n"} map{ split "\n"} @output;
	return unless scalar @output;
	print(@output);
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
	push @keywords, grep{$_} map{split " ", $text->{commands}->{$_}->{short}} @keywords;
	push @keywords, keys %{$text->{iam}};
	push @keywords, keys %{$fx_cache->{partial_label_to_full}};
	push @keywords, keys %{$text->{midi_cmd}} if $config->{use_midi};
	push @keywords, "Audio::Nama::";
	push @keywords, pwd_files();
	@{$text->{keywords}} = @keywords
	
}
sub pwd_files {
	my $dir = '.';
	my $pwd = path($dir);
	grep {-f} $pwd->children;
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
