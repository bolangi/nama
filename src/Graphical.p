# ------------ Graphical User Interface ------------

package ::;

our $VERSION = 1.071;

our ( 
[% qx(cat ./singletons.pl) %]
	$text->{term_attribs},
	$text->{term},
	$text->{prompt},
	$debug,
	$debug2,
	$mode->{preview},
	$gn{Main},
	$ui,
	%ti,
	%tn,
	%bn,
	
	%{$fx_cache->{full_label_to_index}},
	%{$fx_cache->{partial_label_to_full}},
	@{$fx_cache->{registry}},
	%{$fx->{applied}},
	%{$fx->{params}},
	%{$fx->{params_log}},
	%{$fx->{mute_level}},
	%{$fx->{unity_level}},
	%{$fx->{fade_out_level}},
	
	$gui->{_project_name}->{name},
	$config->{root_dir},
	$gui->{_seek_unit},

	%{$engine->{events}},
	$config->{soundcard_channels},
	$config->{soundcard_channels},# for menubutton
	%{$fx_cache->{split}},
	@{$fx_cache->{ladspa_sorted}},
	%oid_status,	
	$config->{gui_default_palette_yml}, # default GUI colors
	$file->{gui_palette}, # where to save selections

	%{$gui->{_palette}},
	%nama_palette,
);
our (
	
	# variables for GUI text input widgets

	$gui->{_project_name},		
	$gui->{_track_name},
	$gui->{_chr},			# recording channel assignment
	$gui->{_chm},			# monitoring channel assignment
	$gui->{_save_id},		# name for save file


	# Widgets
	
	$gui->{mw}, 			# main window
	$gui->{ew}, 			# effects window
	$gui->{canvas}, 		# to lay out the effects window

	# each part of the main window gets its own frame
	# to control the layout better

	$gui->{load_frame},
	$gui->{add_frame},
	$gui->{group_frame},
	$gui->{time_frame},
	$gui->{clock_frame},
	$oid_frame,
	$gui->{track_frame},
	$gui->{fx_frame},
	$gui->{iam_frame},
	$gui->{perl_frame},
	$gui->{transport_frame},
	$gui->{mark_frame},
	$gui->{seek_frame}, # forward, rewind, etc.

	## collected widgets (i may need to destroy them)

	%{$gui->{parents}}, # ->{mw} = $gui->{mw}; # main window
			 # ->{ew} = $gui->{ew}; # effects window
			 # eventually will contain all major frames
	$gui->{group_label}, 
	$gui->{group_rw}, # 
	$gui->{group_version}, # 
	%{$gui->{tracks}}, # for chains (tracks)
	%{$gui->{tracks_remove}}, # what to destroy by remove_track
	%{$gui->{fx}}, # for effects
	@widget_o, # for templates (oids) 
	%widget_o, # 
	%{$gui->{marks}}, # marks

	@{$gui->{global_version_buttons}}, # to set the same version for
						  	#	all tracks
	$gui->{_markers_armed}, # set true to enable removing a mark
	$gui->{mark_remove},   # a button that sets $gui->{_markers_armed}
	$gui->{seek_unit},     # widget shows jump multiplier unit (seconds or minutes)
	$gui->{clock}, 		# displays clock
	$gui->{setup_length},  # displays setup running time

	$gui->{project_head},	# project name

	$gui->{project_label},		# project load/save/quit	
	$gui->{project_entry},
	$gui->{load_project},
	$gui->{new_project},
	$gui->{quit},
	$gui->{_palette}, # configure default master window colors
	$gui->{_nama_palette}, # configure nama-specific master-window colors
	$gui->{_fx_palette}, # configure effects window colors
	@{$gui->{_palette_fields}}, # set by setPalette method
	@{$gui->{_nama_fields}},    # field names for color palette used by nama
	%{$gui->{_nama_palette}},     # nama's indicator colors
	$gui->{rec_bg},      # background color
	$gui->{mon_bg},      # background color
	$gui->{off_bg},      # background color


	### A separate box for entering IAM (and other) commands
	$iam_label,
	$iam_text,
	$iam, # variable for text entry
	$iam_execute,
	$iam_error, # unused

	# add track gui
	#
	$gui->{add_track}->{label},
	$gui->{add_track}->{text_entry},
	$gui->{add_track}->{add_mono},
	$gui->{add_track}->{add_stereo},
	$gui->{add_track}->{rec_label},
	$gui->{add_track}->{rec_text},
	$gui->{add_track}->{mon_label},
	$gui->{add_track}->{mon_text},

	$build_new_take,

	# transport controls
	
	$gui->{engine}->{label},
	$gui->{engine}->{arm},
	$transport_setup, # unused
	$transport_connect, # unused
	$gui->{engine}->{disconnect},
	$transport_new,
	$gui->{engine}->{start},
	$gui->{engine}->{stop},

	$gui->{_old_bg}, # initial background color.
	$gui->{_old_abg}, # initial active background color

	$gui->{savefile_entry},# text entry widget
	$gui->{save_project},	# button to save settings
	$gui->{load_savefile},	# button to recall settings
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
	$text->{term_attribs}->{already_prompted} = 0;
	$text->{term}->tkRunning(1);
  	while (1) {
  		my ($user_input) = $text->{term}->readline($text->{prompt}) ;
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


