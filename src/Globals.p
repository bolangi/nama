package ::Globals;
use Modern::Perl;

# set aliases for common indices
*bn = \%::Bus::by_name;
*tn = \%::Track::by_name;
*ti = \%::Track::by_index;
*mn = \%::Mark::by_name;

# and the graph

*g = \$::ChainSetup::g;

use Exporter;
our @ISA = 'Exporter';
our @EXPORT_OK = qw(

[% join "\n", split " ",qx(./strip_all ./pronouns.pl ./singletons.pl ./serialize.pl) %]

);

our %EXPORT_TAGS = 
(
	singletons => [qw( 	

[% qx(./strip_all ./singletons.pl) %]

	)],

	var_lists => [qw(

						@tracked_vars
						@persistent_vars
						@global_effect_chain_vars
	)],

	pronouns => [qw( 

[% qx(./strip_all ./pronouns.pl) %]

	)],

	serialize =>  [qw(

[% qx(./strip_all ./serialize.pl ) %]

	)],
);
our $ui = 'bullwinkle';  # for testing
{
	my %seen;
	push @{$EXPORT_TAGS{all}}, grep {!$seen{$_}++} @{$EXPORT_TAGS{$_}} foreach
keys %EXPORT_TAGS;
}


1;
