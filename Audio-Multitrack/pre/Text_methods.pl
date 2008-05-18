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
	$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";
	while (1) {
		my ($user_input) = $term->readline($prompt) ;
		$user_input =~ /^\s*$/ and next;
		$term->addhistory($user_input) ;
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
	
1;
