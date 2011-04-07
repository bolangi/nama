# -------- Text Interface -----------
## The following methods belong to the Text interface class

package ::;

our (
	$preview,
	$mastering_mode,
	%tn,
	%ti,
	%bn,
	$attribs,
	$term,
	$this_track,
	$this_bus,
	%effect_i,
	%effect_j,
	@effects,
	%cops,
	%copp,
	$main,
	$main_out,
	$length,
	$run_time,
	$use_placeholders,
	$format_top,
	$format_divider,
	@format_fields,
	$debug,
	%bunch,
	%commands,
	%ladspa_label,
	@effects_help,
	@help_topic,
	%help_topic,
	%ladspa_help,
	$text_wrap,
	$project_name,
	%iam_cmd,
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
	   $attribs->{line_buffer} = q();
	   $term->clear_message();
	   $term->rl_reset_line_state();
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
sub refresh_oids {}
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
