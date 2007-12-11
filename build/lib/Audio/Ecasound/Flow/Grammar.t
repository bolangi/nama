#!/usr/bin/env perl
use Template;

my $template = Template->new($config);
# define template variables for replacement
my $vars = {
person => $value,
};
=comment
	 var1  => $value,
	 var2  => \%hash,
	 var3  => \@list,
	 var4  => \&code,
	 var5  => $object,
=cut

# specify input filename, or file handle, text reference, etc.
my $input = 'Grammar.p';

# process input template, substituting variables
$template->process($input, $vars)
	 || die $template->error();
