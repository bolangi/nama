use Carp;
#&loop;
sub new { my $class = shift; return bless { @_ }, $class; }
sub loop {
	local $debug = 1;
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
sub catch_help { print "catched help @_"}
sub run_command1  { print "command 1!\n"; }
sub comp_com { shift; print "hello auto complete", @_ }
sub smry_command1 { "what does command1 do?" }
sub help_command1 {
<<'END';
Help on 'command1', whatever that may be...
END
}

sub run_command2 { print "command 2!\n"; }
sub create_help_subs {
	$debug2 and print "create_help_subs\n";
	local $debug = 1;
	my %commands = %{ ::yaml_in( $::commands_yml) };

	$debug and print ::yaml_out \%commands;
	
	#map{ print $_, $/} grep{ $_ !~ /mark/ and $_ !~ /effect/ } keys %commands;
	
	map{ 
			my $run_code = qq!sub run_$_ { splice \@_,1,0,  q($_); catch_run( \@_) }; !;
			$debug and print "evalcode: $run_code\n";
			eval $run_code;
			$debug and $@ and print "create_sub eval error: $@\n";
			my $help_code = qq!sub help_$_ { q($commands{$_}{what}) }; !;
			$debug and print "evalcode: $help_code\n";
			eval $help_code;
			$debug and $@ and print "create_sub eval error: $@\n";
			my $smry_code = qq!sub smry_$_ { q($commands{$_}{what}) }; !;
			$debug and print "evalcode: $smry_code\n";
			eval $smry_code;
			$debug and $@ and print "create_sub eval error: $@\n";

			my $alias_code = qq!sub alias_$_ { qw($commands{$_}{short}}; !;
			$debug and print "evalcode: $alias_code\n";
			eval $alias_code;
			$debug and $@ and print "create_sub eval error: $@\n";
			
			map { 
				my $run_code = qq!sub run_$_ { catch_run( \@_) }; !;
				$debug and print "evalcode: $run_code\n";
				eval $run_code;
				$debug and $@ and print "create_sub eval error: $@\n";
			} split " ", $commands{$_}{short} ;

		}

	grep{ $_ !~ /mark/ and $_ !~ /effect/ } keys %commands;

	map{  	
				s/-/_/g;
				my $run_code = qq!sub run_$_ { catch_run( \@_) }; !;
				$debug and print "evalcode: $run_code\n";
				eval $run_code;
				$debug and $@ and print "create_sub eval error: $@\n";
		} keys %iam_cmd;

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

