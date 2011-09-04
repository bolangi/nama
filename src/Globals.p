package ::Globals;
use Modern::Perl;
1;
__END__
use Exporter;
our @ISA = 'Exporter';
our @EXPORT_OK = qw(

[% qx(cat ./singletons.pl) %]
[% qx(cat ./globals.pl   ) %]

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
						%tn
						%ti
						%bn
						%gn
	)],

	var_types => [qw(

						@config_vars
						@persistent_vars
	)],
);
$ui = 'bullwinkle';  # for testing
1;
__END__
{
	my %seen;
	push @{$EXPORT_TAGS{all}}, grep {!$seen{$_}++} @{$EXPORT_TAGS{$_}} foreach
keys %EXPORT_TAGS;
}


1;
