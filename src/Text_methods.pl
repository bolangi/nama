use Carp;
use Text::Format;
use ::Assign qw(:all);
$text = new Text::Format {
	columns 		=> 65,
	firstIndent 	=> 0,
	bodyIndent		=> 0,
	tabstop			=> 4,
};

sub new { my $class = shift; return bless { @_ }, $class; }

sub show_versions {
 	print "All versions: ", join " ", @{$this_track->versions}, $/;
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

sub poll_jack {
	package ::;
	$event_id{Event_poll_jack} = Event->timer(
	    desc   => 'poll_jack',               # description;
	    prio   => 5,                         # low priority;
		interval => 5,
	    cb     => sub{ $jack_running = jack_running() },  # callback;
	);
}

sub loop {

	# first setup Term::Readline::GNU

	# we are using Event's handlers and event loop
	package ::;
	::Text::poll_jack();
	$term = new Term::ReadLine("Ecasound/Nama");
	my $attribs = $term->Attribs;
	$attribs->{attempted_completion_function} = \&complete;
	$term->callback_handler_install($prompt, \&process_line);

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
	    cb     => \&heartbeat,               # callback;
	);
	if ( $midi_inputs =~ /on|capture/ ){
		my $command = "aseqdump ";
		$command .= "-p $controller_ports" if $controller_ports;
		open MIDI, "$command |" or die "can't fork $command: $!";
		$event_id{sequencer} = Event->io(
			desc   => 'read ALSA sequencer events',
			fd     => \*MIDI,                    # handle;
			poll   => 'r',	                     # watch for incoming chars
			cb     => \&process_control_inputs, # callback;
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
	package ::;
	@_ = discard_object(@_);
	my ($diff, $start) = @_;
	#print "diff: $diff, start: $start\n";
	$event_id{Event_wraparound}->cancel()
		if defined $event_id{Event_wraparound};
	$event_id{Event_wraparound} = Event->timer(
	desc   => 'wraparound',               # description;
	after  => $diff,
	cb     => sub{ set_position($start) }, # callback;
   );

}


sub start_heartbeat {$event_id{Event_heartbeat}->start() }

sub stop_heartbeat {$event_id{Event_heartbeat}->stop() }

sub cancel_wraparound {
	$event_id{Event_wraparound}->cancel() if defined $event_id{Event_wraparound}
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
	my $newname = remove_spaces($name);
	$newname =~ s(/$)(); # remove trailing slash
	print ("Project $newname does not exist\n"), return
		unless -d join_path project_root(), $newname; 
	load_project( name => $newname );
	print "loaded project: $project_name\n";
}

    
sub t_create_project {
	package ::;
	my $name = shift;
	load_project( 
		name => remove_spaces($name),
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
sub t_insert_effect {
	my ($before, $code, $values) = @_;
	print ("Cannot insert effect while engine is recording.\n"), return 
		if ::engine_running and ::really_recording;

	# what about inserting before controller... user should
	# not do it
	
	my $n = $cops{ $before }->{chain} or 
		print(qq[Insertion point "$before" does not exist.  Skipping.\n]), 
		return;
	
	# should mute if engine running
	my $track = $ti[$n];
	$debug and print $track->name, $/;
	#$debug and print join " ",@{$track->ops}, $/; 

	# find offset 
	
	my $offset = 0;
	for my $id ( @{$track->ops} ){
		last if $id eq $before;
		$offset++;
	}

	# remove later ops if engine is connected
	# this will not change the $track->cops list 

	my @ops = @{$track->ops}[$offset..$#{$track->ops}];
	$debug and print "ops to remove and re-apply: @ops\n";
	if (::eval_iam q(cs-connected) ){  }
		map{ ::remove_op $_ } @ops
	}

	t_add_effect( $code, $values );

	$debug and print join " ",@{$track->ops}, $/; 

	my $op = pop @{$track->ops}; 
	# acts directly on $track, because ->ops returns 
	# a reference to the array

	# insert the effect id 
	splice 	@{$track->ops}, $offset, 0, $op;
	$debug and print join " ",@{$track->ops}, $/; 

	if (::eval_iam q(cs-connected) ){  }
		map{ ::apply_op $_ } @ops
	}
		
		
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
	print "Setting mixdown_track playback mode.\n";
	$mixdown_track->set(rw => 'MON');
	$tracker->set(rw => 'OFF');}
sub mixoff { 
	print "Leaving mixdown_track mode.\n";
	$mixdown_track->set(rw => 'OFF');
	$tracker->set(rw => 'MON')}

sub bunch {
	package ::;
	my ($bunchname, @tracks) = @_;
	if (! $bunchname){
		::pager(yaml_out( \%bunch ));
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
