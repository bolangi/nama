use Carp;
#&loop;
sub new { my $class = shift; return bless { @_ }, $class; }
sub loop {
package ::;
load_project({name => $project_name, create => $opts{c}}) if $project_name;
use Parse::RecDescent;
use Term::ReadLine;
my $term = new Term::ReadLine 'Ecmd';
my $prompt = "Enter command: ";
$OUT = $term->OUT || \*STDOUT;
my $user_input;
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
				eval $predicate;
				print "\n";
				$@ and print "Perl command failed: $@\n";
			} elsif ($tn{$cmd}) { 
				$debug and print "Track name: $cmd\n";
				$select_track = $tn{$cmd};
				print "selected: $cmd\n";
				$parser->read($predicate) or print ("Returned false\n");
			} elsif ($cmd =~ /^\d+$/ and $ti[$cmd]) { 
				$debug and print "Track name: ", $ti[$cmd]->name, "\n";
				$select_track = $ti[$cmd];
				print "selected: $cmd\n";
				$parser->read($predicate) or print ("Returned false\n");
			} elsif ($iam_cmd{$cmd}){
				$debug and print "Found IAM command\n";
				print eval_iam($user_input) ;
			} else {
				$parser->command($user_input) 
					and print("Succeeded\n") or print ("Returned false\n");
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
