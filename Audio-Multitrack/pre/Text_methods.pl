use Carp;
#&loop;
sub new { my $class = shift; return bless { @_ }, $class; }
sub loop {
	local $debug = 1;
	package ::;
	load_project({name => $project_name, create => $opts{c}}) if $project_name;
	my $term = new Term::ReadLine 'Ecmd';
	my $prompt = "Enter command: ";
	$OUT = $term->OUT || \*STDOUT;
	#$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";

	# prepare help and autocomplete
	#
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
				print eval_iam($user_input), $/ ;
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
	

package ::Text::OuterShell;
use base qw(Term::Shell); 
create_help_subs();
sub catch_run { # 
  my ($o, $cmd, @args) = @_;
  my $original_command_line = join " ", $cmd, @args;
  print "foudn $original_command_line\n";
  ::Text::command_process( $original_command_line );
}
sub create_help_subs {
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

