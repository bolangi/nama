package ::Globals;
use Modern::Perl;

# set aliases for common indices
*bn = \%::Bus::by_name;
*tn = \%::Track::by_name;
*ti = \%::Track::by_index;
*mn = \%::Mark::by_name;
*en = \%::Engine::by_name;
*fi = \%::Effect::by_id;

# and the graph

*g = \$::ChainSetup::g;

use Exporter;
use constant {
	REC	=> 'REC',
	PLAY => 'PLAY',
	MON => 'MON',
	OFF => 'OFF',
};
our @ISA = 'Exporter';
our @EXPORT_OK = qw(

[% join "\n", split " ",qx(./strip_all ./pronouns.pl ./singletons.pl ./serialize.pl) %]

);

our %EXPORT_TAGS = 
(
	trackrw => [qw(REC PLAY MON OFF)],
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
__END__

=head1 Nama Variables

Variables are listed in multiple files in the source.

=head2 Exported

L<Audio::Nama::Globals> exports Nama globals, 
which it gets by merging the contents
of the following files:

=over

=item F<pronouns.pl>

Pronouns (e.g. C<$this_track>) and 
indices (e.g. C<%tn>, get track by name)

=item F<serialize.pl>

Marshalling variables for serializing/deserializing (e.g. C<@tracks_data>)

=item F<singletons.pl> 

Simple hash structures (such as C<$config>) or objects such
as F<$file> that aggregate data.  The hashes can be invested
with object properties as need be.

=back

=head2 Other lists

=over

=item F<config_map>

Maps keys in F<.namarc> (e.g. I<mix_to_disk_format>) to the
corresponding Nama internal scalar (e.g. C<$config-E<gt>{mix_to_disk_format}>

=item F<singleton_keys>

List of allowed singleton hash keys. 

Keys of variables appearing in ./singletons.pl 
should be listed in singleton_keys or in config_map.
Undeclared keys will trigger warnings during build.

=head2 F<var_lists.pl>

Declares lists of variables used in
serializing/deserializing.

=item C<@global_effect_chain_vars>

Mainly user defined and system-wide effect chains,
stored in F<global_effect_chains.json> in the 
Nama project root directory.

=item C<@tracked_vars>

These variables are saved to F<State.json> in the project
directory and placed under version control.

=item C<@persistent_vars>

These Variables saved to F<Aux.json>, I<not> under version control.
including project-specific effect-chain definitions,
and track/version comments.

=back

=cut
