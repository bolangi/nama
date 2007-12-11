#!/usr/bin/env perl
use Template;
use IO::All;

my $template = Template->new;
my $command_headers;

# define template variables for replacement

# specify input filename, or file handle, text reference, etc.
my $input = 'Grammar.p';

my $list = io('commands')->all;
my $body = io('grammar_body')->all;
$body =~ s/::/Audio::Ecasound::Flow::/g;


my (@abbrevs, @stubs, @commands);

map{

	my @parts = my @all_parts = split " ", $_;
	my $full = shift @parts;
	my @short = @parts;
	push @abbrevs,	"_$full: " . join (" | " , @all_parts);
	push @stubs,   	"$full: _$full {}";
	push @commands,	"command: $full";

} split "\n", $list;

my $command_headers = join "\n", @commands, @abbrevs, @stubs ;

my $vars = { 
	commands 	 => $command_headers,
	grammar_body => $body,
};
# process input template, substituting variables
$template->process($input, $vars)
	 || die $template->error();
	
__END__

