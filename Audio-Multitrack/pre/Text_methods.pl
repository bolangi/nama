use Carp;
sub new { my $class = shift; return bless { @_ }, $class; }

sub show_versions {
 	print "All versions: ", join " ", @{$::this_track->versions}, $/;
}

sub show_effects {
 	map { 
 		my $op_id = $_;
 		 my $i = $::effect_i{ $::cops{ $op_id }->{type} };
 		 print $op_id, ": " , $::effects[ $i ]->{name},  " ";
 		 my @pnames =@{$::effects[ $i ]->{params}};
			map{ print join " ", 
			 	$pnames[$_]->{name}, 
				$::copp{$op_id}->[$_],'' 
		 	} (0..scalar @pnames - 1);
		 print $/;
 
 	 } @{ $::this_track->ops };
}
sub show_modifiers {
	print "Modifiers: ",$::this_track->modifiers, $/;
}
sub loop {
    package ::;
    #load_project(name => $project_name, create => $opts{c}) if $project_name;
    my $term = new Term::ReadLine 'Nama';
	
# 	No TK events in text-only mode

	# $mw->iconify;         
	# $term->tkRunning(1);
	
    my $prompt = "Enter command: ";
    $OUT = $term->OUT || \*STDOUT;
	while (1) {
    my ($user_input) = $term->readline($prompt) ;
	next if $user_input =~ /^\s*$/;
	#print "previous: '$previous_text_command' current: '$user_input'\n";
    $term->addhistory($user_input) 
	 	unless $user_input eq $previous_text_command;
 	$previous_text_command = $user_input;
	::Text::command_process( $user_input );
	#print "here we are\n";
 #    use ::Text::OuterShell; # not needed, class is present in this file
#      my $shell = ::Text::OuterShell->new;

          # $shell->cmdloop;
	}
}

    
sub command_process {

package ::;
        my ($user_input) = shift;
        return if $user_input =~ /^\s*$/;
        $debug and print "user input: $user_input\n";
		my ($cmd, $predicate) = ($user_input =~ /([\S]+)(.*)/);
		if ($cmd eq 'eval') {
                $debug and print "Evaluating perl code\n";
                print eval $predicate;
                print "\n";
                $@ and print "Perl command failed: $@\n";
		}
		elsif ( $cmd eq '!' ) {
                $debug and print "Evaluating shell commands!\n";
                system $predicate;
                print "\n";
		} else {


        my @user_input = split /\s*;\s*/, $user_input;
        map {
            my $user_input = $_;
            my ($cmd, $predicate) = ($user_input =~ /([\S]+)(.*)/);
            $debug and print "cmd: $cmd \npredicate: $predicate\n";
            if ($cmd eq 'eval') {
                $debug and print "Evaluating perl code\n";
                print eval $predicate;
                print "\n";
                $@ and print "Perl command failed: $@\n";
            } elsif ($cmd eq '!') {
                $debug and print "Evaluating shell commands!\n";
                system $predicate;
                print "\n";
            } elsif ($tn{$cmd}) { 
                $debug and print qq(Selecting track "$cmd"\n);
                $this_track = $tn{$cmd};
                $predicate !~ /^\s*$/ and $::parser->command($predicate);
            } elsif ($cmd =~ /^\d+$/ and $ti[$cmd]) { 
                $debug and print qq(Selecting track ), $ti[$cmd]->name, $/;
                $this_track = $ti[$cmd];
                $predicate !~ /^\s*$/ and $::parser->command($predicate);
            } elsif ($iam_cmd{$cmd}){
                $debug and print "Found Iam command\n";
                print ::eval_iam($user_input), $/ ;
            } else {
                $debug and print "Passing to parser\n", 
                $_, $/;
                #print 1, ref $parser, $/;
                #print 2, ref $::parser, $/;
                # both print
                $parser->command($_) 
            }    
        } @user_input;
		}
        $ui->refresh; # in case we have a graphic environment
}
package ::Text;
sub show_tracks {
    no warnings;
    my @tracks = @_;
    map {     push @::format_fields,  
            $_->n,
            $_->name,
            $_->rw,
            $_->rec_status,
            $_->rec_status eq 'REC' ? $_->ch_r : '',
            $_->current_version || '',
            #(join " ", @{$_->versions}),

        } grep{ ! $_-> hide} @tracks;
        
    write; # using format at end of file UI.pm
    $- = 0; # $FORMAT_LINES_LEFT # force header on next output
    1;
    use warnings;
    no warnings q(uninitialized);
}

format STDOUT_TOP =
Track  Name        Setting  Status  Input  Version 
==================================================
.
format STDOUT =
@>>    @<<<<<<<<<    @<<<    @<<<    @>>     @>>>   ~~
splice @::format_fields, 0, 6
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
	print( $/, ucfirst $text, $/);
	
}
sub helptopic {
	my $index = shift;
	$index =~ /^\d+$/ and $index = $help_topic[$index];
	print "\n-- ", ucfirst $index, " --\n\n";
	print $help_topic{$index};
	print $/;
}

sub help { 
	my $name = shift;
	chomp $name;
	#print "seeking help for argument: $name\n";
	$help_topic{$name} and helptopic($name), return;
	$name == 10 and (map{ helptopic $_ } @help_topic), return;
	$name =~ /^\d+$/ and helptopic($name), return;

	$commands{$name} and helpline($name), return;
	my %helped = (); 
	map{  my $cmd = $_ ;
		helpline($cmd) and $helped{$cmd}++ if $cmd =~ /$name/;
		  # print ("commands short: ", $commands{$cmd}->{short}, $/),
	      helpline($cmd) 
		  	if grep { /$name/ } split " ", $commands{$cmd}->{short} 
				and ! $helped{$cmd};
	} keys %commands;
	# e.g. help tap_reverb
	if ( $effects_ladspa{"el:$name"}) {
	print "$name is the code for the following LADSPA effect:\n";
	#print yaml_out( $effects_ladspa{"el:$name"});
    print qx(analyseplugin $name);
	}
	
}


=comment
# prepare help and autocomplete

package ::Text::OuterShell;
use base qw(Term::Shell); 
#create_help_subs();
sub catch_run { # 
  my ($o, $cmd, @args) = @_;
  my $original_command_line = join " ", $cmd, @args;
  #print "foudn $0 $original_command_line\n";
  ::Text::command_process( $original_command_line );
}
sub catch_help {
  my ($o, $cmd, @args) = @_;
  $debug and print "cmd: $cmd\n";
  #my $main_name = 
  #
  print grep{ $_ eq $cmd } join " ", 
  my $main_name;
  CMD: for my $k ( keys %commands ){
      for my $alias ( $k, split " ",$commands{$k}{short} ){
        if ($cmd eq $alias){
            $main_name = $k;
            last CMD;
        }
    }
  }
  $debug and print "main_name: $main_name\n";
            
    my $txt = $o->help($main_name, @_);
    if ($o->{command}{help}{found}) {
        $o->page("$txt\n")
    }
}


#my $print "catched help @_"}
sub prompt_str { 'Enter command: ' }
sub run_help {
    my $o = shift;
    my $cmd = shift;
    if ($cmd) {
    my $txt = $o->help($cmd, @_);
    if ($o->{command}{help}{found}) {
        $o->page("$txt\n")
    }
    else {
        my @c = sort $o->possible_actions($cmd, 'help');
        if (@c and $o->{API}{match_uniq}) {
        local $" = "\n\t";
        print <<END;
Ambiguous help topic '$cmd': possible help topics:
    @c
END
        }
        else {
        print <<END;
Unknown help topic '$cmd'; type 'help' for a list of help topics.
END
        }
    }
    }
    else {
    print "Type 'help command' for more detailed help on a command.\n";
my $help_screen = <<HELP;
Help Screen Goes here
HELP
    $o->page($help_screen);
    }
}


sub create_help_subs {
    $debug2 and print "create_help_subs\n";
    %commands = %{ ::yaml_in( $::commands_yml) };

    $debug and print ::yaml_out \%commands;
    
    map{ print $_, $/} grep{ $_ !~ /mark/ and $_ !~ /effect/ } keys %commands;
    
    map{ 
            my $run_code = qq!sub run_$_ { splice \@_,1,0,  q($_); catch_run( \@_) }; !;
            $debug and print "evalcode: $run_code\n";
            eval $run_code;
            $debug and $@ and print "create_sub eval error: $@\n";
            my $help_code = qq!sub help_$_ { q($commands{$_}{what}) };!;
            $debug and print "evalcode: $help_code\n";
            eval $help_code;
            $debug and $@ and print "create_sub eval error: $@\n";
            my $smry_text = 
            $commands{$_}{smry} ? $commands{$_}{smry} : $commands{$_}{what};
            $smry_text .= qq! ($commands{$_}{short}) ! 
                    if $commands{$_}{short};

            my $smry_code = qq!sub smry_$_ { q( $smry_text ) }; !; 
            $debug and print "evalcode: $smry_code\n";
            eval $smry_code;
            $debug and $@ and print "create_sub eval error: $@\n";

            my $alias_code = qq!sub alias_$_ { qw($commands{$_}{short}) }; !;
            $debug and print "evalcode: $alias_code\n";
            eval $alias_code;# noisy in docs
            $debug and $@ and print "create_sub eval error: $@\n";

        }

    grep{ $_ !~ /mark/ and $_ !~ /effect/ } keys %commands;

}
=cut
    
