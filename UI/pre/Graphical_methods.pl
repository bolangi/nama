
# croak "odd number of arguments ",join "\n--\n" ,@_ if @_ % 2;
sub new { my $class = shift; return bless {@_}, $class }
sub session_label_configure{ session_label_configure(@_)}
sub length_display{ $setup_length->configure(-text => colonize $length) };
sub clock_display { $clock->configure(-text => colonize( 0) )}
sub manifest { $ew->deiconify() }


sub loop {
	init_gui(); 
	transport_gui();
	oid_gui();
	time_gui();
	session_init(), load_session({create => $opts{c}}) if $session_name;
	MainLoop;
}


## gui handling
#
sub destroy_widgets {

	map{ $_->destroy } map{ $_->children } $effect_frame;
	my @children = $take_frame->children;
	map{ $_->destroy  } @children[1..$#children];
	@children = $track_frame->children;
	map{ $_->destroy  } @children[11..$#children]; # fragile
	$state_t{active} = 1; 
}

sub init_gui {

	$debug2 and print "&init_gui\n";

### 	Tk root window layout

	$mw = MainWindow->new; 
	$mw->title("Tk Ecmd"); 
	$mw->deiconify;

	### init effect window

	$ew = $mw->Toplevel;
	$ew->title("Effect Window");
	$ew->withdraw;

	$canvas = $ew->Scrolled('Canvas')->pack;
	$canvas->configure(
		scrollregion =>[2,2,10000,2000],
		-width => 900,
		-height => 600,	
		);
# 		scrollregion =>[2,2,10000,2000],
# 		-width => 1000,
# 		-height => 4000,	
	$effect_frame = $canvas->Frame;
	my $id = $canvas->createWindow(30,30, -window => $effect_frame,
											-anchor => 'nw');

	$session_label = $mw->Label->pack(-fill => 'both');
	$old_bg = $session_label->cget('-background');
	$time_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$transport_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$oid_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$clock_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$track_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$take_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$take_label = $take_frame->Menubutton(-text => "Group",-tearoff => 0,)->pack(-side => 'left');
		
	$add_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$perl_eval_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$iam_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
	$load_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');
#	my $blank = $mw->Label->pack(-side => 'left');



	$sn_label = $load_frame->Label(-text => "Enter session name:")->pack(-side => 'left');
	$sn_text = $load_frame->Entry(-textvariable => \$session, -width => 45)->pack(-side => 'left');
	$sn_load = $load_frame->Button->pack(-side => 'left');;
#	$sn_load_nostate = $load_frame->Button->pack(-side => 'left');;
	$sn_new = $load_frame->Button->pack(-side => 'left');;
	$sn_quit = $load_frame->Button->pack(-side => 'left');

	$build_track_label = $add_frame->Label(-text => "Track")->pack(-side => 'left');
	$build_track_text = $add_frame->Entry(-textvariable => \$track_name, -width => 12)->pack(-side => 'left');
	$build_track_rec_label = $add_frame->Label(-text => "REC")->pack(-side => 'left');
	$build_track_rec_text = $add_frame->Entry(-textvariable => \$ch_r, -width => 2)->pack(-side => 'left');
	$build_track_mon_label = $add_frame->Label(-text => "MON")->pack(-side => 'left');
	$build_track_mon_text = $add_frame->Entry(-textvariable => \$ch_m, -width => 2)->pack(-side => 'left');
	$build_track_add = $add_frame->Button->pack(-side => 'left');;

	$sn_load->configure(
		-text => 'Load',
		-command => \&load_session,
		);
	$sn_new->configure( 
		-text => 'New',
		-command => sub { load_session({create => 1}) },
		);
	$sn_quit->configure(-text => "Quit",
		 -command => sub { 
				return if transport_running();
				save_state(join_path(&session_dir,$state_store_file)) 
					if session_dir();
		$debug2 and print "\%state_c\n================\n", &yaml_out(\%state_c);
		$debug2 and print "\%state_t\n================\n", &yaml_out(\%state_t);
		$debug2 and print "\%copp\n================\n", &yaml_out(\%copp);
		$debug2 and print "\%cops\n================\n", &yaml_out(\%cops);
		$debug2 and print "\%pre_output\n================\n", &yaml_out(\%pre_output); 
		$debug2 and print "\%post_input\n================\n", &yaml_out(\%post_input);
		exit;
				 }
				);


	$build_track_add->configure( 
			-text => 'Add',
			-command => sub { add_track($track_name) }
	);

=comment TAKE
	$build_new_take->configure( 
			-text => 'New Group',
			-command =>
			\new_take, # used for mixdown

			
			);
=cut

			

	my @labels = 
		qw(Track Version Status Rec Mon Volume Cut Unity Pan Center Effects);
	my @widgets;
	map{ push @widgets, $track_frame->Label(-text => $_)  } @labels;
	$widgets[0]->grid(@widgets[1..$#widgets]);

	
	$iam_label = $iam_frame->Label(-text => "IAM Command")
		->pack(-side => 'left');;
	$iam_text = $iam_frame->Entry( 
		-textvariable => \$iam, -width => 65)
		->pack(-side => 'left');;
	$iam_execute = $iam_frame->Button(
			-text => 'Execute',
			-command => sub { print eval_iam($iam), "\n" }
		)->pack(-side => 'left');;
	my $perl_eval;
	my $perl_eval_label = $perl_eval_frame->Label(
		-text => "Perl Command")
		->pack(-side => 'left');;
	my $perl_eval_text = $perl_eval_frame->Entry(
		-textvariable => \$perl_eval, -width => 65)
		->pack(-side => 'left');;
	my $perl_eval_execute = $perl_eval_frame->Button(
			-text => 'Execute',
			-command => sub { eval $perl_eval  }
		)->pack(-side => 'left');;
		
}
sub transport_gui {

	$transport_label = $transport_frame->Label(
		-text => 'TRANSPORT',
		-width => 12,
		)->pack(-side => 'left');;
	$transport_setup_and_connect  = $transport_frame->Button->pack(-side => 'left');;
	$transport_start = $transport_frame->Button->pack(-side => 'left');
	$transport_stop = $transport_frame->Button->pack(-side => 'left');
	$transport_setup = $transport_frame->Button->pack(-side => 'left');;
	$transport_connect = $transport_frame->Button->pack(-side => 'left');;
	$transport_disconnect = $transport_frame->Button->pack(-side => 'left');;
	$transport_new = $transport_frame->Button->pack(-side => 'left');;

	$transport_stop->configure(-text => "Stop",
	-command => sub { 
					stop_transport();
				}
		);
	$transport_start->configure(
		-text => "Start!",
		-command => sub { 
		return if transport_running();
		if ( really_recording ) {
			session_label_configure(-background => 'lightpink') 
		}
		else {
			session_label_configure(-background => 'lightgreen') 
		}
		start_transport();
				});
	$transport_setup_and_connect->configure(
			-text => 'Generate and connect',
			-command => sub {&setup_transport; &connect_transport}
						 );
	$transport_setup->configure(
			-text => 'Generate chain setup',
			-command => \&setup_transport,
						 );
	$transport_connect->configure(
			-text => 'Connect chain setup',
			-command => \&connect_transport,
						 );
	$transport_disconnect->configure(
			-text => 'Disconnect setup',
			-command => \&disconnect_transport,
						);
	$transport_new->configure(
			-text => 'New Engine',
			-command => \&new_engine,
						 );
}
sub time_gui {
	$debug2 and print "&time_gui\n";

	my $time_label = $clock_frame->Label(
		-text => 'TIME', 
		-width => 12);
	$clock = $clock_frame->Label(
		-text => '0:00', 
		-width => 8,
		-background => 'orange',
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

	my $mark_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	my $fast_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	# jump

	my $jump_label = $fast_frame->Label(-text => q(JUMP), -width => 12);
	my $mark_label = $mark_frame->Label(-text => q(MARK), -width => 12);
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
			-command => \to_start,
			);
	my $end = $fast_frame->Button(
			-text => 'End',
			-command => \to_end,
			);

	$time_step = $fast_frame->Button( 
			-text => 'Sec',
			);
		for my $w($jump_label, @rew, $beg, $time_step, $end, @fw){
			$w->pack(-side => 'left')
		}

	$time_step->configure (-command => \toggle_unit);

	# Marks
	
	my @label_and_arm;
	push @label_and_arm, $mark_label;	
	push @label_and_arm, $mark_frame->Button(
		-text => 'Set',
		-command => sub { arm_mark },
	);
	my $marks = 18; # number of marker buttons
	my @m = (1..$marks);
	my $label = qw(A);
	map { push @time_marks, $mark_frame->Button( 
		-text => $_,
		-command => sub { mark(eval $_)},
		-background => $marks[$_] ? $old_bg : 'lightblue',
		) } @m;
	# map { $time_marks[$_]->configure( -command => sub { # mark($_)} ) } @m[1..$#m];
	for my $m (@m) {
		$time_marks[$m]->configure( -command => sub { mark($m)} )
			unless ! defined $time_marks[$m];
		
		;
	}
	#$time_marks[3]->configure( -background => 'orange' );
#	 map { $time_marks[$_]->configure(-background => 'orange')} @m;
 	for my $w (@label_and_arm, @time_marks){
 		$w->pack(-side => 'left')
 	}
#	$time_marks[0]->grid(@time_marks[@m]);

}
sub oid_gui {
	$debug2 and print "&oid_gui\n";
	my $outputs = $oid_frame->Label(-text => 'OUTPUTS', -width => 12);
	my @oid_name;
	for my $oid ( @oids ){
		# print "gui oid name: $oid->{name} status: $oid_status{$oid->{name}}\n";
		next if $oid->{name} =~ m/setup/;
		push @oid_name, $oid->{name};
		
		my $oid_button = $oid_frame->Button( 
			-text => ucfirst $oid->{name},
			-background => 
				$oid_status{$oid->{name}} ?  'AntiqueWhite' : $old_bg,
			-activebackground => 
				$oid_status{$oid->{name}} ? 'AntiqueWhite' : $old_bg
		);
		push @widget_o, $oid_button;
		$widget_o{$oid->{name}} = $oid_button;
	}
	for my $i (0..$#widget_o) {
		$widget_o[$i]->configure(
			-command => sub { 
		print "but oid name: $oid_name[$i] status: $oid_status{$oid_name[$i]}\n";
				$oid_status{$oid_name[$i]} = !  $oid_status{$oid_name[$i]};
		print "but oid name: $oid_name[$i] status: $oid_status{$oid_name[$i]}\n";
				$widget_o[$i]->configure( -background => 
					$oid_status{$oid_name[$i]} ?  'AntiqueWhite' : $old_bg ,
			-activebackground => 
					$oid_status{$oid_name[$i]} ? 'AntiqueWhite' : $old_bg
					
					);
			});
	}
	my $toggle_jack = $oid_frame->Button;
	
	$toggle_jack->configure(
		-text => q(Jack ON/OFF),
		-command => sub {
			my $color = $toggle_jack->cget( -background );
				if ($color eq q(lightblue) ){

					# jack is on, turn it off
				
					convert_to_alsa();
					paint_button($toggle_jack, $old_bg);
					$jack_on = 0;
				}
				else {

					convert_to_jack();
					paint_button($toggle_jack, q(lightblue));
					$jack_on = 1;
				}
			}
		);
	push @widget_o, $toggle_jack; # since no one else uses this array
				
		
	map { $_ -> pack(-side => 'left') } ($outputs, @widget_o);
	
}
sub paint_button {
	my ($button, $color) = @_;
	$button->configure(-background => $color,
						-activebackground => $color);
}
sub flash_ready {
	my $color;
		if (@record ){
			$color = 'lightpink'; # live recording
		} elsif ( really_recording ){  # mixing only
			$color = 'yellow';
		} else {  $color = 'lightgreen'; }; # just playback

	$debug and print "flash color: $color\n";
	_display(-background => $color);
	$->after(10000, 
		sub{ length_display(-background => $old_bg) }
	);
}
sub take_gui {
	my $t = shift;
	#my $debug = 1;

	$debug2 and print "&take_gui\n";
		my $tname = $alias{$t} ? $alias{$t} : $t;
		my $name = $take_frame->Menubutton(
				-text => ucfirst $tname,
				-tearoff =>0,
			)->pack(-side => 'left');
		push @widget_t, $name;
	$debug and print "=============\n\@widget_t\n",yaml_out(\@widget_t);
		
		if ($t != 1) { # do not add REC command for Mixdown group MIX

		$name->AddItems([
			'command' => $::REC,
			-background => $old_bg,
			-command => sub { 
				no strict qw(vars);
				defined $my_t or my $my_t = $t;
				use strict qw(vars);
				select_take ($my_t, qq(REC) );
				}
			]);
		}

		$name->AddItems([
			'command' => $::MON,
			-background => $old_bg,
			-command => sub {
				no strict qw(vars);
				defined $my_t or my $my_t = $t;
				use strict qw(vars);
				select_take($my_t, qq(MON)); 
				}
			]);
		$name->AddItems([
			'command' => $::MUTE,
			-background => $old_bg,
			-command => sub {
				no strict qw(vars);
				defined $my_t or my $my_t = $t;
				use strict qw(vars);
				select_take($my_t, qq(MUTE)); 
				}

		]);

							   
}
sub global_version_buttons {
#	( map{ $_->destroy } @global_version_buttons ) if @global_version_buttons; 
    my @children = $widget_t[1]->children;
	for (@children) {
		$_->cget(-value) and $_->destroy;
	}; # should remove menubuttons
		
	@global_version_buttons = ();
	$debug and print "making global version buttons range:", join ' ',1..$last_version, " \n";
 	for my $v (undef, 1..$last_version) {
		no warnings;
		next unless grep{  grep{ $v == $_ } @{ $state_c{$_}->{versions} } }
			grep{ $_ != 1 } @all_chains; # MIX 
		use warnings;
 		push @global_version_buttons,
			$widget_t[1]->radiobutton(
				###  HARDCODED, second take widget
				-label => ($v ? $v : ''),
				-variable => \$monitor_version,
				-value => $v,
				-command => sub { 
					$state_t{2}->{rw} = $::MON; ### HARDCODED SECOND TAKE; MIX
					mon_vert($v);  # select this version
					setup_transport(); 
					connect_transport();
					refresh();
					}

 					);
 	}
}
sub track_gui { # nearly 300 lines! 

	my $n = shift; # chain index is lexicalized, will remain static in callbacks
					# my $j is effect index
	my ($name, $version, $rw, $ch_r, $ch_m, $vol, $mute, $solo, $unity, $pan, $center);
	my $this_take = $t; 
	$debug2 and print "&track_gui\n";
	my $stub = $state_c{$n}->{active};
	$name = $track_frame->Label(
			-text => $state_c{$n}->{file},
			-justify => 'left');
	$version = $track_frame->Menubutton( 
					-text => $stub,
					-tearoff => 0);
	for my $v (undef, @{$state_c{$n}->{versions}}) {
					$version->radiobutton(
						-label => ($v ? $v: ''),
						-variable => \$state_c{$n}->{active},
						-value => $v,
						-command => 
		sub { $version->configure(-text=> selected_version($n) ) 
	#		unless rec_status($n) eq $::REC
			}
					);
	}

	$ch_r = $track_frame->Menubutton(
					-textvariable => \$state_c{$n}->{ch_r},
					-tearoff => 0,
				);
			if ( $n != 1 ) { # for all but Mixdown track MIX
				for my $v (1..$tk_input_channels) {
					$ch_r->radiobutton(
						-label => $v,
						-variable => \$state_c{$n}->{ch_r},
						-value => $v,
						-command => sub { 
							$state_c{$n}->{rw} = $::REC;
							refresh() }
				 		)
				}
			}
	$ch_m = $track_frame->Menubutton(
					-textvariable => \$state_c{$n}->{ch_m},
					-tearoff => 0,
				);
				for my $v (1..10) {
					$ch_m->radiobutton(
						-label => $v,
						-variable => \$state_c{$n}->{ch_m},
						-value => $v,
						-command => sub { 
							$state_c{$n}->{rw} = $::MON;
							refresh_c($n) }
				 		)
				}
	$rw = $track_frame->Menubutton(
		-text => $state_c{$n}->{rw},
		-tearoff => 0,
	);

	my @items = (
			[ 'command' => $::REC,
				-foreground => 'red',
				-command  => sub { 
					$state_c{$n}->{rw} = $::REC;
					refresh();
					}
			],
			[ 'command' => $::MON,
				-command  => sub { 
					$state_c{$n}->{rw} = $::MON;
					refresh();
					}
			],
			[ 'command' => $::MUTE, 
				-command  => sub { 
					$state_c{$n}->{rw} = $::MUTE;
					refresh();
					}
			],
		);
	map{$rw->AddItems($_) unless $n == 1} @items; # MIX CONDITIONAL
	$state_c{$n}->{rw} = $::MON if $n == 1;          # MIX

 
   ## XXX general code mixed with GUI code

	# Volume

	my $p_num = 0; # needed when using parameter controllers
	my $vol_id = add_volume_control($n);


	$debug and print "vol cop_id: $vol_id\n";
	my %p = ( 	parent => \$track_frame,
			chain  => $n,
			type => 'ea',
			cop_id => $vol_id,
			p_num		=> $p_num,
			length => 300, 
			);


	 $debug and do {my %q = %p; delete $q{parent}; print
	 "x=============\n%p\n",yaml_out(\%q)};

	$vol = make_scale ( \%p );
	# Mute

=comment
	$mute = $track_frame->Button;
	
	$mute->configure( -command => sub { toggle_muting($mute, $n) });
=cut;
	$mute = $track_frame->Button(
	  		-command => sub { 
				if ($copp{$vol_id}->[0]) {  # non-zero volume
					$old_vol{$n}=$copp{$vol_id}->[0];
					$copp{$vol_id}->[0] = 0;
					effect_update($p{chain}, $p{cop_id}, $p{p_num}, 0);
					$mute->configure(-background => 'brown');
					$mute->configure(-activebackground => 'brown');
				}
				else {
					$copp{$vol_id}->[0] = $old_vol{$n};
					effect_update($p{chain}, $p{cop_id}, $p{p_num}, 
						$old_vol{$n});
					$old_vol{$n} = 0;
					$mute->configure(-background => $old_bg);
					$mute->configure(-activebackground => $old_bg);
				}
			}	
	  );

=comment
	
	# Solo

	$solo = $track_frame->Button;
	my @muted;
	$solo->configure( -command => sub {

		# do nothing if mix track
		
		return if $n == 1; MIX

		# do nothing if setup not connected
		
		return if ! grep{/$session_name/} eval_iam(q(cs-connected));

		# do nothing if someone else is soloing;
		
		return if grep{ is_soloing($_) } grep {$_ != $n} @all_chains; # but some may
		                                                               # not be in
																	   # chain
																	   # setup

		# restore prior mute settings if I had been soloing
		
		if (is_soloing($n) ) {
		
			$solo->configure(-foreground => $old_bg );
			$solo->configure(-activeforeground => $old_bg );

			map{ toggle_mute($_) if $muted[$_] != is_muted($_) } 
				grep{$_ != 1} @all_chains; # MIX
		}

		# otherwise save muted status for each track and mute all
		
		else {
			map{ $mute($_) = is_muted($_) } grep{$_ != 1} @all_chains; # MIX

			map{ toggle_mute($_) } 
			grep {! is_muted($_) } 
			grep {$_ != $n} 
			grep {$_ != 1} 
			@all_chains;

			is_muted($n) and toggle_mute($n);
			
			$solo->configure(-foreground => q(yellow) );
			$solo->configure(-activeforeground => q(yellow) );

			
		}
	});


=cut

	# Unity

	$unity = $track_frame->Button(
	  		-command => sub { 
				$copp{$vol_id}->[0] = 100;
	 			effect_update($p{chain}, $p{cop_id}, $p{p_num}, 100);
			}
	  );

	  
	# Pan
	# effects code mixed with GUI code XXX
	# run on initializing the track gui

	
	my $pan_id = add_pan_control($n);
	
	$debug and print "pan cop_id: $pan_id\n";
	$p_num = 0;           # first parameter
	my %q = ( 	parent => \$track_frame,
			chain  => $n,
			type => 'epp',
			cop_id => $pan_id,
			p_num		=> $p_num,
			);
	 $debug and do {my %q = %p; 
		 delete $q{parent}; 
	 	 print "x=============\n%p\n",yaml_out(\%q)};
	$pan = make_scale ( \%q );

	# Center

	$center = $track_frame->Button(
	  	-command => sub { 
			$copp{$pan_id}->[0] = 50;
			effect_update($q{chain}, $q{cop_id}, $q{p_num}, 50);
		}
	  );
	
	my $effects = $effect_frame->Frame->pack(-fill => 'both');;

	# effects, held by widget_c->n->effects is the frame for
	# all effects of the track

	@{ $widget_c{$n} }{qw(name version rw ch_r ch_m mute effects)} 
		= ($name,  $version, $rw, $ch_r, $ch_m, $mute, \$effects);#a ref to the object
	$debug and print "=============\n\%widget_c\n",yaml_out(\%widget_c);
	my $parents = ${ $widget_c{$n}->{effects} }->Frame->pack(-fill => 'x');

	# parents are the independent effects

	my $children = ${ $widget_c{$n}->{effects} }->Frame->pack(-fill => 'x');
	
	# children are controllers for various paramters

	$widget_c{$n}->{parents} = $parents;   # parents belong here

	$widget_c{$n}->{children} = $children; # children go here
	
	$parents->Label(-text => (uc $stub) )->pack(-side => 'left');

	my @tags = qw( EF P1 P2 L1 L2 L3 L4 );
	my @starts =   ( $e_bound{tkeca}{a}, 
					 $e_bound{preset}{a}, 
					 $e_bound{preset}{b}, 
					 $e_bound{ladspa}{a}, 
					 $e_bound{ladspa}{b}, 
					 $e_bound{ladspa}{c}, 
					 $e_bound{ladspa}{d}, 
					);
	my @ends   =   ( $e_bound{tkeca}{z}, 
					 $e_bound{preset}{b}, 
					 $e_bound{preset}{z}, 
					 $e_bound{ladspa}{b}-1, 
					 $e_bound{ladspa}{c}-1, 
					 $e_bound{ladspa}{d}-1, 
					 $e_bound{ladspa}{z}, 
					);
	my @add_effect;

	map{push @add_effect, effect_button($n, shift @tags, shift @starts, shift @ends)} 1..@tags;
	
	$name->grid($version, $rw, $ch_r, $ch_m, $vol, $mute, $unity, $pan, $center, @add_effect);

	refresh();

	
}

sub effect_button {
	$debug2 and print "&effect_button\n";
	my ($n, $label, $start, $end) = @_;
	$debug and print "chain $n label $label start $start end $end\n";
	my @items;
	my $widget;
	my @indices = ($start..$end);
	if ($start >= $e_bound{ladspa}{a} and $start <= $e_bound{ladspa}{z}){
		@indices = ();
		@indices = @ladspa_sorted[$start..$end];
		#	print "length sorted indices list: ".scalar @indices. "\n";
#	print join " ", @indices;
	}
		
		for my $j (@indices) { 
=comment
	if ($start >= $e_bound{ladspa}{a} and $start <= $e_bound{ladspa}{z}){
		print "adding effect: $effects[$j]->{name}\n";
		}
=cut
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
		-menuitems => [@items],
	);
	$widget;
}

sub make_scale {
	# my $debug = 1;
	$debug2 and print "&make_scale\n";
	my $ref = shift;
	my %p = %{$ref};
=comment
	%p contains following:
	cop_id   => operator id, to access dynamic effect params in %copp
	parent => parent widget, i.e. the frame
	p_num      => parameter number, starting at 0
	length       => length widget # optional 
=cut
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
			-from   =>   $effects[$i]->{params}->[$p]->{begin},
			-to   =>     $effects[$i]->{params}->[$p]->{end},
			-resolution => ($effects[$i]->{params}->[$p]->{resolution} 
				?  $effects[$i]->{params}->[$p]->{resolution}
				: abs($effects[$i]->{params}->[$p]->{end} - 
					$effects[$i]->{params}->[$p]->{begin} ) > 30 
						? 1 
						: abs($effects[$i]->{params}->[$p]->{end} - 
							$effects[$i]->{params}->[$p]->{begin} ) / 100),
		  -width => 12,
		  -length => $p{length} ? $p{length} : 100,
		  -command => sub { effect_update($n, $id, $p, $copp{$id}->[$p]) }
		  );

		# auxiliary field for logarithmic display
		no warnings;	
		if ($effects[$i]->{params}->[$p]->{hint} =~ /logarithm/) {
			my $log_display = $frame->Label(
				-text => exp $effects[$i]->{params}->[$p]->{default},
				-width => 5,
				);
			$controller->configure(
		  		-command => sub { 
					effect_update($n, $id, $p, exp $copp{$id}->[$p]);
					$log_display->configure(
						-text => $effects[$i]->{params}->[$p]->{name} =~ /hz/i
							? int exp $copp{$id}->[$p]
							: dn(exp $copp{$id}->[$p], 1)
						);
					}
				);
		$log_display->grid($controller);
		}
		else { $controller->grid; }

		return $frame;
		use warnings;

	}	

	elsif ($display_type eq q(field) ){ 

	 	# then return field type controller widget

		return ${ $p{parent} }->Entry(
			-textvariable =>\$copp{$id}->[$p],
			-width => 6,
	#		-command => sub { effect_update($n, $id, $p, $copp{$id}->[$p]) },
			# doesn't work with Entry widget
			);	

	}
	else { croak "missing or unexpected display type: $display_type" }

}
=comment
sub is_soloing {
	my $n = shift;	
	$widget_c{$n}{solo}->cget('-foreground') eq q(yellow)
}
sub toggle_muting {
	my ($widget, $n) = @_;
	toggle_mute($n);
	if (is_muted($n)){
		$widget->configure(-background => 'brown');
		$widget->configure(-activebackground => 'brown');
	} 
	else {
		$widget->configure(-background => $old_bg);
		$widget->configure(-activebackground => $old_bg);
	}
}
sub toggle_mute {
	my $setup = eval_iam("cs-connected");
	$setup =~ /$session_name/ or return; # only work if connected setup
	my $n = shift;
	is_muted();
	eval_iam("c-select $n");
	eval_iam("c-muting");
	is_muted();
}
sub is_muted {
	my $n = shift;
		my ($cs) = grep{/Chain "$n"/} split "\n", eval_iam("cs");
		# print "CS: $cs\n";
		my $status = $cs =~ /muted/;
		print ( $status 
			? "track $n: muted\n"
			: "track $n: not muted\n"

		);
		$status;
}
=cut
