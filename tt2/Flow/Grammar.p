##  Grammar.p, source for Grammar.pm

package Audio::Ecasound::Flow;

### COMMAND LINE PARSER 

$debug2 and print "Reading grammar\n";

$AUTOSTUB = 1;
$RD_HINT = 1;

# rec command changes active take

$grammar = q(

[% PERL %]

	use IO::All;

	my $body = io('grammar_body')->all;
	$body =~ s/::/Audio::Ecasound::Flow::/g;

	my $list = io('commands')->all;
	my (@abbrevs, @stubs, @commands);

	map{

		my @parts = my @all_parts = split " ", $_;
		my $full = shift @parts;
		my @short = @parts;
		push @abbrevs,	"_$full: " . join (" | " , @all_parts);
		push @stubs,   	"$full: _$full {}";
		push @commands,	"command: $full";

	} split "\n", $list;

	print join "\n", @commands, @abbrevs, @stubs, $body ;

[% END %]


);

1;
