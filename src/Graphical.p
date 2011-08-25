# ------------ Graphical User Interface ------------

package ::;

our $VERSION = 1.071;

our ( 
[% qx(cat ./singletons.pl) %]
	$attribs,
	$term,
	$prompt,
	$debug,
	$debug2,
	$preview,
	$main,
	$ui,
	%ti,
	%tn,
	%bn,
	
	%effect_i,
	%effect_j,
	@effects,
	%cops,
	%copp,
	%copp_exp,
	%mute_level,
	%unity_level,
	%fade_out_level,
	
	$project_name,
	$project_root,
	$unit,

	%event_id,
	$soundcard_channels,
	$tk_input_channels,# for menubutton
	%e_bound,
	@ladspa_sorted,
	%oid_status,	
	$default_palette_yml, # default GUI colors
	$palette_file, # where to save selections

	%palette,
	%nama_palette,
);
our (
	
	# variables for GUI text input widgets

	$project,		
	$track_name,
	$ch_r,			# recording channel assignment
	$ch_m,			# monitoring channel assignment
	$save_id,		# name for save file


	# Widgets
	
	$mw, 			# main window
	$ew, 			# effects window
	$canvas, 		# to lay out the effects window

	# each part of the main window gets its own frame
	# to control the layout better

	$load_frame,
	$add_frame,
	$group_frame,
	$time_frame,
	$clock_frame,
	$oid_frame,
	$track_frame,
	$effect_frame,
	$iam_frame,
	$perl_eval_frame,
	$transport_frame,
	$mark_frame,
	$fast_frame, # forward, rewind, etc.

	## collected widgets (i may need to destroy them)

	%parent, # ->{mw} = $mw; # main window
			 # ->{ew} = $ew; # effects window
			 # eventually will contain all major frames
	$group_label, 
	$group_rw, # 
	$group_version, # 
	%track_widget, # for chains (tracks)
	%track_widget_remove, # what to destroy by remove_track
	%effects_widget, # for effects
	@widget_o, # for templates (oids) 
	%widget_o, # 
	%mark_widget, # marks

	@global_version_buttons, # to set the same version for
						  	#	all tracks
	$markers_armed, # set true to enable removing a mark
	$mark_remove,   # a button that sets $markers_armed
	$time_step,     # widget shows jump multiplier unit (seconds or minutes)
	$clock, 		# displays clock
	$setup_length,  # displays setup running time

	$project_label,	# project name

	$sn_label,		# project load/save/quit	
	$sn_text,
	$sn_load,
	$sn_new,
	$sn_quit,
	$sn_palette, # configure default master window colors
	$sn_namapalette, # configure nama-specific master-window colors
	$sn_effects_palette, # configure effects window colors
	@palettefields, # set by setPalette method
	@namafields,    # field names for color palette used by nama
	%namapalette,     # nama's indicator colors
	$rec,      # background color
	$mon,      # background color
	$off,      # background color


	### A separate box for entering IAM (and other) commands
	$iam_label,
	$iam_text,
	$iam, # variable for text entry
	$iam_execute,
	$iam_error, # unused

	# add track gui
	#
	$build_track_label,
	$build_track_text,
	$build_track_add_mono,
	$build_track_add_stereo,
	$build_track_rec_label,
	$build_track_rec_text,
	$build_track_mon_label,
	$build_track_mon_text,

	$build_new_take,

	# transport controls
	
	$transport_label,
	$transport_setup_and_connect,
	$transport_setup, # unused
	$transport_connect, # unused
	$transport_disconnect,
	$transport_new,
	$transport_start,
	$transport_stop,

	$old_bg, # initial background color.
	$old_abg, # initial active background color

	$sn_save_text,# text entry widget
	$sn_save,	# button to save settings
	$sn_recall,	# button to recall settings
);

package ::Graphical;  ## gui routines
use Modern::Perl; use Carp;
use Module::Load::Conditional qw(can_load);
use ::Assign qw(:all);
use ::Util qw(colonize);
no warnings 'uninitialized';

our @ISA = '::';      ## default to root class
# widgets

## The following methods belong to the Graphical interface class

sub hello {"make a window";}
sub loop {
	package ::;
	$attribs->{already_prompted} = 0;
	$term->tkRunning(1);
  	while (1) {
  		my ($user_input) = $term->readline($prompt) ;
  		::process_line( $user_input );
  	}
}

sub initialize_tk { can_load( modules => { Tk => undef } ) }

# the following graphical methods are placed in the root namespace
# allowing access to root namespace variables 
# with a package path

package ::;
[% qx(cat ./Graphical_subs.pl ) %]

[% qx(cat ./Refresh_subs.pl ) %]

1;
__END__


