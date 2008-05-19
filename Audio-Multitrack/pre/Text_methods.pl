use Carp;
sub new { my $class = shift; return bless { @_ }, $class; }
sub loop {
	local $debug = 0;
	::Text::OuterShell::create_help_subs();
	package ::;
	load_project({name => $project_name, create => $opts{c}}) if $project_name;
#	my $term = new Term::ReadLine 'Ecmd';
#	my $prompt = "Enter command: ";
#	$OUT = $term->OUT || \*STDOUT;
	$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";


 #	use ::Text::OuterShell; # not needed, class is present in this file
	  my $shell = ::Text::OuterShell->new;

          $shell->cmdloop;
}

	
sub command_process {

package ::;
		my ($user_input) = shift;
		# my ($user_input) = $term->readline($prompt) ; # old way
		return if $user_input =~ /^\s*$/;
		# $term->addhistory($user_input) ; # this is done # for us too
		my @user_input = split /\s*;\s*/, $user_input;
		map {
			my $user_input = $_;
			my ($cmd, $predicate) = ($user_input =~ /(\S+)(.*)/);
			$debug and print "cmd: $cmd \npredicate: $predicate\n";
			if ($cmd eq 'eval') {
				$debug and print "Evaluating perl code\n";
				eval $predicate;
				print "\n";
				$@ and print "Perl command failed: $@\n";
			} elsif ($tn{$cmd}) { 
				$debug and print qq(Selecting track "$cmd"\n);
				$select_track = $tn{$cmd};
				$predicate !~ /^\s*$/ and $parser->read($predicate);
			} elsif ($cmd =~ /^\d+$/ and $ti[$cmd]) { 
				$debug and print qq(Selecting track ), $ti[$cmd]->name, $/;
				$select_track = $ti[$cmd];
				$predicate !~ /^\s*$/ and $parser->read($predicate);
			} elsif ($iam_cmd{$cmd}){
				$debug and print "Found Iam command\n";
				print ::eval_iam($user_input), $/ ;
			} else {
				$debug and print "Passing to parser\n";
				$parser->command($user_input) 
			}

		} @user_input;
}
package ::Text;
sub show_tracks {
	no warnings;
	my @tracks = @_;
	map { 	push @::format_fields,  
			$_->n,
			$_->name,
			$_->rw,
			$_->rec_status,
			$_->ch_r || 1,
			$_->current_version || 'none',
			(join " ", @{$_->versions}),

		} @tracks;
		
	write; # using format at end of file UI.pm
	$- = 0; # $FORMAT_LINES_LEFT # force header on next output
	1;
	use warnings;
	no warnings q(uninitialized);
}

format STDOUT_TOP =
Chain  Track name     Setting  Status  Input  Active  Versions   
==========================================================================
.
format STDOUT =
@>>    @<<<<<<<<<<<<   @<<<     @<<<   @>>     @>>>   @<<<<<<<<<<<<<<<<<<< ~~
splice @::format_fields, 0, 7
.
	
# prepare help and autocomplete

package ::Text::OuterShell;
use base qw(Term::Shell); 
#create_help_subs();
sub catch_run { # 
  my ($o, $cmd, @args) = @_;
  my $original_command_line = join " ", $cmd, @args;
  print "foudn $0 $original_command_line\n";
  ::Text::command_process( $original_command_line );
}
sub catch_help {
  my ($o, $cmd, @args) = @_;
  local $debug = 0;
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
	my (%cmds, %docs);
	my %done;
	my %handlers;
	for my $h (keys %{$o->{handlers}}) {
	    next unless length($h);
	    next unless grep{defined$o->{handlers}{$h}{$_}} qw(run smry help);
	    my $dest = exists $o->{handlers}{$h}{run} ? \%cmds : \%docs;
	    my $smry = do { my $x = $o->summary($h); $x ? $x : "" };
	    my $help = exists $o->{handlers}{$h}{help}
		? (exists $o->{handlers}{$h}{smry}
		    ? " "
		    : "")
		: "";
	    $dest->{"    $h"} = "$smry$help";
	}
	my @t;
	push @t, "  Commands:\n" if %cmds;
	push @t, scalar $o->format_pairs(
	    [sort keys %cmds], [map {$cmds{$_}} sort keys %cmds], ' - ', 1
	);
	push @t, "  Extra Help Topics: (not commands)\n" if %docs;
	push @t, scalar $o->format_pairs(
	    [sort keys %docs], [map {$docs{$_}} sort keys %docs], ' - ', 1
	);
	$o->page(join '', @t);
    }
}


=comment
sub run_help {
    my $o = shift;
    my $cmd = shift;
    if ($cmd) {
	my $txt = $o->help($cmd, @_);
	if ($o->{command}{help}{found}) {
	    $o->page($txt.$/)
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
	my (%cmds, %docs);
	my %done;
	my %handlers;
	for my $h (keys %{$o->{handlers}}) {
	    next unless length($h);
	    next unless grep{defined$o->{handlers}{$h}{$_}} qw(smry help);
	    my $dest = exists $o->{handlers}{$h}{run} ? \%cmds : \%docs;
	    my $smry = do { my $x = $o->summary($h); $x ? $x : "" };
	    my $help = exists $o->{handlers}{$h}{help}
		? (exists $o->{handlers}{$h}{smry}
		    ? "   "
		    : " * ")
		: "   ";
	    $dest->{"    $h"} = "$smry$help";
	}
	my @t;
	push @t, "  Commands:\n" if %cmds;
	push @t, scalar $o->format_pairs(
	    [sort keys %cmds], [map {$cmds{$_}} sort keys %cmds], ' - ', 1
	);
	push @t, "  Extra Help Topics: (not commands)\n" if %docs;
	push @t, scalar $o->format_pairs(
	    [sort keys %docs], [map {$docs{$_}} sort keys %docs], ' - ', 1
	);
	$o->page(join '', @t);
    }
}
=cut
sub create_help_subs {
	$debug2 and print "create_help_subs\n";
	local $debug = 0;
	%commands = %{ ::yaml_in( $::commands_yml) };

	$debug and print ::yaml_out \%commands;
	
	#map{ print $_, $/} grep{ $_ !~ /mark/ and $_ !~ /effect/ } keys %commands;
	
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
			#eval $alias_code;# noisy in docs
			$debug and $@ and print "create_sub eval error: $@\n";

		}

	grep{ $_ !~ /mark/ and $_ !~ /effect/ } keys %commands;

}
	

=comment
sub run_command1  { print "command 1!\n"; }
sub comp_com { shift; print "hello auto complete", @_ }
sub smry_command1 { "what does command1 do?" }
sub help_command1 {
<<'END';
Help on 'command1', whatever that may be...
END
=cut

