# gui handling
#
sub init_gui {

	$debug2 and print "&init_gui\n";

	init_palettefields(); # keys only


	### 	Tk root window 

	# Tk main window
 	$mw = MainWindow->new;  
	get_saved_colors();
	$set_event = $mw->Label();
	$mw->optionAdd('*font', 'Helvetica 12');
	$mw->optionAdd('*BorderWidth' => 1);
	$mw->title("Ecasound/Nama"); 
	$mw->deiconify;
	$parent{mw} = $mw;

	### Exit via Ctrl-C 

	$mw->bind('<Control-Key-c>' => \&abort);
 	$SIG{INT} = \&abort;
		

	### init effect window

	$ew = $mw->Toplevel;
	$ew->title("Effect Window");
	$ew->deiconify; 
#	$ew->withdraw;
	$parent{ew} = $ew;

	
	$canvas = $ew->Scrolled('Canvas')->pack;
	$canvas->configure(
		scrollregion =>[2,2,10000,2000],
		-width => 1200,
		-height => 700,	
		);
# 		scrollregion =>[2,2,10000,2000],
# 		-width => 1000,
# 		-height => 4000,	
	$effect_frame = $canvas->Frame;
	my $id = $canvas->createWindow(30,30, -window => $effect_frame,
											-anchor => 'nw');

	$project_label = $mw->Label->pack(-fill => 'both');

	$time_frame = $mw->Frame(
	#	-borderwidth => 20,
	#	-relief => 'groove',
	)->pack(
		-side => 'bottom', 
		-fill => 'both',
	);
	$mark_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	$fast_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	$transport_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	# $oid_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$clock_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	#$group_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$track_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
 	#$group_label = $group_frame->Menubutton(-text => "GROUP",
 #										-tearoff => 0,
 #										-width => 13)->pack(-side => 'left');
		
	$add_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$perl_eval_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$iam_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$load_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
#	my $blank = $mw->Label->pack(-side => 'left');



	$sn_label = $load_frame->Label(
		-text => "    Project name: "
	)->pack(-side => 'left');
	$sn_text = $load_frame->Entry(
		-textvariable => \$project,
		-width => 25
	)->pack(-side => 'left');
	$sn_load = $load_frame->Button->pack(-side => 'left');;
	$sn_new = $load_frame->Button->pack(-side => 'left');;
	$sn_quit = $load_frame->Button->pack(-side => 'left');
	$sn_save = $load_frame->Button->pack(-side => 'left');
	my $sn_save_text = $load_frame->Entry(
									-textvariable => \$save_id,
									-width => 15
									)->pack(-side => 'left');
	$sn_recall = $load_frame->Button->pack(-side => 'left');
	$sn_palette = $load_frame->Menubutton(-tearoff => 0)
		->pack( -side => 'left');
	$sn_namapalette = $load_frame->Menubutton(-tearoff => 0)
		->pack( -side => 'left');
	#$sn_effects_palette = $load_frame->Menubutton(-tearoff => 0)
	#	->pack( -side => 'left');
	# $sn_dump = $load_frame->Button->pack(-side => 'left');

	$build_track_label = $add_frame->Label(
		-text => "New track name: ")->pack(-side => 'left');
	$build_track_text = $add_frame->Entry(
		-textvariable => \$track_name, 
		-width => 12
	)->pack(-side => 'left');
# 	$build_track_mon_label = $add_frame->Label(
# 		-text => "Aux send: (channel/client):",
# 		-width => 18
# 	)->pack(-side => 'left');
# 	$build_track_mon_text = $add_frame->Entry(
# 		-textvariable => \$ch_m, 
# 		-width => 10
# 	)->pack(-side => 'left');
	$build_track_rec_label = $add_frame->Label(
		-text => "Input channel or client:"
	)->pack(-side => 'left');
	$build_track_rec_text = $add_frame->Entry(
		-textvariable => \$ch_r, 
		-width => 10
	)->pack(-side => 'left');
	$build_track_add_mono = $add_frame->Button->pack(-side => 'left');;
	$build_track_add_stereo  = $add_frame->Button->pack(-side => 'left');;

	$sn_load->configure(
		-text => 'Load',
		-command => sub{ load_project(
			name => remove_spaces($project),
			)});
	$sn_new->configure( 
		-text => 'Create',
		-command => sub{ load_project(
							name => remove_spaces($project),
							create => 1)});
	$sn_save->configure(
		-text => 'Save settings',
		-command => #sub { print "save_id: $save_id\n" });
		 sub {save_state($save_id) });
	$sn_recall->configure(
		-text => 'Recall settings',
 		-command => sub {load_project (name => $project_name, 
 										settings => $save_id)},
				);
	$sn_quit->configure(-text => "Quit",
		 -command => sub { 
				return if transport_running();
				save_state($save_id);
				print "Exiting... \n";		
				#$term->tkRunning(0);
				#$ew->destroy;
				#$mw->destroy;
				#::Text::command_process('quit');
				exit;
				 });
# 	$sn_dump->configure(
# 		-text => q(Dump state),
# 		-command => sub{ print &status_vars });
	$sn_palette->configure(
		-text => 'Palette',
		-relief => 'raised',
	);
	$sn_namapalette->configure(
		-text => 'Nama palette',
		-relief => 'raised',
	);
# 	$sn_effects_palette->configure(
# 		-text => 'Effects palette',
# 		-relief => 'raised',
# 	);

my @color_items = map { [ 'command' => $_, 
							-command  => colorset('mw', $_ ) ]
						} @palettefields;
$sn_palette->AddItems( @color_items);

@color_items = map { [ 'command' => $_, 
							-command  => namaset( $_ ) ]
						} @namafields;

# $sn_effects_palette->AddItems( @color_items);
# 
# @color_items = map { [ 'command' => $_, 
# 						-command  => namaset($_, $namapalette{$_})]
# 						} @namafields;
$sn_namapalette->AddItems( @color_items);

	$build_track_add_mono->configure( 
			-text => 'Add Mono Track',
			-command => sub { 
					return if $track_name =~ /^\s*$/;	
			add_track(remove_spaces($track_name)) }
	);
	$build_track_add_stereo->configure( 
			-text => 'Add Stereo Track',
			-command => sub { 
								return if $track_name =~ /^\s*$/;	
								add_track(remove_spaces($track_name));
								::Text::command_process('stereo');
	});

	my @labels = 
		qw(Track Name Version Status Source Send Volume Mute Unity Pan Center Effects);
	my @widgets;
	map{ push @widgets, $track_frame->Label(-text => $_)  } @labels;
	$widgets[0]->grid(@widgets[1..$#widgets]);


#  unified command processing by command_process 
# 	
 	$iam_label = $iam_frame->Label(
# 	-text => "         Command: "
 		)->pack(-side => 'left');;
# 	$iam_text = $iam_frame->Entry( 
# 		-textvariable => \$iam, -width => 45)
# 		->pack(-side => 'left');;
# 	$iam_execute = $iam_frame->Button(
# 			-text => 'Execute',
# 			-command => sub { ::Text::command_process( $iam ) }
# 			
# 		)->pack(-side => 'left');;
# 
# 			#join  " ",
# 			# grep{ $_ !~ add fxa afx } split /\s*;\s*/, $iam) 
		
}

sub transport_gui {
	@_ = discard_object(@_);
	$debug2 and print "&transport_gui\n";

	$transport_label = $transport_frame->Label(
		-text => 'TRANSPORT',
		-width => 12,
		)->pack(-side => 'left');;
	# disable Arm button
	# $transport_setup_and_connect  = $transport_frame->Button->pack(-side => 'left');;
	$transport_start = $transport_frame->Button->pack(-side => 'left');
	$transport_stop = $transport_frame->Button->pack(-side => 'left');
	#$transport_setup = $transport_frame->Button->pack(-side => 'left');;
	#$transport_connect = $transport_frame->Button->pack(-side => 'left');;
	#$transport_disconnect = $transport_frame->Button->pack(-side => 'left');;
	# $transport_new = $transport_frame->Button->pack(-side => 'left');;

	$transport_stop->configure(-text => "Stop",
	-command => sub { 
					stop_transport();
				}
		);
	$transport_start->configure(
		-text => "Start",
		-command => sub { 
		return if transport_running();
		my $color = engine_mode_color();
		project_label_configure(-background => $color);
		start_transport();
				});
# 	$transport_setup_and_connect->configure(
# 			-text => 'Arm',
# 			-command => sub {arm()}
# 						 );

# preview_button();
#mastering_button();

}
sub time_gui {
	@_ = discard_object(@_);
	$debug2 and print "&time_gui\n";

	my $time_label = $clock_frame->Label(
		-text => 'TIME', 
		-width => 12);
	#print "bg: $namapalette{ClockBackground}, fg:$namapalette{ClockForeground}\n";
	$clock = $clock_frame->Label(
		-text => '0:00', 
		-width => 8,
		-background => $namapalette{ClockBackground},
		-foreground => $namapalette{ClockForeground},
		);
	my $length_label = $clock_frame->Label(
		-text => 'LENGTH',
		-width => 10,
		);
	$setup_length = $clock_frame->Label(
	#	-width => 8,
		);

	for my $w ($time_label, $clock, $length_label, $setup_length) {
		$w->pack(-side => 'left');	
	}

	$mark_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	my $fast_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	# jump

	my $jump_label = $fast_frame->Label(-text => q(JUMP), -width => 12);
	my @pluses = (1, 5, 10, 30, 60);
	my @minuses = map{ - $_ } reverse @pluses;
	my @fw = map{ my $d = $_; $fast_frame->Button(
			-text => $d,
			-command => sub { jump($d) },
			)
		}  @pluses ;
	my @rew = map{ my $d = $_; $fast_frame->Button(
			-text => $d,
			-command => sub { jump($d) },
			)
		}  @minuses ;
	my $beg = $fast_frame->Button(
			-text => 'Beg',
			-command => \&to_start,
			);
	my $end = $fast_frame->Button(
			-text => 'End',
			-command => \&to_end,
			);

	$time_step = $fast_frame->Button( 
			-text => 'Sec',
			);
		for my $w($jump_label, @rew, $beg, $time_step, $end, @fw){
			$w->pack(-side => 'left')
		}

	$time_step->configure (-command => sub { &toggle_unit; &show_unit });

	# Marks
	
	my $mark_label = $mark_frame->Label(
		-text => q(MARK), 
		-width => 12,
		)->pack(-side => 'left');
		
	my $drop_mark = $mark_frame->Button(
		-text => 'Place',
		-command => \&drop_mark,
		)->pack(-side => 'left');	
		
	$mark_remove = $mark_frame->Button(
		-text => 'Remove',
		-command => \&arm_mark_toggle,
	)->pack(-side => 'left');	

}

#  the following is based on previous code for multiple buttons
#  needs cleanup

sub preview_button { 
	$debug2 and print "&preview\n";
	@_ = discard_object(@_);
	#my $outputs = $oid_frame->Label(-text => 'OUTPUTS', -width => 12);
	my $rule = $rec_file;
	my $status = $rule->status;
	my $oid_button = $transport_frame->Button( );
	$oid_button->configure(
		-text => 'Preview',
		-command => sub { 
			$rule->set(status => ! $rule->status);
			$oid_button->configure( 
		-background => 
				$rule->status ? $old_bg : $namapalette{Preview} ,
		#-activebackground => 
		#		$rule->status ? $old_bg : $namapalette{ActivePreview} ,
		-text => 
				$rule->status ? 'Preview' : 'PREVIEW MODE'
					
					);

			if ($rule->status) { # rec_file enabled
				arm()
			} else { 
				preview();
			}

			});
		push @widget_o, $oid_button;
		
	map { $_ -> pack(-side => 'left') } (@widget_o);
	
}
sub paint_button {
	@_ = discard_object(@_);
	my ($button, $color) = @_;
	$button->configure(-background => $color,
						-activebackground => $color);
}

sub engine_mode_color {
		if ( user_rec_tracks()  ){ 
				$rec  					# live recording
		} elsif ( &really_recording ){ 
				$namapalette{Mixdown}	# mixdown only 
		} elsif ( user_mon_tracks() ){  
				$namapalette{Play}; 	# just playback
		} else { $old_bg } 
	}

sub flash_ready {

	my $color = engine_mode_color();
	$debug and print "flash color: $color\n";
	length_display(-background => $color);
	project_label_configure(-background => $color) unless $preview;
# 	$event_id{tk_flash_ready}->cancel() if defined $event_id{tk_flash_ready};
# 	$event_id{tk_flash_ready} = $set_event->after(3000, 
# 		sub{ length_display(-background => $off);
# 			 project_label_configure(-background => $off) 
# }
# );
}
sub group_gui {  
	@_ = discard_object(@_);
	my $group = $main; 
	my $dummy = $track_frame->Label(-text => ' '); 
	$group_label = 	$track_frame->Label(
			-text => "G R O U P",
			-foreground => $namapalette{GroupForeground},
			-background => $namapalette{GroupBackground},

 );
	$group_version = $track_frame->Menubutton( 
		-text => q( ), 
		-tearoff => 0,
		-foreground => $namapalette{GroupForeground},
		-background => $namapalette{GroupBackground},
);
	$group_rw = $track_frame->Menubutton( 
		-text    => $group->rw,
	 	-tearoff => 0,
		-foreground => $namapalette{GroupForeground},
		-background => $namapalette{GroupBackground},
);


		
		$group_rw->AddItems([
			'command' => 'REC',
			-background => $old_bg,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
				$group->set(rw => 'REC');
				$group_rw->configure(-text => 'REC');
				refresh();
				reconfigure_engine()
				}
			],[
			'command' => 'MON',
			-background => $old_bg,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
				$group->set(rw => 'MON');
				$group_rw->configure(-text => 'MON');
				refresh();
				reconfigure_engine()
				}
			],[
			'command' => 'OFF',
			-background => $old_bg,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
				$group->set(rw => 'OFF');
				$group_rw->configure(-text => 'OFF');
				refresh();
				reconfigure_engine()
				}
			]);
			$dummy->grid($group_label, $group_version, $group_rw);
			$ui->global_version_buttons;

}
sub global_version_buttons {
	local $debug = 0;
	my $version = $group_version;
	$version and map { $_->destroy } $version->children;
		
	$debug and print "making global version buttons range:",
		join ' ',1..$main->last, " \n";

			$version->radiobutton( 

				-label => (''),
				-value => 0,
				-command => sub { 
					$main->set(version => 0); 
					$version->configure(-text => " ");
					reconfigure_engine();
					refresh();
					}
			);

 	for my $v (1..$main->last) { 

	# the highest version number of all tracks in the
	# $main group
	
	my @user_track_indices = grep { $_ > 2 } map {$_->n} ::Track::all;
	
		next unless grep{  grep{ $v == $_ } @{ $ti{$_}->versions } }
			@user_track_indices;
		

			$version->radiobutton( 

				-label => ($v ? $v : ''),
				-value => $v,
				-command => sub { 
					$main->set(version => $v); 
					$version->configure(-text => $v);
					reconfigure_engine();
					refresh();
					}

			);
 	}
}
sub track_gui { 
	$debug2 and print "&track_gui\n";
	@_ = discard_object(@_);
	my $n = shift;
	return if $ti{$n}->hide;
	
	$debug and print "found index: $n\n";
	my @rw_items = @_ ? @_ : (
			[ 'command' => "REC",
				-foreground => 'red',
				-command  => sub { 
					return if eval_iam("engine-status") eq 'running';
					$ti{$n}->set(rw => "REC");
					
					refresh_track($n);
					refresh_group();
					reconfigure_engine();
			}],
			[ 'command' => "MON",
				-command  => sub { 
					return if eval_iam("engine-status") eq 'running';
					$ti{$n}->set(rw => "MON");
					refresh_track($n);
					refresh_group();
					reconfigure_engine();
			}],
			[ 'command' => "OFF", 
				-command  => sub { 
					return if eval_iam("engine-status") eq 'running';
					$ti{$n}->set(rw => "OFF");
					refresh_track($n);
					refresh_group();
					reconfigure_engine();
			}],
		);
	my ($number, $name, $version, $rw, $ch_r, $ch_m, $vol, $mute, $solo, $unity, $pan, $center);
	$number = $track_frame->Label(-text => $n,
									-justify => 'left');
	my $stub = " ";
	$stub .= $ti{$n}->active;
	$name = $track_frame->Label(
			-text => $ti{$n}->name,
			-justify => 'left');
	$version = $track_frame->Menubutton( 
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
			$ti{$n}->set( active => $v );
			return if $ti{$n}->rec_status eq "REC";
			$version->configure( -text=> $ti{$n}->current_version );
			reconfigure_engine();
			}
					);
	}

	$ch_r = $track_frame->Menubutton(
					# -relief => 'groove',
					-tearoff => 0,
				);
	my @range;
	push @range, "";
	push @range, 1..$tk_input_channels if $n > 2;
	
	for my $v (@range) {
		$ch_r->radiobutton(
			-label => $v,
			-value => $v,
			-command => sub { 
				return if eval_iam("engine-status") eq 'running';
			#	$ti{$n}->set(rw => 'REC');
				$ti{$n}->source($v);
				refresh_track($n) }
			)
	}
	$ch_m = $track_frame->Menubutton(
					-tearoff => 0,
					# -relief => 'groove',
				);
				for my $v ("off",3..10) {
					$ch_m->radiobutton(
						-label => $v,
						-value => $v,
						-command => sub { 
							return if eval_iam("engine-status") eq 'running';
			#				$ti{$n}->set(rw  => "MON");
							$ti{$n}->send($v);
							refresh_track($n);
							reconfigure_engine();
 						}
				 		)
				}
	$rw = $track_frame->Menubutton(
		-text => $ti{$n}->rw,
		-tearoff => 0,
		# -relief => 'groove',
	);
	map{$rw->AddItems($_)} @rw_items; 

 
	my $p_num = 0; # needed when using parameter controllers
	# Volume
	
	if ( need_vol_pan($ti{$n}->name, "vol") ){

		my $vol_id = $ti{$n}->vol;

		local $debug = 0;


		$debug and print "vol cop_id: $vol_id\n";
		my %p = ( 	parent => \$track_frame,
				chain  => $n,
				type => 'ea',
				cop_id => $vol_id,
				p_num		=> $p_num,
				length => 300, 
				);


		 $debug and do {my %q = %p; delete $q{parent}; print
		 "=============\n%p\n",yaml_out(\%q)};

		$vol = make_scale ( \%p );
		# Mute

		$mute = $track_frame->Button(
			-command => sub { 
				if ($copp{$vol_id}->[0]) {  # non-zero volume
					$ti{$n}->set(old_vol_level => $copp{$vol_id}->[0]);
					effect_update_copp_set( $vol_id, 0, 0);
					$mute->configure(-background => $namapalette{Mute});
				}
				else {
					effect_update_copp_set($vol_id, 0,$ti{$n}->old_vol_level);
					$ti{$n}->set(old_vol_level => 0);
					$mute->configure(-background => $off);
				}
			}	
		  );

		# Unity

		$unity = $track_frame->Button(
				-command => sub { 
					effect_update_copp_set($vol_id, 0, 100);
				}
		  );
	} else {

		$vol = $track_frame->Label;
		$mute = $track_frame->Label;
		$unity = $track_frame->Label;

	}

	if ( need_vol_pan($ti{$n}->name, "pan") ){
	  
		# Pan
		
		my $pan_id = $ti{$n}->pan;
		
		$debug and print "pan cop_id: $pan_id\n";
		$p_num = 0;           # first parameter
		my %q = ( 	parent => \$track_frame,
				chain  => $n,
				type => 'epp',
				cop_id => $pan_id,
				p_num		=> $p_num,
				);
		# $debug and do { my %q = %p; delete $q{parent}; print "x=============\n%p\n",yaml_out(\%q) };
		$pan = make_scale ( \%q );

		# Center

		$center = $track_frame->Button(
			-command => sub { 
				effect_update_copp_set($pan_id, 0, 50);
			}
		  );
	} else { 

		$pan = $track_frame->Label;
		$center = $track_frame->Label;
	}
	
	my $effects = $effect_frame->Frame->pack(-fill => 'both');;

	# effects, held by track_widget->n->effects is the frame for
	# all effects of the track

	@{ $track_widget{$n} }{qw(name version rw ch_r ch_m mute effects)} 
		= ($name,  $version, $rw, $ch_r, $ch_m, $mute, \$effects);#a ref to the object
	#$debug and print "=============\n\%track_widget\n",yaml_out(\%track_widget);
	my $independent_effects_frame 
		= ${ $track_widget{$n}->{effects} }->Frame->pack(-fill => 'x');


	my $controllers_frame 
		= ${ $track_widget{$n}->{effects} }->Frame->pack(-fill => 'x');
	
	# parents are the independent effects
	# children are controllers for various paramters

	$track_widget{$n}->{parents} = $independent_effects_frame;

	$track_widget{$n}->{children} = $controllers_frame;
	
	$independent_effects_frame
		->Label(-text => uc $ti{$n}->name )->pack(-side => 'left');

	#$debug and print( "Number: $n\n"),MainLoop if $n == 2;
	my @tags = qw( EF P1 P2 L1 L2 L3 L4 );
	my @starts =   ( $e_bound{cop}{a}, 
					 $e_bound{preset}{a}, 
					 $e_bound{preset}{b}, 
					 $e_bound{ladspa}{a}, 
					 $e_bound{ladspa}{b}, 
					 $e_bound{ladspa}{c}, 
					 $e_bound{ladspa}{d}, 
					);
	my @ends   =   ( $e_bound{cop}{z}, 
					 $e_bound{preset}{b}, 
					 $e_bound{preset}{z}, 
					 $e_bound{ladspa}{b}-1, 
					 $e_bound{ladspa}{c}-1, 
					 $e_bound{ladspa}{d}-1, 
					 $e_bound{ladspa}{z}, 
					);
	my @add_effect;

	map{push @add_effect, effect_button($n, shift @tags, shift @starts, shift @ends)} 1..@tags;
	
	$number->grid($name, $version, $rw, $ch_r, $ch_m, $vol, $mute, $unity, $pan, $center, @add_effect);

	$track_widget_remove{$n} = [
		$number, $name, $version, $rw, $ch_r, $ch_m, $vol,
			$mute, $unity, $pan, $center, @add_effect, $effects ];

	refresh_track($n);

}

sub remove_track_gui {
	load_project( name => $project_name );
# 	@_ = discard_object( @_ );
# 	my $n = shift;
# 	my $m;
# 	map {print ++$m, ref $_, $/; (ref $_) =~ /Tk/ and $_->destroy  } @{ $track_widget_remove{$n} };
}

sub paint_mute_buttons {
	map{ $track_widget{$_}{mute}->configure(
			-background 		=> $namapalette{Mute},

			)} grep { $ti{$_}->old_vol_level}# muted tracks
				map { $_->n } ::Track::all;  # track numbers
}

sub create_master_and_mix_tracks { 
	$debug2 and print "&create_master_and_mix_tracks\n";


	my @rw_items = (
			[ 'command' => "MON",
				-command  => sub { 
						return if eval_iam("engine-status") eq 'running';
						$tn{Master}->set(rw => "MON");
						refresh_track($tn{Master}->n);
			}],
			[ 'command' => "OFF", 
				-command  => sub { 
						return if eval_iam("engine-status") eq 'running';
						$tn{Master}->set(rw => "OFF");
						refresh_track($tn{Master}->n);
			}],
		);

	track_gui( $tn{Master}->n, @rw_items );

	track_gui( $tn{Mixdown}->n); 

	group_gui('Main');
}


sub update_version_button {
	@_ = discard_object(@_);
	my ($n, $v) = @_;
	carp ("no version provided \n") if ! $v;
	my $w = $track_widget{$n}->{version};
					$w->radiobutton(
						-label => $v,
						-value => $v,
						-command => 
		sub { $track_widget{$n}->{version}->configure(-text=>$v) 
				unless $ti{$n}->rec_status eq "REC" }
					);
}

sub add_effect_gui {
		$debug2 and print "&add_effect_gui\n";
		@_ = discard_object(@_);
		my %p 			= %{shift()};
		my $n 			= $p{chain};
		my $code 			= $p{type};
		my $parent_id = $p{parent_id};  
		my $id		= $p{cop_id};   # initiates restore
		my $parameter		= $p{parameter}; 
		my $i = $effect_i{$code};

		$debug and print yaml_out(\%p);

		$debug and print "cop_id: $id, parent_id: $parent_id\n";
		# $id is determined by cop_add, which will return the
		# existing cop_id if supplied

		# check display format, may be 'scale' 'field' or 'hidden'
		
		my $display_type = $cops{$id}->{display}; # individual setting
		defined $display_type or $display_type = $effects[$i]->{display}; # template
		$debug and print "display type: $display_type\n";

		return if $display_type eq q(hidden);

		my $frame ;
		if ( ! $parent_id ){ # independent effect
			$frame = $track_widget{$n}->{parents}->Frame->pack(
				-side => 'left', 
				-anchor => 'nw',)
		} else {                 # controller
			$frame = $track_widget{$n}->{children}->Frame->pack(
				-side => 'top', 
				-anchor => 'nw')
		}

		$effects_widget{$id} = $frame; 
		# we need a separate frame so title can be long

		# here add menu items for Add Controller, and Remove

		my $parentage = $effects[ $effect_i{ $cops{$parent_id}->{type}} ]
			->{name};
		$parentage and $parentage .=  " - ";
		$debug and print "parentage: $parentage\n";
		my $eff = $frame->Menubutton(
			-text => $parentage. $effects[$i]->{name}, -tearoff => 0,);

		$eff->AddItems([
			'command' => "Remove",
			-command => sub { remove_effect($id) }
		]);
		$eff->grid();
		my @labels;
		my @sliders;

		# make widgets

		for my $p (0..$effects[$i]->{count} - 1 ) {
		my @items;
		#$debug and print "p_first: $p_first, p_last: $p_last\n";
		for my $j ($e_bound{ctrl}{a}..$e_bound{ctrl}{z}) {   
			push @items, 				
				[ 'command' => $effects[$j]->{name},
					-command => sub { add_effect ({
							parent_id => $id,
							chain => $n,
							parameter  => $p,
							type => $effects[$j]->{code} } )  }
				];

		}
		push @labels, $frame->Menubutton(
				-text => $effects[$i]->{params}->[$p]->{name},
				-menuitems => [@items],
				-tearoff => 0,
		);
			$debug and print "parameter name: ",
				$effects[$i]->{params}->[$p]->{name},"\n";
			my $v =  # for argument vector 
			{	parent => \$frame,
				cop_id => $id, 
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
	@_ = discard_object(@_);
	$project_label->configure( @_ ) }

sub length_display{ 
	@_ = discard_object(@_);
	$setup_length->configure(@_)};

sub clock_config { 
	@_ = discard_object(@_);
	$clock->configure( @_ )}

sub manifest { $ew->deiconify() }

sub destroy_widgets {

	map{ $_->destroy } map{ $_->children } $effect_frame;
	#my @children = $group_frame->children;
	#map{ $_->destroy  } @children[1..$#children];
	my @children = $track_frame->children;
	# leave field labels (first row)
	map{ $_->destroy  } @children[11..$#children]; # fragile
	%mark_widget and map{ $_->destroy } values %mark_widget;
}
sub remove_effect_gui { 
	@_ = discard_object(@_);
	$debug2 and print "&remove_effect_gui\n";
	my $id = shift;
	my $n = $cops{$id}->{chain};
	$debug and print "id: $id, chain: $n\n";

	$debug and print "i have widgets for these ids: ", join " ",keys %effects_widget, "\n";
	$debug and print "preparing to destroy: $id\n";
	return unless defined $effects_widget{$id};
	$effects_widget{$id}->destroy();
	delete $effects_widget{$id}; 

}

sub effect_button {
	local $debug = 0;	
	$debug2 and print "&effect_button\n";
	my ($n, $label, $start, $end) = @_;
	$debug and print "chain $n label $label start $start end $end\n";
	my @items;
	my $widget;
	my @indices = ($start..$end);
	if ($start >= $e_bound{ladspa}{a} and $start <= $e_bound{ladspa}{z}){
		@indices = ();
		@indices = @ladspa_sorted[$start..$end];
		$debug and print "length sorted indices list: ".scalar @indices. "\n";
	$debug and print "Indices: @indices\n";
	}
		
		for my $j (@indices) { 
		push @items, 				
			[ 'command' => "$effects[$j]->{count} $effects[$j]->{name}" ,
				-command  => sub { 
					 add_effect( {chain => $n, type => $effects[$j]->{code} } ); 
					$ew->deiconify; # display effects window
					} 
			];
	}
	$widget = $track_frame->Menubutton(
		-text => $label,
		-tearoff =>0,
		# -relief => 'raised',
		-menuitems => [@items],
	);
	$widget;
}

sub make_scale {
	
	$debug2 and print "&make_scale\n";
	my $ref = shift;
	my %p = %{$ref};
# 	%p contains following:
# 	cop_id   => operator id, to access dynamic effect params in %copp
# 	parent => parent widget, i.e. the frame
# 	p_num      => parameter number, starting at 0
# 	length       => length widget # optional 
	my $id = $p{cop_id};
	my $n = $cops{$id}->{chain};
	my $code = $cops{$id}->{type};
	my $p  = $p{p_num};
	my $i  = $effect_i{$code};

	$debug and print "id: $id code: $code\n";
	

	# check display format, may be text-field or hidden,

	$debug and  print "i: $i code: $effects[$i]->{code} display: $effects[$i]->{display}\n";
	my $display_type = $cops{$id}->{display};
	defined $display_type or $display_type = $effects[$i]->{display};
	$debug and print "display type: $display_type\n";
	return if $display_type eq q(hidden);


	$debug and print "to: ", $effects[$i]->{params}->[$p]->{end}, "\n";
	$debug and print "p: $p code: $code\n";
	$debug and print "is_log_scale: ".is_log_scale($i,$p), "\n";

	# set display type to individually specified value if it exists
	# otherwise to the default for the controller class


	
	if 	($display_type eq q(scale) ) { 

		# return scale type controller widgets
		my $frame = ${ $p{parent} }->Frame;
			

		#return ${ $p{parent} }->Scale(
		
		my $log_display;
		
		my $controller = $frame->Scale(
			-variable => \$copp{$id}->[$p],
			-orient => 'horizontal',
			-from   =>  $effects[$i]->{params}->[$p]->{begin},
			-to     =>  $effects[$i]->{params}->[$p]->{end},
			-resolution => resolution($i, $p),
		  -width => 12,
		  -length => $p{length} ? $p{length} : 100,
		  -command => sub { effect_update($id, $p, $copp{$id}->[$p]) }
		  );

		# auxiliary field for logarithmic display
		if ( is_log_scale($i, $p)  )
		#	or $code eq 'ea') 
			{
			my $log_display = $frame->Label(
				-text => exp $effects[$i]->{params}->[$p]->{default},
				-width => 5,
				);
			$controller->configure(
				-variable => \$copp_exp{$id}->[$p],
		  		-command => sub { 
					$copp{$id}->[$p] = exp $copp_exp{$id}->[$p];
					effect_update($id, $p, $copp{$id}->[$p]);
					$log_display->configure(
						-text => 
						$effects[$i]->{params}->[$p]->{name} =~ /hz|frequency/i
							? int $copp{$id}->[$p]
							: dn($copp{$id}->[$p], 1)
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
			-textvariable =>\$copp{$id}->[$p],
			-width => 6,
	#		-command => sub { effect_update($id, $p, $copp{$id}->[$p]) },
			# doesn't work with Entry widget
			);	

	}
	else { croak "missing or unexpected display type: $display_type" }

}

sub is_log_scale {
	my ($i, $p) = @_;
	$effects[$i]->{params}->[$p]->{hint} =~ /logarithm/ 
}
sub resolution {
	my ($i, $p) = @_;
	my $res = $effects[$i]->{params}->[$p]->{resolution};
	return $res if $res;
	my $end = $effects[$i]->{params}->[$p]->{end};
	my $beg = $effects[$i]->{params}->[$p]->{begin};
	return 1 if abs($end - $beg) > 30;
	return abs($end - $beg)/100
}

sub arm_mark_toggle { 
	if ($markers_armed) {
		$markers_armed = 0;
		$mark_remove->configure( -background => $off);
	}
	else{
		$markers_armed = 1;
		$mark_remove->configure( -background => $namapalette{MarkArmed});
	}
}
sub marker {
	@_ = discard_object( @_); # UI
	my $mark = shift; # Mark
	#print "mark is ", ref $mark, $/;
	my $pos = $mark->time;
	#print $pos, " ", int $pos, $/;
		$mark_widget{$pos} = $mark_frame->Button( 
			-text => (join " ",  colonize( int $pos ), $mark->name),
			-background => $off,
			-command => sub { mark($mark) },
		)->pack(-side => 'left');
}

sub restore_time_marks {
	@_ = discard_object( @_);
# 	map {$_->dumpp} ::Mark::all(); 
#	::Mark::all() and 
	map{ $ui->marker($_) } ::Mark::all() ; 
	$time_step->configure( -text => $unit == 1 ? q(Sec) : q(Min) )
}
sub destroy_marker {
	@_ = discard_object( @_);
	my $pos = shift;
	$mark_widget{$pos}->destroy; 
}

sub wraparound {
	@_ = discard_object @_;
	my ($diff, $start) = @_;
	cancel_wraparound();
	$event_id{tk_wraparound} = $set_event->after( 
		int( $diff*1000 ), sub{ set_position( $start) } )
}
sub cancel_wraparound { tk_event_cancel("tk_wraparound") }

sub start_heartbeat {
	#print ref $set_event; 
	$event_id{tk_heartbeat} = $set_event->repeat( 
		3000, \&heartbeat);
		# 3000, *heartbeat{SUB}); # equivalent to above
}

sub poll_jack {
	package ::; # no necessary we are already in base class
	$event_id{tk_poll_jack} = $set_event->repeat( 
		5000, \&jack_update
	);

}
sub stop_heartbeat { tk_event_cancel( qw(tk_heartbeat tk_wraparound)) }

sub tk_event_cancel {
	@_ = discard_object @_;
	map{ (ref $event_id{$_}) =~ /Tk/ and $set_event->afterCancel($event_id{$_}) 
	} @_;
}
sub get_saved_colors {
	$debug2 and print "&get_saved_colors\n";

	# aliases
	
	*old_bg = \$palette{mw}{background};
	*old_abg = \$palette{mw}{activeBackground};
	$old_bg = '#d915cc1bc3cf' unless $old_bg;
	#print "pb: $palette{mw}{background}\n";


	my $pal = join_path($project_root, $palette_file);
	-f $pal or $pal = $default_palette_yml;
	assign_var( $pal, qw[%palette %namapalette]);
	
	*rec = \$namapalette{RecBackground};
	*mon = \$namapalette{MonBackground};
	*off = \$namapalette{OffBackground};

	$old_abg = $palette{mw}{activeBackground};
	$old_abg = $project_label->cget('-activebackground') unless $old_abg;
	#print "1palette: \n", yaml_out( \%palette );
	#print "\n1namapalette: \n", yaml_out(\%namapalette);
	my %setformat;
	map{ $setformat{$_} = $palette{mw}{$_} if $palette{mw}{$_}  } 
		keys %{$palette{mw}};	
	#print "\nsetformat: \n", yaml_out(\%setformat);
	$mw->setPalette( %setformat );
}
sub colorset {
	my ($widgetid, $field) = @_;
	sub { 
			my $widget = eval "\$$widgetid";
			#print "ancestor: $widgetid\n";
			my $new_color = colorchooser($field,$widget->cget("-$field"));
			if( defined $new_color ){
				
				# install color in palette listing
				$palette{$widgetid}{$field} = $new_color;

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
			#print "f: $field np: $namapalette{$field}\n";
			my $color = colorchooser($field,$namapalette{$field});
			if ($color){ 
				# install color in palette listing
				$namapalette{$field} = $color;

				# set those objects who are not
				# handled by refresh
	*rec = \$namapalette{RecBackground};
	*mon = \$namapalette{MonBackground};
	*off = \$namapalette{OffBackground};

				$clock->configure(
					-background => $namapalette{ClockBackground},
					-foreground => $namapalette{ClockForeground},
				);
				$group_label->configure(
					-background => $namapalette{GroupBackground},
					-foreground => $namapalette{GroupForeground},
				);
				refresh();
			}
	}

}

sub colorchooser { 
	#print "colorchooser\n";
	#my $debug = 1;
	my ($field, $initialcolor) = @_;
	$debug and print "field: $field, initial color: $initialcolor\n";
	my $new_color = $mw->chooseColor(
							-title => $field,
							-initialcolor => $initialcolor,
							);
	#print "new color: $new_color\n";
	$new_color;
}
sub init_palettefields {
	@palettefields = qw[ 
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

	@namafields = qw [
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
 		file => join_path(project_root(), $palette_file),
		format => 'yaml',
 		vars => [ qw( %palette %namapalette ) ],
 		class => '::')
}

sub abort {
	remove_small_wavs();
	kill 15, ::ecasound_pid();
	$term->rl_deprep_terminal();
	Tk::exit();
}


### end
