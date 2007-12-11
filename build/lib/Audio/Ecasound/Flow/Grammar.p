# Grammar.p, source for Grammar.pm

package Audio::Ecasound::Flow;

### COMMAND LINE PARSER 

$debug2 and print "Reading grammar\n";

$AUTOSTUB = 1;
$RD_HINT = 1;

# rec command changes active take

$grammar = q(

[% INSERT command_headers %]
[% INSERT grammar_body %]

);

# extract top-level commands from grammar

@ecmd_commands = 
	grep{$_} map{&remove_spaces($_)}        # remove null items
	map{split /\s*\|\s*|command:\s*/, $_}  # split apart commands
	grep {/command:/} split "\n", $grammar; # only commands

@ecmd_commands{@ecmd_commands} = 1..@ecmd_commands;
#print join $/, keys %ecmd_commands; 
#

sub remove_spaces {
	my $entry = shift;
	# remove leading and trailing spaces
	
	$entry =~ s/^\s*//;
	$entry =~ s/\s*$//;

	# convert other spaces to underscores
	
	$entry =~ s/\s+/_/g;
	$entry;
}
1;

