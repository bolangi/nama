# ----------- Terminal related subroutines ---------

package ::;
use v5.36;
no warnings 'uninitialized';
use Carp;
use ::Globals qw(:singletons $this_bus $this_track $text);
use ::Log qw(logpkg logsub);
use Data::Dumper::Concise;
use List::MoreUtils qw(first_index);


=comment - widgets

Tree:

tickit
	term
vbox (root)
	scrollbox 
		vbox 
		   static
		   static
		   ...
entry

Names:

$text->{tickit} 
$text->{root} 
$text->{vbox} 
$text->{scrollbox} 
$text->{term} 
$text->{entry} 
=cut

{
my ($root, $vbox, $tickit, $term, $scrollbox, $entry);
$text->{loop} = IO::Async::Loop->new;
sub initialize_terminal {
$root = 		Tickit::Widget::VBox->new; 
$vbox = 		Tickit::Widget::VBox->new; # contains multiple items to scroll through
$scrollbox = Tickit::Widget::ScrollBox->new->set_child( $vbox );
$tickit = Tickit::Async->new( root => $root);
$text->{tickit} = $tickit;
$text->{term} = $term = $tickit->term;
my $lines = $term->lines;
 
$root->add($scrollbox, valign => 'top', force_size => $lines - 2); 
my $label; 
my $do_command = sub { my ( $self, $line ) = @_; 
						print_to_terminal($line); 
						$line =~ s/^.+?>\s*//;
						process_line($line); 
						$self->set_text(prompt());
						$self->set_position(99); 
					}; 
$entry = Tickit::Widget::Entry->new( text 	 => 'enter nama command (h for help) > ', on_enter => $do_command,);
Tickit::Widget::Entry::Plugin::Completion->apply($entry, gen_words => \&gen_words, use_popup => 1 ); 
$entry->bind_keys( 'Up' 	=> sub { previous_command() }, 
					'Down'	=> sub { next_command()     }, 
); 
#$entry->set_text(prompt()); 
$entry->set_position(99);
$root->add($entry, valign => 'bottom');
for (1..$tickit->lines){ print_to_terminal(' ') }
}
 
sub print_to_terminal ($txt) {
	$vbox->add( Tickit::Widget::Static->new( text => $txt ));
	$scrollbox->scroll_to(1e5);
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

sub detect_spacebar {
=comment
		if ( $config->{press_space_to_start} 
				and ($buffer eq $trigger)
				and ! ($mode->song or $mode->live) )
			toggle_transport();	
=cut
warn ("not implemented");
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
	#push @keywords, grep{$_} map{split " ", $text->{commands}->{$_}->{short}} @keywords;
	push @keywords, keys %{$text->{iam}};
	push @keywords, keys %{$fx_cache->{partial_label_to_full}};
	push @keywords, keys %{$text->{midi_cmd}} if $config->{use_midi};
	push @keywords, "Audio::Nama::";
	push @keywords, pwd_files();
	@{$text->{keywords}} = sort {lc $a cmp lc $b} @keywords
	
}
sub gen_words {
	my %args = @_;
	my $word = $args{word};
	my $keywords = $text->{keywords};
	my $first = 0;
	my $last = scalar @$keywords - 1;
	for (my $i = 0;      $i <= $last; $i++)  { $first = $i,     last if @$keywords[$i] =~ /^$word/i }
	return unless $first;
	for (my $i = $first; $i <= $last; $i++)  { $last  = $i - 1, last if @$keywords[$i] !~ /^$word/i }
	@$keywords[$first .. $last]
}
sub pwd_files {
	my $dir = '.';
	my $pwd = path($dir);
	grep {-f} $pwd->children;
}

1;
