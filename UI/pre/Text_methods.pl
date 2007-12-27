sub new { my $class = shift; return bless { @_ }, $class; }
sub loop {
	package ::;
	load_session({name => $session_name, create => $opts{c}}) if $session_name;
	use Term::ReadLine;
	my $term = new Term::ReadLine 'Ecmd';
	my $prompt = "Enter command: ";
	$::OUT = $term->OUT || \*STDOUT;
	my $user_input;
	use vars qw($parser %iam_cmd);
 	$parser = new Parse::RecDescent ($grammar) or croak "Bad grammar!\n";
	$debug = 1;
	while (1) {
		
		($user_input) = $term->readline($prompt) ;
		$user_input =~ /^\s*$/ and next;
		$term->addhistory($user_input) ;
		my ($cmd, $predicate) = ($user_input =~ /(\w+)(.*)/);
		$debug and print "cmd: $cmd \npredicate: $predicate\n";
		if ($cmd eq 'eval') {
			eval $predicate;
			print "\n";
			$@ and print "Perl command failed: $@\n";
		} elsif ($track_names{$cmd}) { 
			$debug and print "Track name: $cmd\n";
			$select_track = $cmd; 
			$parser->command($predicate) or print ("Returned false\n");
		} elsif ($iam_cmd{$cmd}){
			$debug and print "Found IAM command\n";
			eval_iam($user_input) ;
		} elsif ( grep { $cmd eq $_ } @ecmd_commands ) {
			$debug and print "Found Ecmd command\n";
			$parser->command($user_input) or print ("Parse failed\n");
		} else {
			$parser->command($user_input) or print ("Returned false\n");
		}

	}
}

format STDOUT_TOP =
Chain Ver File            Setting Status Rec_ch Mon_ch 
=====================================================
.
format STDOUT =
@<<  @<<  @<<<<<<<<<<<<<<<  @<<<   @<<<   @<<    @<< ~~
splice @::format_fields, 0, 7

.
	
1;
