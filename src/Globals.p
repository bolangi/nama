package ::Globals;
use Modern::Perl;
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
						%gn
						$prompt
	)],

	var_types => [qw(

						@config_vars
						@persistent_vars
	)],

	serialize =>  [qw(
						@tracks_data
						@bus_data
						@groups_data
						@marks_data
						@fade_data
						@edit_data
						@inserts_data
						$this_track_name
	)],
);
our $ui = 'bullwinkle';  # for testing
{
	my %seen;
	push @{$EXPORT_TAGS{all}}, grep {!$seen{$_}++} @{$EXPORT_TAGS{$_}} foreach
keys %EXPORT_TAGS;
}


1;
