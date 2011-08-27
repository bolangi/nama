# -------- Text Interface -----------
## The following methods belong to the Text interface class

package ::;

our (
[% qx(cat ./singletons.pl) %]
	$mode->{preview},
	$mode->{mastering},
	%tn,
	%ti,
	%bn,
	$text->{term_attribs},
	$text->{term},
	$this_track,
	$this_bus,
	%{$fx_cache->{full_label_to_index}},
	%{$fx_cache->{partial_label_to_full}},
	@{$fx_cache->{registry}},
	%{$fx->{applied}},
	%{$fx->{params}},
	$gn{Main},
	$setup->{audio_length},
	$setup->{runtime_limit},
	$config->{use_placeholders},
	$text->{format_top},
	$text->{format_divider},
	@{$text->{format_fields}},
	$debug,
	%{$gui->{_project_name}->{bunch}},
	%{$text->{commands}},
	%{$fx_cache->{ladspa_id_to_label}},
	@{$fx_cache->{user_help}},
	@{$help->{arr_topic}},
	%{$help->{topic}},
	%{$fx_cache->{ladspa_help}},
	$text->{wrap},
	$gui->{_project_name}->{name},
	%{$text->{iam}},
	$ui,
		
);

package ::Text;
use Modern::Perl; 
no warnings 'uninitialized';
use Carp;
use ::Assign qw(:all);

our @ISA = '::';
our $VERSION = 1.071;

sub hello {"hello world!";}

sub loop {
	package ::;
	issue_first_prompt();
	$Event::DIED = sub {
	   my ($event, $errmsg) = @_;
	   say $errmsg;
	   $text->{term_attribs}->{line_buffer} = q();
	   $text->{term}->clear_message();
	   $text->{term}->rl_reset_line_state();
	};
	Event::loop();
}

[% qx(cat ./Text_methods.pl ) %]

## NO-OP GRAPHIC METHODS 

no warnings qw(redefine);
sub init_gui {}
sub transport_gui {}
sub group_gui {}
sub track_gui {}
sub preview_button {}
sub create_master_and_mix_tracks {}
sub time_gui {}
sub refresh {}
sub refresh_group {}
sub refresh_track {}
sub flash_ready {}
sub update_master_version_button {}
sub update_version_button {}
sub paint_button {}
sub project_label_configure{}
sub length_display{}
sub clock_display {}
sub clock_config {}
sub manifest {}
sub global_version_buttons {}
sub destroy_widgets {}
sub destroy_marker {}
sub restore_time_marks {}
sub show_unit {}
sub add_effect_gui {}
sub remove_effect_gui {}
sub marker {}
sub init_palette {}
sub save_palette {}
sub paint_mute_buttons {}
sub remove_track_gui {}
sub reset_engine_mode_color_display {}
sub set_engine_mode_color_display {}

1;
__END__
