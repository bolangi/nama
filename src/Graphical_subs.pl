# gui handling

# in the $gui variable, keys with leading _underscore
# indicate variables
#
# $gui->{_project_name}  # scalar/array/hash var
# $gui->{mw}             # Tk objects (widgets, frames, etc.)

sub init_gui {

	logsub("&init_gui");

	init_palettefields(); # keys only


	### 	Tk root window 

	# Tk main window
 	$gui->{mw} = MainWindow->new;  
	get_saved_colors();
	$gui->{mw}->optionAdd('*font', 'Helvetica 12');
	$gui->{mw}->optionAdd('*BorderWidth' => 1);
	$gui->{mw}->title("Ecasound/Nama"); 
	$gui->{mw}->deiconify;

	### init effect window

	$gui->{ew} = $gui->{mw}->Toplevel;
	$gui->{ew}->title("Effect Window");
	$gui->{ew}->deiconify; 
#	$gui->{ew}->withdraw;

	### Exit via Ctrl-C 

	$gui->{mw}->bind('<Control-Key-c>' => \&cleanup_exit); 
	$gui->{ew}->bind('<Control-Key-c>' => \&cleanup_exit);

    ## Press SPACE to start/stop transport

	$gui->{mw}->bind('<Control-Key- >' => \&toggle_transport); 
	$gui->{ew}->bind('<Control-Key- >' => \&toggle_transport); 
	
	$gui->{canvas} = $gui->{ew}->Scrolled('Canvas')->pack;
	$gui->{canvas}->configure(
		scrollregion =>[2,2,10000,10000],
		-width => 1200,
		-height => 700,	
		);
	$gui->{fx_frame} = $gui->{canvas}->Frame;
	my $id = $gui->{canvas}->createWindow(30,30, -window => $gui->{fx_frame},
											-anchor => 'nw');

	$gui->{project_head} = $gui->{mw}->Label->pack(-fill => 'both');

	$gui->{time_frame} = $gui->{mw}->Frame(
	#	-borderwidth => 20,
	#	-relief => 'groove',
	)->pack(
		-side => 'bottom', 
		-fill => 'both',
	);
	$gui->{mark_frame} = $gui->{time_frame}->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	$gui->{seek_frame} = $gui->{time_frame}->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	$gui->{transport_frame} = $gui->{mw}->Frame->pack(-side => 'bottom', -fill => 'both');
	# $oid_frame = $gui->{mw}->Frame->pack(-side => 'bottom', -fill => 'both');
	$gui->{clock_frame} = $gui->{mw}->Frame->pack(-side => 'bottom', -fill => 'both');
	#$gui->{group_frame} = $gui->{mw}->Frame->pack(-side => 'bottom', -fill => 'both');
 	my $track_canvas = $gui->{mw}->Scrolled('Canvas')->pack(-side => 'bottom', -fill => 'both');
 	$track_canvas->configure(
 		-scrollregion =>[2,2,400,9600],
 		-width => 400,
 		-height => 400,	
 		);
	$gui->{track_frame} = $track_canvas->Frame; # ->pack(-fill => 'both');
	#$gui->{track_frame} = $gui->{mw}->Frame;
 	my $id2 = $track_canvas->createWindow(0,0,
		-window => $gui->{track_frame}, 
		-anchor => 'nw');
 	#$gui->{group_label} = $gui->{group_frame}->Menubutton(-text => "GROUP",
 #										-tearoff => 0,
 #										-width => 13)->pack(-side => 'left');
		
	$gui->{add_frame} = $gui->{mw}->Frame->pack(-side => 'bottom', -fill => 'both');
	$gui->{perl_frame} = $gui->{mw}->Frame->pack(-side => 'bottom', -fill => 'both');
	$gui->{iam_frame} = $gui->{mw}->Frame->pack(-side => 'bottom', -fill => 'both');
	$gui->{load_frame} = $gui->{mw}->Frame->pack(-side => 'bottom', -fill => 'both');
#	my $blank = $gui->{mw}->Label->pack(-side => 'left');



	$gui->{project_label} = $gui->{load_frame}->Label(
		-text => "    Project name: "
	)->pack(-side => 'left');
	$gui->{project_entry} = $gui->{load_frame}->Entry(
		-textvariable => \$gui->{_project_name},
		-width => 25
	)->pack(-side => 'left');

	$gui->{load_project} = $gui->{load_frame}->Button->pack(-side => 'left');;
	$gui->{new_project} = $gui->{load_frame}->Button->pack(-side => 'left');;
	$gui->{quit} = $gui->{load_frame}->Button->pack(-side => 'left');
	$gui->{save_project} = $gui->{load_frame}->Button->pack(-side => 'left');
	$gui->{savefile_entry} = $gui->{load_frame}->Entry(
									-textvariable => \$gui->{_save_id},
									-width => 15
									)->pack(-side => 'left');
	$gui->{load_savefile} = $gui->{load_frame}->Button->pack(-side => 'left');
	$gui->{palette} = $gui->{load_frame}->Menubutton(-tearoff => 0)
		->pack( -side => 'left');
	$gui->{nama_palette} = $gui->{load_frame}->Menubutton(-tearoff => 0)
		->pack( -side => 'left');
	$gui->{add_track}->{label} = $gui->{add_frame}->Label(
		-text => "New track name: ")->pack(-side => 'left');
	$gui->{add_track}->{text_entry} = $gui->{add_frame}->Entry(
		-textvariable => \$gui->{_track_name}, 
		-width => 12
	)->pack(-side => 'left');
	$gui->{add_track}->{rec_label} = $gui->{add_frame}->Label(
		-text => "Input channel or client:"
	)->pack(-side => 'left');
	$gui->{add_track}->{rec_text} = $gui->{add_frame}->Entry(
		-textvariable => \$gui->{_chr}, 
		-width => 10
	)->pack(-side => 'left');
	$gui->{add_track}->{add_mono} = $gui->{add_frame}->Button->pack(-side => 'left');;
	$gui->{add_track}->{add_stereo}  = $gui->{add_frame}->Button->pack(-side => 'left');;

	$gui->{load_project}->configure(
		-text => 'Load',
		-command => sub{ load_project(
			name => remove_spaces($gui->{_project_name}),
			)});
	$gui->{new_project}->configure( 
		-text => 'Create',
		-command => sub{ load_project(
							name => remove_spaces($gui->{_project_name}),
							create => 1)});
	$gui->{save_project}->configure(
		-text => 'Save settings',
		-command => #sub { print "save_id: $gui->{_save_id}\n" });
		 sub {save_state($gui->{_save_id}) });
	$gui->{load_savefile}->configure(
		-text => 'Recall settings',
 		-command => sub {load_project (name => $project->{name},  # current project 
 										settings => $gui->{_save_id})},
				);
	$gui->{quit}->configure(-text => "Quit",
		 -command => sub { 
				return if transport_running();
				save_state($gui->{_save_id});
				print "Exiting... \n";		
				#$text->{term}->tkRunning(0);
				#$gui->{ew}->destroy;
				#$gui->{mw}->destroy;
				#::process_command('quit');
				exit;
				 });
	$gui->{palette}->configure(
		-text => 'Palette',
		-relief => 'raised',
	);
	$gui->{nama_palette}->configure(
		-text => 'Nama palette',
		-relief => 'raised',
	);

my @color_items = map { [ 'command' => $_, 
							-command  => colorset('mw', $_ ) ]
						} @{$gui->{_palette_fields}};
$gui->{palette}->AddItems( @color_items);

@color_items = map { [ 'command' => $_, 
							-command  => namaset( $_ ) ]
						} @{$gui->{_nama_fields}};

	$gui->{add_track}->{add_mono}->configure( 
			-text => 'Add Mono Track',
			-command => sub { 
					return if $gui->{_track_name} =~ /^\s*$/;	
			add_track(remove_spaces($gui->{_track_name})) }
	);
	$gui->{add_track}->{add_stereo}->configure( 
			-text => 'Add Stereo Track',
			-command => sub { 
								return if $gui->{_track_name} =~ /^\s*$/;	
								add_track(remove_spaces($gui->{_track_name}));
								process_command('stereo');
	});

	my @labels = 
		qw(Track Name Version Status Source Send Volume Mute Unity Pan Center Effects);
	my @widgets;
	map{ push @widgets, $gui->{track_frame}->Label(-text => $_)  } @labels;
	$widgets[0]->grid(@widgets[1..$#widgets]);


}

sub transport_gui {
	my $ui = shift;
	logsub("&transport_gui");

	$gui->{engine_label} = $gui->{transport_frame}->Label(
		-text => 'TRANSPORT',
		-width => 12,
		)->pack(-side => 'left');;
	$gui->{engine_start} = $gui->{transport_frame}->Button->pack(-side => 'left');
	$gui->{engine_stop} = $gui->{transport_frame}->Button->pack(-side => 'left');

	$gui->{engine_stop}->configure(-text => "Stop",
	-command => sub { 
					stop_transport();
				}
		);
	$gui->{engine_start}->configure(
		-text => "Start",
		-command => sub { 
		return if transport_running();
		my $color = engine_mode_color();
		$ui->project_label_configure(-background => $color);
		start_transport();
				});

#preview_button();
#mastering_button();

}
sub time_gui {
	my $ui = shift;
	logsub("&time_gui");

	my $time_label = $gui->{clock_frame}->Label(
		-text => 'TIME', 
		-width => 12);
	#print "bg: $gui->{_nama_palette}->{ClockBackground}, fg:$gui->{_nama_palette}->{ClockForeground}\n";
	$gui->{clock} = $gui->{clock_frame}->Label(
		-text => '0:00', 
		-width => 8,
		-background => $gui->{_nama_palette}->{ClockBackground},
		-foreground => $gui->{_nama_palette}->{ClockForeground},
		);
	my $length_label = $gui->{clock_frame}->Label(
		-text => 'LENGTH',
		-width => 10,
		);
	$gui->{setup_length} = $gui->{clock_frame}->Label(
	#	-width => 8,
		);

	for my $w ($time_label, $gui->{clock}, $length_label, $gui->{setup_length}) {
		$w->pack(-side => 'left');	
	}

	$gui->{mark_frame} = $gui->{time_frame}->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	$gui->{seek_frame} = $gui->{time_frame}->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	# jump

	my $jump_label = $gui->{seek_frame}->Label(-text => q(JUMP), -width => 12);
	my @pluses = (1, 5, 10, 30, 60);
	my @minuses = map{ - $_ } reverse @pluses;
	my @fw = map{ my $d = $_; $gui->{seek_frame}->Button(
			-text => $d,
			-command => sub { jump($d) },
			)
		}  @pluses ;
	my @rew = map{ my $d = $_; $gui->{seek_frame}->Button(
			-text => $d,
			-command => sub { jump($d) },
			)
		}  @minuses ;
	my $beg = $gui->{seek_frame}->Button(
			-text => 'Beg',
			-command => \&to_start,
			);
	my $end = $gui->{seek_frame}->Button(
			-text => 'End',
			-command => \&to_end,
			);

	$gui->{seek_unit} = $gui->{seek_frame}->Button( 
			-text => 'Sec',
			);
		for my $w($jump_label, @rew, $beg, $gui->{seek_unit}, $end, @fw){
			$w->pack(-side => 'left')
		}

	$gui->{seek_unit}->configure (-command => sub { &toggle_unit; &show_unit });

	# Marks
	
	my $mark_label = $gui->{mark_frame}->Label(
		-text => q(MARK), 
		-width => 12,
		)->pack(-side => 'left');
		
	my $drop_mark = $gui->{mark_frame}->Button(
		-text => 'Place',
		-command => \&drop_mark,
		)->pack(-side => 'left');	
		
	$gui->{mark_remove} = $gui->{mark_frame}->Button(
		-text => 'Remove',
		-command => \&arm_mark_toggle,
	)->pack(-side => 'left');	

}
sub toggle_unit {
	if ($gui->{_seek_unit} == 1){
		$gui->{_seek_unit} = 60;
		
	} else{ $gui->{_seek_unit} = 1; }
}
sub show_unit { $gui->{seek_unit}->configure(
	-text => ($gui->{_seek_unit} == 1 ? 'Sec' : 'Min') 
)}

sub paint_button {
	my $ui = shift;
	my ($button, $color) = @_;
	$button->configure(-background => $color,
						-activebackground => $color);
}

sub engine_mode_color {
		if ( user_rec_tracks()  ){ 
				$gui->{_nama_palette}->{RecBackground} # live recording 
		} elsif ( ::ChainSetup::really_recording() ){ 
				$gui->{_nama_palette}->{Mixdown}	# mixdown only 
		} elsif ( user_mon_tracks() ){  
				$gui->{_nama_palette}->{Play}; 	# just playback
		} else { $gui->{_old_bg} } 
}
sub user_rec_tracks { some_user_tracks('REC') }
sub user_mon_tracks { some_user_tracks('MON') }

sub some_user_tracks {
	my $which = shift;
	my @user_tracks = ::Track::all();
	splice @user_tracks, 0, 2; # drop Master and Mixdown tracks
	return unless @user_tracks;
	my @selected_user_tracks = grep { $_->rec_status eq $which } @user_tracks;
	return unless @selected_user_tracks;
	map{ $_->n } @selected_user_tracks;
}

sub flash_ready {

	my $color = engine_mode_color();
	logpkg('debug', "flash color: $color");
	$ui->length_display(-background => $color);
	$ui->project_label_configure(-background => $color) unless $mode->{preview};
 	$engine->{events}->{heartbeat} = AE::timer(5, 0, \&reset_engine_mode_color_display);
}
sub reset_engine_mode_color_display { $ui->project_label_configure(
	-background => $gui->{_nama_palette}->{OffBackground} )
}
sub set_engine_mode_color_display { $ui->project_label_configure(-background => engine_mode_color()) }
sub group_gui {  
	my $ui = shift;
	my $group = $bn{Main}; 
	my $dummy = $gui->{track_frame}->Label(-text => ' '); 
	$gui->{group_label} = 	$gui->{track_frame}->Label(
			-text => "G R O U P",
			-foreground => $gui->{_nama_palette}->{GroupForeground},
			-background => $gui->{_nama_palette}->{GroupBackground},

 );
	$gui->{group_version} = $gui->{track_frame}->Menubutton( 
		-text => q( ), 
		-tearoff => 0,
		-foreground => $gui->{_nama_palette}->{GroupForeground},
		-background => $gui->{_nama_palette}->{GroupBackground},
);
	$gui->{group_rw} = $gui->{track_frame}->Menubutton( 
		-text    => $group->rw,
	 	-tearoff => 0,
		-foreground => $gui->{_nama_palette}->{GroupForeground},
		-background => $gui->{_nama_palette}->{GroupBackground},
);


		
		$gui->{group_rw}->AddItems([
			'command' => 'REC',
			-background => $gui->{_old_bg},
			-command => sub { 
				return if ::eval_iam("engine-status") eq 'running';
				$group->set(rw => 'REC');
				$gui->{group_rw}->configure(-text => 'REC');
				refresh();
				::reconfigure_engine()
				}
			],[
			'command' => 'MON',
			-background => $gui->{_old_bg},
			-command => sub { 
				return if ::eval_iam("engine-status") eq 'running';
				$group->set(rw => 'MON');
				$gui->{group_rw}->configure(-text => 'MON');
				refresh();
				::reconfigure_engine()
				}
			],[
			'command' => 'OFF',
			-background => $gui->{_old_bg},
			-command => sub { 
				return if ::eval_iam("engine-status") eq 'running';
				$group->set(rw => 'OFF');
				$gui->{group_rw}->configure(-text => 'OFF');
				refresh();
				::reconfigure_engine()
				}
			]);
			$dummy->grid($gui->{group_label}, $gui->{group_version}, $gui->{group_rw});
			#$ui->global_version_buttons;

}
sub global_version_buttons {
	my $version = $gui->{group_version};
	$version and map { $_->destroy } $version->children;
		
	logpkg('debug', "making global version buttons range: " ,
		join ' ',1..$bn{Main}->last);

			$version->radiobutton( 

				-label => (''),
				-value => 0,
				-command => sub { 
					$bn{Main}->set(version => 0); 
					$version->configure(-text => " ");
					::reconfigure_engine();
					refresh();
					}
			);

 	for my $v (1..$bn{Main}->last) { 

	# the highest version number of all tracks in the
	# $bn{Main} group
	
	my @user_track_indices = grep { $_ > 2 } map {$_->n} ::Track::all();
	
		next unless grep{  grep{ $v == $_ } @{ $ti{$_}->versions } }
			@user_track_indices;
		

			$version->radiobutton( 

				-label => ($v ? $v : ''),
				-value => $v,
				-command => sub { 
					$bn{Main}->set(version => $v); 
					$version->configure(-text => $v);
					::reconfigure_engine();
					refresh();
					}

			);
 	}
}
sub track_gui { 
	logsub("&track_gui");
	my $ui = shift;
	my $n = shift;
	return if $ti{$n}->hide;
	
	logpkg('debug', "found index: $n");
	my @rw_items = @_ ? @_ : (
			[ 'command' => "REC",
				-foreground => 'red',
				-command  => sub { 
					return if ::eval_iam("engine-status") eq 'running';
					$ti{$n}->set(rw => "REC");
					
					$ui->refresh_track($n);
					#refresh_group();
					::reconfigure_engine();
			}],
			[ 'command' => "MON",
				-command  => sub { 
					return if ::eval_iam("engine-status") eq 'running';
					$ti{$n}->set(rw => "MON");
					$ui->refresh_track($n);
					#refresh_group();
					::reconfigure_engine();
			}],
			[ 'command' => "OFF", 
				-command  => sub { 
					return if ::eval_iam("engine-status") eq 'running';
					$ti{$n}->set(rw => "OFF");
					$ui->refresh_track($n);
					#refresh_group();
					::reconfigure_engine();
			}],
		);
	my ($number, $name, $version, $rw, $ch_r, $ch_m, $vol, $mute, $solo, $unity, $pan, $center);
	$number = $gui->{track_frame}->Label(-text => $n,
									-justify => 'left');
	my $stub = " ";
	$stub .= $ti{$n}->version;
	$name = $gui->{track_frame}->Label(
			-text => $ti{$n}->name,
			-justify => 'left');
	$version = $gui->{track_frame}->Menubutton( 
					-text => $stub,
					# -relief => 'sunken',
					-tearoff => 0);
	my @versions = '';
	#push @versions, @{$ti{$n}->versions} if @{$ti{$n}->versions};
	my $ref = ref $ti{$n}->versions ;
		$ref =~ /ARRAY/ and 
		push (@versions, @{$ti{$n}->versions}) or
		croak "chain $n, found unexpectedly $ref\n";;
	my $indicator;
	for my $v (@versions) {
					$version->radiobutton(
						-label => $v,
						-value => $v,
						-variable => \$indicator,
						-command => 
		sub { 
			$ti{$n}->set( version => $v );
			return if $ti{$n}->rec_status eq "REC";
			$version->configure( -text=> $ti{$n}->current_version );
			::reconfigure_engine();
			}
					);
	}

	$ch_r = $gui->{track_frame}->Menubutton(
					# -relief => 'groove',
					-tearoff => 0,
				);
	my @range;
	push @range, 1..$config->{soundcard_channels} if $n > 2; # exclude Master/Mixdown
	
	for my $v (@range) {
		$ch_r->radiobutton(
			-label => $v,
			-value => $v,
			-command => sub { 
				return if ::eval_iam("engine-status") eq 'running';
			#	$ti{$n}->set(rw => 'REC');
				$ti{$n}->source($v);
				$ui->refresh_track($n) }
			)
	}
	@range = ();

	push @range, "off" if $n > 2;
	push @range, 1..$config->{soundcard_channels} if $n != 2; # exclude Mixdown

	$ch_m = $gui->{track_frame}->Menubutton(
					-tearoff => 0,
					# -relief => 'groove',
				);
				for my $v (@range) {
					$ch_m->radiobutton(
						-label => $v,
						-value => $v,
						-command => sub { 
							return if ::eval_iam("engine-status") eq 'running';
							$ti{$n}->set_send($v);
							$ui->refresh_track($n);
							::reconfigure_engine();
 						}
				 		)
				}
	$rw = $gui->{track_frame}->Menubutton(
		-text => $ti{$n}->rw,
		-tearoff => 0,
		# -relief => 'groove',
	);
	map{$rw->AddItems($_)} @rw_items; 

 
	my $p_num = 0; # needed when using parameter controllers
	# Volume
	
	if ( ::need_vol_pan($ti{$n}->name, "vol") ){

		my $vol_id = $ti{$n}->vol;

		logpkg('debug', "vol effect_id: $vol_id");
		my %p = ( 	parent => \$gui->{track_frame},
				chain  => $n,
				type => 'ea',
				effect_id => $vol_id,
				p_num		=> $p_num,
				length => 300, 
				);


		 logpkg('debug',sub{my %q = %p; delete $q{parent}; print
		 "=============\n%p\n",yaml_out(\%q)});

		$vol = make_scale ( \%p );
		# Mute

		$mute = $gui->{track_frame}->Button(
			-command => sub { 
				if ($fx->{params}->{$vol_id}->[0] != $config->{mute_level}->{$fx->{applied}->{$vol_id}->{type}} and
					$fx->{params}->{$vol_id}->[0] != $config->{fade_out_level}->{$fx->{applied}->{$vol_id}->{type}}
				) {  # non-zero volume
					$ti{$n}->mute;
					$mute->configure(-background => $gui->{_nama_palette}->{Mute});
				}
				else {
					$ti{$n}->unmute;
					$mute->configure(-background => $gui->{_nama_palette}->{OffBackground})
				}
			}	
		  );

		# Unity

		$unity = $gui->{track_frame}->Button(
				-command => sub { 
					::effect_update_copp_set(
						$vol_id, 
						0, 
						$config->{unity_level}->{$fx->{applied}->{$vol_id}->{type}});
				}
		  );
	} else {

		$vol = $gui->{track_frame}->Label;
		$mute = $gui->{track_frame}->Label;
		$unity = $gui->{track_frame}->Label;

	}

	if ( ::need_vol_pan($ti{$n}->name, "pan") ){
	  
		# Pan
		
		my $pan_id = $ti{$n}->pan;
		
		logpkg('debug', "pan effect_id: $pan_id");
		$p_num = 0;           # first parameter
		my %q = ( 	parent => \$gui->{track_frame},
				chain  => $n,
				type => 'epp',
				effect_id => $pan_id,
				p_num		=> $p_num,
				);
		# logpkg('debug',sub{ my %q = %p; delete $q{parent}; print "x=============\n%p\n",yaml_out(\%q) });
		$pan = make_scale ( \%q );

		# Center

		$center = $gui->{track_frame}->Button(
			-command => sub { 
				::effect_update_copp_set($pan_id, 0, 50);
			}
		  );
	} else { 

		$pan = $gui->{track_frame}->Label;
		$center = $gui->{track_frame}->Label;
	}
	
	my $effects = $gui->{fx_frame}->Frame->pack(-fill => 'both');;

	# effects, held by track_widget->n->effects is the frame for
	# all effects of the track

	@{ $gui->{tracks}->{$n} }{qw(name version rw ch_r ch_m mute effects)} 
		= ($name,  $version, $rw, $ch_r, $ch_m, $mute, \$effects);#a ref to the object
	#logpkg('debug', "=============$gui->{tracks}\n",sub{yaml_out($gui->{tracks})});
	my $independent_effects_frame 
		= ${ $gui->{tracks}->{$n}->{effects} }->Frame->pack(-fill => 'x');


	my $controllers_frame 
		= ${ $gui->{tracks}->{$n}->{effects} }->Frame->pack(-fill => 'x');
	
	# parents are the independent effects
	# children are controllers for various paramters

	$gui->{tracks}->{$n}->{parents} = $independent_effects_frame;

	$gui->{tracks}->{$n}->{children} = $controllers_frame;
	
	$independent_effects_frame
		->Label(-text => uc $ti{$n}->name )->pack(-side => 'left');

	#logpkg('debug',"Number: $n"),MainLoop if $n == 2;
	my @tags = qw( EF P1 P2 L1 L2 L3 L4 );
	my @starts =   ( $fx_cache->{split}->{cop}{a}, 
					 $fx_cache->{split}->{preset}{a}, 
					 $fx_cache->{split}->{preset}{b}, 
					 $fx_cache->{split}->{ladspa}{a}, 
					 $fx_cache->{split}->{ladspa}{b}, 
					 $fx_cache->{split}->{ladspa}{c}, 
					 $fx_cache->{split}->{ladspa}{d}, 
					);
	my @ends   =   ( $fx_cache->{split}->{cop}{z}, 
					 $fx_cache->{split}->{preset}{b}, 
					 $fx_cache->{split}->{preset}{z}, 
					 $fx_cache->{split}->{ladspa}{b}-1, 
					 $fx_cache->{split}->{ladspa}{c}-1, 
					 $fx_cache->{split}->{ladspa}{d}-1, 
					 $fx_cache->{split}->{ladspa}{z}, 
					);
	my @add_effect;

	map{push @add_effect, effect_button($n, shift @tags, shift @starts, shift @ends)} 1..@tags;
	
	$number->grid($name, $version, $rw, $ch_r, $ch_m, $vol, $mute, $unity, $pan, $center, @add_effect);

	$gui->{tracks_remove}->{$n} = [
		grep{ $_ } (
			$number, 
			$name, 
			$version, 
			$rw, 
			$ch_r, 
			$ch_m, 
			$vol,
			$mute, 
			$unity, 
			$pan, 
			$center, 
			@add_effect,
			$effects,
		)
	];

	$ui->refresh_track($n);

}

sub remove_track_gui {
 	my $ui = shift;
 	my $n = shift;
	logsub("&remove_track_gui");
	return unless $gui->{tracks_remove}->{$n};
 	map {$_->destroy  } @{ $gui->{tracks_remove}->{$n} };
	delete $gui->{tracks_remove}->{$n};
	delete $gui->{tracks}->{$n};
}

sub paint_mute_buttons {
	map{ $gui->{tracks}->{$_}{mute}->configure(
			-background 		=> $gui->{_nama_palette}->{Mute},

			)} grep { $ti{$_}->old_vol_level}# muted tracks
				map { $_->n } ::Track::all();  # track numbers
}

sub create_master_and_mix_tracks { 
	logsub("&create_master_and_mix_tracks");


	my @rw_items = (
			[ 'command' => "MON",
				-command  => sub { 
						return if ::eval_iam("engine-status") eq 'running';
						$tn{Master}->set(rw => "MON");
						$ui->refresh_track($tn{Master}->n);
			}],
			[ 'command' => "OFF", 
				-command  => sub { 
						return if ::eval_iam("engine-status") eq 'running';
						$tn{Master}->set(rw => "OFF");
						$ui->refresh_track($tn{Master}->n);
			}],
		);

	$ui->track_gui( $tn{Master}->n, @rw_items );

	$ui->track_gui( $tn{Mixdown}->n); 

	#$ui->group_gui('Main');
}

sub update_version_button {
	my $ui = shift;
	my ($n, $v) = @_;
	carp ("no version provided \n") if ! $v;
	my $w = $gui->{tracks}->{$n}->{version};
					$w->radiobutton(
						-label => $v,
						-value => $v,
						-command => 
		sub { $gui->{tracks}->{$n}->{version}->configure(-text=>$v) 
				unless $ti{$n}->rec_status eq "REC" }
					);
}

sub add_effect_gui {
		logsub("&add_effect_gui");
		my $ui = shift;
		my %p 			= %{shift()};
		my ($n,$code,$id,$parent_id,$parameter) =
			@p{qw(chain type effect_id parent_id parameter)};
		my $i = $fx_cache->{full_label_to_index}->{$code};

		logpkg('debug', sub{yaml_out(\%p)});

		logpkg('debug', "effect_id: $id, parent_id: $parent_id");
		# $id is determined by effect_init, which will return the
		# existing effect_id if supplied

		# check display format, may be 'scale' 'field' or 'hidden'
		
		my $display_type = $fx->{applied}->{$id}->{display}; # individual setting
		defined $display_type or $display_type = $fx_cache->{registry}->[$i]->{display}; # template
		logpkg('debug', "display type: $display_type");

		return if $display_type eq q(hidden);

		my $frame ;
		if ( ! $parent_id ){ # independent effect
			$frame = $gui->{tracks}->{$n}->{parents}->Frame->pack(
				-side => 'left', 
				-anchor => 'nw',)
		} else {                 # controller
			$frame = $gui->{tracks}->{$n}->{children}->Frame->pack(
				-side => 'top', 
				-anchor => 'nw')
		}

		$gui->{fx}->{$id} = $frame; 
		# we need a separate frame so title can be long

		# here add menu items for Add Controller, and Remove

		my $parentage = $fx_cache->{registry}->[ $fx_cache->{full_label_to_index}->{ $fx->{applied}->{$parent_id}->{type}} ]
			->{name};
		$parentage and $parentage .=  " - ";
		logpkg('debug', "parentage: $parentage");
		my $eff = $frame->Menubutton(
			-text => $parentage. $fx_cache->{registry}->[$i]->{name}, -tearoff => 0,);

		$eff->AddItems([
			'command' => "Remove",
			-command => sub { remove_effect($id) }
		]);
		$eff->grid();
		my @labels;
		my @sliders;

		# make widgets

		for my $p (0..$fx_cache->{registry}->[$i]->{count} - 1 ) {
		my @items;
		#logpkg('debug', "p_first: $p_first, p_last: $p_last");
		for my $j ($fx_cache->{split}->{ctrl}{a}..$fx_cache->{split}->{ctrl}{z}) {   
			push @items, 				
				[ 'command' => $fx_cache->{registry}->[$j]->{name},
					-command => sub { add_effect ({
							parent_id => $id,
							chain => $n,
							values => [ $p  + 1 ],
							type => $fx_cache->{registry}->[$j]->{code} } )  }
				];

		}
		push @labels, $frame->Menubutton(
				-text => $fx_cache->{registry}->[$i]->{params}->[$p]->{name},
				-menuitems => [@items],
				-tearoff => 0,
		);
			logpkg('debug', "parameter name: ",
				$fx_cache->{registry}->[$i]->{params}->[$p]->{name});
			my $v =  # for argument vector 
			{	parent => \$frame,
				effect_id => $id, 
				p_num  => $p,
			};
			push @sliders,make_scale($v);
		}

		if (@sliders) {

			$sliders[0]->grid(@sliders[1..$#sliders]);
			 $labels[0]->grid(@labels[1..$#labels]);
		}
}


sub project_label_configure{ 
	my $ui = shift;
	$gui->{project_head}->configure( @_ ) }

sub length_display{ 
	my $ui = shift;
	$gui->{setup_length}->configure(@_)};

sub clock_config { 
	my $ui = shift;
	$gui->{clock}->configure( @_ )}

sub manifest { $gui->{ew}->deiconify() }

sub destroy_widgets {

	map{ $_->destroy } map{ $_->children } $gui->{fx_frame};
	#my @children = $gui->{group_frame}->children;
	#map{ $_->destroy  } @children[1..$#children];
	my @children = $gui->{track_frame}->children;
	# leave field labels (first row)
	map{ $_->destroy  } @children[11..$#children]; # fragile
	%{$gui->{marks}} and map{ $_->destroy } values %{$gui->{marks}};
}
sub remove_effect_gui { 
	my $ui = shift;
	logsub("&remove_effect_gui");
	my $id = shift;
	my $n = $fx->{applied}->{$id}->{chain};
	logpkg('debug', "id: $id, chain: $n");

	logpkg('debug', "i have widgets for these ids: ", join " ",keys %{$gui->{fx}});
	logpkg('debug', "preparing to destroy: $id");
	return unless defined $gui->{fx}->{$id};
	$gui->{fx}->{$id}->destroy();
	delete $gui->{fx}->{$id}; 

}

sub effect_button {
	logsub("&effect_button");
	my ($n, $label, $start, $end) = @_;
	logpkg('debug', "chain $n label $label start $start end $end");
	my @items;
	my $widget;
	my @indices = ($start..$end);
	if ($start >= $fx_cache->{split}->{ladspa}{a} and $start <= $fx_cache->{split}->{ladspa}{z}){
		@indices = ();
		@indices = @{$fx_cache->{ladspa_sorted}}[$start..$end];
		logpkg('debug', "length sorted indices list: ",scalar @indices );
	logpkg('debug', "Indices: @indices");
	}
		
		for my $j (@indices) { 
		push @items, 				
			[ 'command' => "$fx_cache->{registry}->[$j]->{count} $fx_cache->{registry}->[$j]->{name}" ,
				-command  => sub { 
					 add_effect( {chain => $n, type => $fx_cache->{registry}->[$j]->{code} } ); 
					$gui->{ew}->deiconify; # display effects window
					} 
			];
	}
	$widget = $gui->{track_frame}->Menubutton(
		-text => $label,
		-tearoff =>0,
		# -relief => 'raised',
		-menuitems => [@items],
	);
	$widget;
}

sub make_scale {
	
	logsub("&make_scale");
	my $ref = shift;
	my %p = %{$ref};
# 	%p contains following:
# 	effect_id   => operator id, to access dynamic effect params in %{$fx->{params}}
# 	parent => parent widget, i.e. the frame
# 	p_num      => parameter number, starting at 0
# 	length       => length widget # optional 
	my $id = $p{effect_id};
	my $n = $fx->{applied}->{$id}->{chain};
	my $code = $fx->{applied}->{$id}->{type};
	my $p  = $p{p_num};
	my $i  = $fx_cache->{full_label_to_index}->{$code};

	logpkg('debug', "id: $id code: $code");
	

	# check display format, may be text-field or hidden,

	logpkg('debug',"i: $i code: $fx_cache->{registry}->[$i]->{code} display: $fx_cache->{registry}->[$i]->{display}");
	my $display_type = $fx->{applied}->{$id}->{display};
	defined $display_type or $display_type = $fx_cache->{registry}->[$i]->{display};
	logpkg('debug', "display type: $display_type");
	return if $display_type eq q(hidden);


	logpkg('debug', "to: ", $fx_cache->{registry}->[$i]->{params}->[$p]->{end}) ;
	logpkg('debug', "p: $p code: $code");
	logpkg('debug', "is_log_scale: ".is_log_scale($i,$p));

	# set display type to individually specified value if it exists
	# otherwise to the default for the controller class


	
	if 	($display_type eq q(scale) ) { 

		# return scale type controller widgets
		my $frame = ${ $p{parent} }->Frame;
			

		#return ${ $p{parent} }->Scale(
		
		my $log_display;
		
		my $controller = $frame->Scale(
			-variable => \$fx->{params}->{$id}->[$p],
			-orient => 'horizontal',
			-from   =>  $fx_cache->{registry}->[$i]->{params}->[$p]->{begin},
			-to     =>  $fx_cache->{registry}->[$i]->{params}->[$p]->{end},
			-resolution => resolution($i, $p),
		  -width => 12,
		  -length => $p{length} ? $p{length} : 100,
		  -command => sub { ::effect_update($id, $p, $fx->{params}->{$id}->[$p]) },
			-state => is_read_only($id,$p) ? 'disabled' : 'normal',
		  );

		# auxiliary field for logarithmic display
		if ( is_log_scale($i, $p)  )
		#	or $code eq 'ea') 
			{
			my $log_display = $frame->Label(
				-text => exp $fx_cache->{registry}->[$i]->{params}->[$p]->{default},
				-width => 5,
				);
			$controller->configure(
				-variable => \$fx->{params_log}->{$id}->[$p],
		  		-command => sub { 
					$fx->{params}->{$id}->[$p] = exp $fx->{params_log}->{$id}->[$p];
					::effect_update($id, $p, $fx->{params}->{$id}->[$p]);
					$log_display->configure(
						-text => 
						$fx_cache->{registry}->[$i]->{params}->[$p]->{name} =~ /hz|frequency/i
							? int $fx->{params}->{$id}->[$p]
							: dn($fx->{params}->{$id}->[$p], 1)
						);
					}
				);
		$log_display->grid($controller);
		}
		else { $controller->grid; }

		return $frame;

	}	

	elsif ($display_type eq q(field) ){ 

	 	# then return field type controller widget

		return ${ $p{parent} }->Entry(
			-textvariable =>\$fx->{params}->{$id}->[$p],
			-width => 6,
	#		-command => sub { ::effect_update($id, $p, $fx->{params}->{$id}->[$p]) },
			# doesn't work with Entry widget
			);	

	}
	else { croak "missing or unexpected display type: $display_type" }

}

sub is_log_scale {
	my ($i, $p) = @_;
	$fx_cache->{registry}->[$i]->{params}->[$p]->{hint} =~ /logarithm/ 
}
sub resolution {
	my ($i, $p) = @_;
	my $res = $fx_cache->{registry}->[$i]->{params}->[$p]->{resolution};
	return $res if $res;
	my $end = $fx_cache->{registry}->[$i]->{params}->[$p]->{end};
	my $beg = $fx_cache->{registry}->[$i]->{params}->[$p]->{begin};
	return 1 if abs($end - $beg) > 30;
	return abs($end - $beg)/100
}

sub arm_mark_toggle { 
	if ($gui->{_markers_armed}) {
		$gui->{_markers_armed} = 0;
		$gui->{mark_remove}->configure( -background => $gui->{_nama_palette}->{OffBackground});
	 } else{
		$gui->{_markers_armed} = 1;
		$gui->{mark_remove}->configure( -background => $gui->{_nama_palette}->{MarkArmed});
	}
}
sub marker {
	my $ui = shift;
	my $mark = shift; # Mark
	#print "mark is ", ref $mark, $/;
	my $pos = $mark->time;
	#print $pos, " ", int $pos, $/;
		$gui->{marks}->{$pos} = $gui->{mark_frame}->Button( 
			-text => (join " ",  colonize( int $pos ), $mark->name),
			-background => $gui->{_nama_palette}->{OffBackground},
			-command => sub { ::mark($mark) },
		)->pack(-side => 'left');
}

sub restore_time_marks {
	my $ui = shift;
	map{ $ui->marker($_) } ::Mark::all() ; 
	$gui->{seek_unit}->configure( -text => $gui->{_seek_unit} == 1 ? q(Sec) : q(Min) )
}
sub destroy_marker {
	my $ui = shift;
	my $pos = shift;
	$gui->{marks}->{$pos}->destroy; 
}


sub get_saved_colors {
	logsub("&get_saved_colors");

	# aliases
	
	$gui->{_old_bg} = $gui->{_palette}{mw}{background};
	$gui->{_old_abg} = $gui->{_palette}{mw}{activeBackground};
	$gui->{_old_bg} //= '#d915cc1bc3cf';
	#print "pb: $gui->{_palette}{mw}{background}\n";


	my $pal = $file->gui_palette;
	$pal .= '.json' unless $pal =~ /\.json$/;
	say "pal $pal";
	$pal = -f $pal 
			? scalar read_file($pal)
			: get_data_section('default_palette_json');
	my $ref = decode($pal, 'json');
	#say "palette file",yaml_out($ref);

	assign_singletons({ data => $ref });
	
	$gui->{_old_abg} = $gui->{_palette}->{mw}{activeBackground};
	$gui->{_old_abg} = $gui->{project_head}->cget('-activebackground') unless $gui->{_old_abg};
	#print "1palette: \n", yaml_out( $gui->{_palette} );
	#print "\n1namapalette: \n", yaml_out($gui->{_nama_palette});
	my %setformat;
	map{ $setformat{$_} = $gui->{_palette}->{mw}{$_} if $gui->{_palette}->{mw}{$_}  } 
		keys %{$gui->{_palette}->{mw}};	
	#print "\nsetformat: \n", yaml_out(\%setformat);
	$gui->{mw}->setPalette( %setformat );
}
sub colorset {
	my ($widgetid, $field) = @_;
	sub { 
			my $widget = $gui->{$widgetid};
			#print "ancestor: $widgetid\n";
			my $new_color = colorchooser($field,$widget->cget("-$field"));
			if( defined $new_color ){
				
				# install color in palette listing
				$gui->{_palette}->{$widgetid}{$field} = $new_color;

				# set the color
				my @fields =  ($field => $new_color);
				push (@fields, 'background', $widget->cget('-background'))
					unless $field eq 'background';
				#print "fields: @fields\n";
				$widget->setPalette( @fields );
			}
 	};
}

sub namaset {
	my ($field) = @_;
	sub { 	
			#print "f: $field np: $gui->{_nama_palette}->{$field}\n";
			my $color = colorchooser($field,$gui->{_nama_palette}->{$field});
			if ($color){ 
				# install color in palette listing
				$gui->{_nama_palette}->{$field} = $color;

				# set those objects who are not
				# handled by refresh
	*rec = \$gui->{_nama_palette}->{RecBackground};
	*mon = \$gui->{_nama_palette}->{MonBackground};
	*off = \$gui->{_nama_palette}->{OffBackground};

				$gui->{clock}->configure(
					-background => $gui->{_nama_palette}->{ClockBackground},
					-foreground => $gui->{_nama_palette}->{ClockForeground},
				);
				$gui->{group_label}->configure(
					-background => $gui->{_nama_palette}->{GroupBackground},
					-foreground => $gui->{_nama_palette}->{GroupForeground},
				);
				refresh();
			}
	}

}

sub colorchooser { 
	logsub("&colorchooser");
	my ($field, $initialcolor) = @_;
	logpkg('debug', "field: $field, initial color: $initialcolor");
	my $new_color = $gui->{mw}->chooseColor(
							-title => $field,
							-initialcolor => $initialcolor,
							);
	#print "new color: $new_color\n";
	$new_color;
}
sub init_palettefields {
	@{$gui->{_palette_fields}} = qw[ 
		foreground
		background
		activeForeground
		activeBackground
		selectForeground
		selectBackground
		selectColor
		highlightColor
		highlightBackground
		disabledForeground
		insertBackground
		troughColor
	];

	@{$gui->{_nama_fields}} = qw [
		RecForeground
		RecBackground
		MonForeground
		MonBackground
		OffForeground
		OffBackground
		ClockForeground
		ClockBackground
		Capture
		Play
		Mixdown
		GroupForeground
		GroupBackground
		SendForeground
		SendBackground
		SourceForeground
		SourceBackground
		Mute
		MarkArmed
	];
}

sub save_palette {
 	serialize (
 		file => $file->gui_palette,
		format => 'json',
 		vars => [ qw( $gui->{_palette} $gui->{_nama_palette} ) ],
 		class => '::')
}

### end

