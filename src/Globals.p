package ::Globals;
use Modern::Perl;
*bn = \%::Bus::by_name;
*tn = \%::Track::by_name;
*ti = \%::Track::by_index;
use Exporter;
our @ISA = 'Exporter';
our @EXPORT_OK = qw(

[% qx(cat ./singletons.pl) %]
[% qx(cat ./globals.pl   ) %]
[% qx(cat ./serialize.pl ) %]

);

our %EXPORT_TAGS = 
(
	singletons => [qw( 	

[% qx(cat ./singletons.pl) %]

	)],

debug => [qw( 		$debug
					$debug2
)],

	pronouns => [qw(
						$this_track
						$this_bus
						$this_op
						$this_param
						$this_mark
						$this_edit
						%tn
						%ti
						%bn
						$prompt
	)],

	var_types => [qw(

						@config_vars
						@persistent_vars
						@new_persistent_vars
						@global_effect_chain_vars
						@project_config_vars
	)],

	serialize =>  [qw(

[% qx(cat ./serialize.pl ) %]

	)],
);
our $ui = 'bullwinkle';  # for testing
{
	my %seen;
	push @{$EXPORT_TAGS{all}}, grep {!$seen{$_}++} @{$EXPORT_TAGS{$_}} foreach
keys %EXPORT_TAGS;
}


1;
