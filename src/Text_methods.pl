use Carp;
use Text::Format;
$text = new Text::Format {
	columns 		=> 65,
	firstIndent 	=> 0,
	bodyIndent		=> 0,
	tabstop			=> 4,
};

sub new { my $class = shift; return bless { @_ }, $class; }

sub show_versions {
 	print "All versions: ", join " ", @{$::this_track->versions}, $/;
}

sub show_effects {
 	map { 
 		my $op_id = $_;
 		 my $i = $effect_i{ $cops{ $op_id }->{type} };
 		 print $op_id, ": " , $effects[ $i ]->{name},  " ";
 		 my @pnames =@{$effects[ $i ]->{params}};
			map{ print join " ", 
			 	$pnames[$_]->{name}, 
				$copp{$op_id}->[$_],'' 
		 	} (0..scalar @pnames - 1);
		 print $/;
 
 	 } @{ $this_track->ops };
}
sub show_modifiers {
	print "Modifiers: ",$this_track->modifiers, $/;
}


sub loop {

	# first setup Term::Readline::GNU

	# we are using Event's handlers and event loop

	package ::;
	$term = new Term::ReadLine("Ecasound/Nama");
	my $attribs = $term->Attribs;
	$attribs->{attempted_completion_function} = \&::Text::complete;
	$term->callback_handler_install($prompt, \&::Text::process_line);

	# store output buffer in a scalar (for print)
	my $outstream=$attribs->{'outstream'};

	# install STDIN handler
	$event_id{stdin} = Event->io(
		desc   => 'STDIN handler',           # description;
		fd     => \*STDIN,                   # handle;
		poll   => 'r',	                   # watch for incoming chars
		cb     => sub{ &{$attribs->{'callback_read_char'}}() }, # callback;
		repeat => 1,                         # keep alive after event;
	 );

	$event_id{Event_heartbeat} = Event->timer(
		parked => 1, 						# start it later
	    desc   => 'heartbeat',               # description;
	    prio   => 5,                         # low priority;
		interval => 3,
	    cb     => \&::heartbeat,               # callback;
	);
	if ( $midi_inputs =~ /on|capture/ ){
		my $command = "aseqdump ";
		$command .= "-p $controller_ports" if $controller_ports;
		open MIDI, "$command |" or die "can't fork $command: $!";
		$event_id{sequencer} = Event->io(
			desc   => 'read ALSA sequencer events',
			fd     => \*MIDI,                    # handle;
			poll   => 'r',	                     # watch for incoming chars
			cb     => \&::process_control_inputs, # callback;
			repeat => 1,                         # keep alive after event;
		 );
		$event_id{sequencer_error} = Event->io(
			desc   => 'read ALSA sequencer events',
			fd     => \*MIDI,                    # handle;
			poll   => 'e',	                     # watch for exception
			cb     => sub { die "sequencer pipe read failed" }, # callback;
		 );
	
	}
	Event::loop();

}
sub wraparound {
	@_ = ::discard_object @_;
	my ($diff, $start) = @_;
	#print "diff: $diff, start: $start\n";
	$event_id{Event_wraparound}->cancel()
		if defined $event_id{Event_wraparound};
	$event_id{Event_wraparound} = Event->timer(
	desc   => 'wraparound',               # description;
	after  => $diff,
	cb     => sub{ ::set_position($start) }, # callback;
   );

}


sub start_heartbeat {$event_id{Event_heartbeat}->start() }

sub stop_heartbeat {$event_id{Event_heartbeat}->stop() }

sub cancel_wraparound {
	$event_id{Event_wraparound}->cancel() if defined $event_id{Event_wraparound}
}

sub process_line {
  $debug2 and print "&process_line\n";
  my ($user_input) = @_;
  $debug and print "user input: $user_input\n";

  if (defined $user_input and $user_input !~ /^\s*$/)
    {
    $term->addhistory($user_input) 
	 	unless $user_input eq $previous_text_command;
 	$previous_text_command = $user_input;
	command_process( $user_input );
    }
}


sub command_process {
	package ::;
	my ($user_input) = shift;
	return if $user_input =~ /^\s*$/;
	$debug and print "user input: $user_input\n";
	my ($cmd, $predicate) = ($user_input =~ /([\S]+)(.*)/);
	if ($cmd eq 'for' 
			and my ($bunchy, $do) = $predicate =~ /\s*(.+?)\s*;(.+)/){
		print "b: $bunchy d: $do\n";
		my @tracks;
		if ($bunchy =~ /\S \S/ or $tn{$bunchy} or $ti[$bunchy]){
			print "multiple tracks found\n";
			@tracks = split " ", $bunchy;
			print "t: @tracks\n";
		} else { @tracks = @{$bunch{$bunchy}};
			print "tt: @tracks\n";
 		}
		print "ttt: @tracks\n";
		for my $t(@tracks) {
			::Text::command_process("$t; $do");
		}
	} elsif ($cmd eq 'eval') {
			$debug and print "Evaluating perl code\n";
			pager( eval $predicate );
			print "\n";
			$@ and print "Perl command failed: $@\n";
	}
	elsif ( $cmd eq '!' ) {
			$debug and print "Evaluating shell commands!\n";
			#system $predicate;
			my $output = qx( $predicate );
			#print "length: ", length $output, $/;
			pager($output); 
			print "\n";
	} else {


	my @user_input = split /\s*;\s*/, $user_input;
	map {
		my $user_input = $_;
		my ($cmd, $predicate) = ($user_input =~ /([\S]+)(.*)/);
		$debug and print "cmd: $cmd \npredicate: $predicate\n";
		if ($cmd eq 'eval') {
			$debug and print "Evaluating perl code\n";
			pager( eval $predicate);
			print "\n";
			$@ and print "Perl command failed: $@\n";
		} elsif ($cmd eq '!') {
			$debug and print "Evaluating shell commands!\n";
			my $output = qx( $predicate );
			#print "length: ", length $output, $/;
			pager($output); 
			print "\n";
		} elsif ($tn{$cmd}) { 
			$debug and print qq(Selecting track "$cmd"\n);
			$this_track = $tn{$cmd};
			$predicate !~ /^\s*$/ and $parser->command($predicate);
		} elsif ($cmd =~ /^\d+$/ and $ti[$cmd]) { 
			$debug and print qq(Selecting track ), $ti[$cmd]->name, $/;
			$this_track = $ti[$cmd];
			$predicate !~ /^\s*$/ and $parser->command($predicate);
		} elsif ($iam_cmd{$cmd}){
			$debug and print "Found Iam command\n";
			my $result = eval_iam($user_input);
			pager( $result );  
		} else {
			if ($cmd eq 'h') { s/h/help/; }
			$debug and print "Passing to parser\n", $_, $/;
			#print 1, ref $parser, $/;
			#print 2, ref $::parser, $/;
			# both print
			$parser->command($_) 
		}    
	} @user_input;
	}
	$ui->refresh; # in case we have a graphic environment
	# package :: scope ends here
}

sub placeholder { $use_placeholders ? q(--) : q() }
sub show_tracks {
    no warnings;
    my @tracks = @_;
    map {     push @format_fields,  
            $_->n,
            $_->name,
            $_->current_version || placeholder(),
            $_->rw,
            $_->rec_status,
            $_->name =~ /Master|Mixdown/ ? placeholder() : 
				$_->rec_status eq 'REC' ? $_->source : placeholder(),
			$_->name =~ /Master|Mixdown/ ? placeholder() : 
				$_->rec_status ne 'OFF' 
					? ($_->send ? $_->send : placeholder())
					: placeholder(),
            #(join " ", @{$_->versions}),

        } grep{ ! $_-> hide} @tracks;
        
    write; # using format below
    $- = 0; # $FORMAT_LINES_LEFT # force header on next output
    1;
    use warnings;
    no warnings q(uninitialized);
}

format STDOUT_TOP =
Track  Name        Ver. Setting  Status   Source      Send
=============================================================
.
format STDOUT =
@>>    @<<<<<<<<<  @|||   @<<     @<<    @|||||||  @|||||||||  ~~
splice @format_fields, 0, 7
.

sub helpline {
	my $cmd = shift;
	my $text = "Command: $cmd\n";
	$text .=  "Shortcuts: $commands{$cmd}->{short}\n"
			if $commands{$cmd}->{short};	
	$text .=  $commands{$cmd}->{what}. $/;
	$text .=  "parameters: ". $commands{$cmd}->{parameters} . $/
			if $commands{$cmd}->{parameters};	
	$text .=  "example: ". eval( qq("$commands{$cmd}->{example}") ) . $/  
			if $commands{$cmd}->{example};
	($/, ucfirst $text, $/);
	
}
sub helptopic {
	my $index = shift;
	$index =~ /^(\d+)$/ and $index = $help_topic[$index];
	my @output;
	push @output, "\n-- ", ucfirst $index, " --\n\n";
	push @output, $help_topic{$index}, $/;
	@output;
}

sub help { 
	my $name = shift;
	chomp $name;
	#print "seeking help for argument: $name\n";
	$iam_cmd{$name} and print <<IAM;

$name is an Ecasound command.  See 'man ecasound-iam'.
IAM
	my @output;
	if ( $help_topic{$name}){
		@output = helptopic($name);
	} elsif ($name == 10){
		@output = map{ helptopic $_ } @help_topic;
	} elsif ( $name =~ /^(\d+)$/ and $1 < 20  ){
		@output = helptopic($name)
	} elsif ( $commands{$name} ){
		@output = helpline($name)
	} else {
		my %helped = (); 
		my @help = ();
		map{  
			my $cmd = $_ ;
			if ($cmd =~ /$name/){
				push( @help, helpline($cmd));
				$helped{$cmd}++ ;
			}
			if ( ! $helped{$cmd} and
					grep{ /$name/ } split " ", $commands{$cmd}->{short} ){
				push @help, helpline($cmd) 
			}
		} keys %commands;
		if ( @help ){ push @output, 
			qq("$name" matches the following commands:\n\n), @help;
		}
	}
	::pager( @output ); 
	
}
sub help_effect {
	my $input = shift;
	print "input: $input\n";
	# e.g. help tap_reverb    
	#      help 2142
	#      help var_chipmunk # preset


	if ($input !~ /\D/){ # all digits
		$input = $ladspa_label{$input}
			or print("$input: effect not found.\n\n"), return;
	}
	if ( $effect_i{$input} ) {} # do nothing
	elsif ( $effect_j{$input} ) { $input = $effect_j{$input} }
	else { print("$input: effect not found.\n\n"), return }
	if ($input =~ /pn:/) {
		print grep{ /$input/  } @effects_help;
	}
	elsif ( $input =~ /el:/) {
	
	my @output = $ladspa_help{$input};
	print "label: $input\n";
	::pager( @output );
	#print $ladspa_help{$input};
	} else { 
	print "$input: Ecasound effect. Type 'man ecasound' for details.\n";
	}
}


sub find_effect {
	my @keys = @_;
	#print "keys: @keys\n";
	#my @output;
	my @matches = grep{ 
		my $help = $_; 
		my $didnt_match;
		map{ $help =~ /\Q$_\E/i or $didnt_match++ }  @keys;
		! $didnt_match; # select if no cases of non-matching
	} @effects_help;
	if ( @matches ){
# 		push @output, <<EFFECT;
# 
# Effects matching "@keys" were found. The "pn:" prefix 
# indicates an Ecasound preset. The "el:" prefix indicates
# a LADSPA plugin. No prefix indicates an Ecasound chain
# operator.
# 
# EFFECT
	::pager( $text->paragraphs(@matches) , "\n" );
	} else { print "No matching effects.\n\n" }
}


sub t_load_project {
	package ::;
	my $name = shift;
	print "input name: $name\n";
	my $name = remove_spaces($name);
	$name =~ s(/$)(); # remove trailing slash
	print ("Project $name does not exist\n"), return
		unless -d join_path project_root(), $name; 
	load_project( name => $name );

	print "loaded project: $project_name\n";
}
    
sub t_create_project {
	package ::;
	my $name = shift;
	load_project( 
		name => ::remove_spaces($name),
		create => 1,
	);
	print "created project: $project_name\n";

}
sub t_add_ctrl {
	package ::;
	my ($parent, $code, $values) = @_;
	print "code: $code, parent: $parent\n";
	$values and print "values: ", join " ", @{$values};
	if ( $effect_i{$code} ) {} # do nothing
	elsif ( $effect_j{$code} ) { $code = $effect_j{$code} }
	else { warn "effect code not found: $code\n"; return }
	print "code: ", $code, $/;
		my %p = (
				chain => $cops{$parent}->{chain},
				parent_id => $parent,
				values => $values,
				type => $code,
			);
			print "adding effect\n";
			# print (yaml_out(\%p));
		add_effect( \%p );
}
sub t_add_effect {
	package ::;
	my ($code, $values)  = @_;

	# allow use of LADSPA unique ID
	
    if ($code !~ /\D/){ # i.e. $code is all digits
		$code = $ladspa_label{$code} 
			or carp("$code: LADSPA plugin not found.  Aborting.\n"), return;
	}
		
	if ( $effect_i{$code} ) {} # do nothing
	elsif ( $effect_j{$code} ) { $code = $effect_j{$code} }
	else { warn "effect code not found: $code\n"; return }
	print "code: ", $code, $/;
		my %p = (
			chain => $this_track->n,
			values => $values,
			type => $code,
			);
			print "adding effect\n";
			#print (yaml_out(\%p));
		add_effect( \%p );
}
package ::Text;
sub group_rec { 
	print "Setting group REC-enable. You may record user tracks.\n";
	$tracker->set( rw => 'REC'); }
sub group_mon { 
	print "Setting group MON mode. No recording on user tracks.\n";
	$tracker->set( rw => 'MON');}
sub group_off {
	print "Setting group OFF mode. All user tracks disabled.\n";
	$tracker->set(rw => 'OFF'); } 

sub mixdown {
	print "Enabling mixdown to file.\n";
	$mixdown_track->set(rw => 'REC'); }
sub mixplay { 
	print "Setting mixdown playback mode.\n";
	$mixdown_track->set(rw => 'MON');
	$tracker->set(rw => 'OFF');}
sub mixoff { 
	print "Leaving mixdown mode.\n";
	$mixdown_track->set(rw => 'OFF');
	$tracker->set(rw => 'MON')}

sub bunch {
	package ::;
	my ($bunchname, @tracks) = @_;
	if (! $bunchname){
		pager(yaml_out \%bunch);
	} elsif (! @tracks){
		$bunch{$bunchname} 
			and print "bunch $bunchname: @{$bunch{$bunchname}}\n" 
			or  print "bunch $bunchname: does not exist.\n";
	} elsif (my @mispelled = grep { ! $tn{$_} and ! $ti[$_]} @tracks){
		print "@mispelled: mispelled track(s), skipping.\n";
	} else {
	$bunch{$bunchname} = [ @tracks ];
	}
}
sub load_keywords {

@keywords = keys %commands;
push @keywords, grep{$_} map{split " ", $commands{$_}->{short}} @keywords;
push @keywords, keys %iam_cmd;
push @keywords, keys %effect_j;
}

sub complete {
    my ($text, $line, $start, $end) = @_;
    return $term->completion_matches($text,\&keyword);
};

{
    my $i;
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
    }
};

