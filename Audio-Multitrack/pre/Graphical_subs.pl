# gui handling
use Carp;

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
	#my @children = $take_frame->children;
	#map{ $_->destroy  } @children[1..$#children];
	my @children = $track_frame->children;

	# leave field labels (first row)
	map{ $_->destroy  } @children[11..$#children]; 
	
	$tracker_group_widget->destroy if $tracker_group_widget;
	map{ $_->destroy  } values %widget_m if %widget_m;
}

sub init_gui {

	$debug2 and print "&init_gui\n";

	@_ = discard_object(@_);

### 	Tk root window layout

	$mw = MainWindow->new; 
	$mw->title("Tk Ecmd"); 
	$mw->deiconify;

	### init effect window

	$ew = $mw->Toplevel;
	$ew->title("Effect Window");
	$ew->deiconify; 
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

	$project_label = $mw->Label->pack(-fill => 'both');
	$old_bg = $project_label->cget('-background');
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
	$mark_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	$fast_frame = $time_frame->Frame->pack(
		-side => 'bottom', 
		-fill => 'both');
	$load_frame = $mw->Frame->pack(-side => 'bottom', -fill => 'both');



	$sn_label = $load_frame->Label(-text => "Enter project name:")->pack(-side => 'left');
	$sn_text = $load_frame->Entry(-textvariable => \$project, -width => 45)->pack(-side => 'left');
	$sn_load = $load_frame->Button->pack(-side => 'left');;
#	$sn_load_nostate = $load_frame->Button->pack(-side => 'left');;
	$sn_new = $load_frame->Button->pack(-side => 'left');;
	$sn_quit = $load_frame->Button->pack(-side => 'left');
	$sn_save = $load_frame->Button->pack(-side => 'left');
	$sn_recall = $load_frame->Button->pack(-side => 'left');
	$save_id = "";
	my $sn_save_text = $load_frame->Entry(
									-textvariable => \$save_id,
									-width => 15
									)->pack(-side => 'left');
	$sn_dump = $load_frame->Button->pack(-side => 'left');

	$build_track_label = $add_frame->Label(-text => "Track")->pack(-side => 'left');
	$build_track_text = $add_frame->Entry(-textvariable => \$track_name, -width => 12)->pack(-side => 'left');
	$build_track_rec_label = $add_frame->Label(-text => "Rec CH")->pack(-side => 'left');
	$build_track_rec_text = $add_frame->Entry(-textvariable => \$ch_r, -width => 2)->pack(-side => 'left');
	$build_track_mon_label = $add_frame->Label(-text => "Mon CH")->pack(-side => 'left');
	$build_track_mon_text = $add_frame->Entry(-textvariable => \$ch_m, -width => 2)->pack(-side => 'left');
	$build_track_add = $add_frame->Button->pack(-side => 'left');;

	$sn_load->configure(
		-text => 'Load',
		-command => sub{ load_project(name => remove_spaces $project_name)});
	$sn_new->configure( 
		-text => 'New',
		-command => sub{ load_project(
							name => remove_spaces($project_name),
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
	$sn_dump->configure(
		-text => q(Dump state),
		-command => sub{ print &status_vars });
	$sn_quit->configure(-text => "Quit",
		 -command => sub { 
				return if transport_running();
				exit;
				 }
				);


	$build_track_add->configure( 
			-text => 'Add',
			-command => sub { add_track(remove_spaces($track_name)) }
	);

=comment TAKE
	$build_new_take->configure( 
			-text => 'New Group',
			-command =>
			\&new_take, # used for mixdown

			
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
	@_ = discard_object(@_);
	$debug2 and print "&transport_gui\n";

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
			project_label_configure(-background => 'lightpink') 
		}
		else {
			project_label_configure(-background => 'lightgreen') 
		}
		start_transport();
				});
	$transport_setup_and_connect->configure(
			-text => 'Arm',
			-command => sub {&setup_transport and &connect_transport}
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
	@_ = discard_object(@_);
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

	# jump

	my $jump_label = $fast_frame->Label(-text => q(JUMP), -width => 12);
	my $mark_label = $mark_frame->Label(-text => q(MARK), -width => 12)->pack(-side => left);;
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
	
	my $drop_mark = $mark_frame->Button(
		-text => 'Drop mark',
		-background => $old_bg,
		-command => \&drop_mark,
	)->pack(-side => 'left');	
		
	$mark_remove = $mark_frame->Button(
				-text => 'Remove',
				-command => \&arm_mark_toggle, 
	)->pack(-side => 'left');	
}

sub oid_gui {
	$debug2 and print "&oid_gui\n";
	@_ = discard_object(@_);
	my $outputs = $oid_frame->Label(-text => 'OUTPUTS', -width => 12);
	my @oid_name;
	for my $rule ( ::Rule::all_rules ){
		my $name = $rule->name;
		my $status = $rule->status;
		# print "gui oid name: $name status: $status\n";
		next if $name =~ m/setup|mix_|mixer|rec_file|multi/i;
		push @oid_name, $name;
		
		my $oid_button = $oid_frame->Button( 
			-text => ucfirst $name,
			-background => 
				$status ?  'AntiqueWhite' : $old_bg,
			-activebackground => 
				$status ? 'AntiqueWhite' : $old_bg
		);
		$oid_button->configure(
			-command => sub { 
				$rule->set(status => ! $rule->status);
				$oid_button->configure( -background => 
					$rule->status ?  'AntiqueWhite' : $old_bg ,
			-activebackground => 
					$rule->status ? 'AntiqueWhite' : $old_bg
					
					);
			});
		push @widget_o, $oid_button;
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
	@_ = discard_object(@_);
	my ($button, $color) = @_;
	$button->configure(-background => $color,
						-activebackground => $color);
}
sub flash_ready {
	my $color;
		if (@record ){
			$color = 'lightpink'; # live recording
		} elsif ( &really_recording ){  # mixing only
			$color = 'yellow';
		} else {  $color = 'lightgreen'; }; # just playback

	$debug and print "flash color: $color\n";
	length_display(-background => $color);
	$clock->after(10000, 
		sub{ length_display(-background => $old_bg) }
	);
}
sub group_gui {  
	@_ = discard_object(@_);
	my $name = shift;
	my $group = $::Group::by_name{$name};
	$debug2 and print "&group_gui\n";
		my $group_rw = $take_frame->Menubutton(
				-text => $name,
				-tearoff =>0,
			)->pack(-side => 'left');
		push @widget_t, $group_rw;
	#$debug and print "=============\n\@widget_t\n",yaml_out(\@widget_t);
		
		$group_rw->AddItems([
			'command' => 'REC',
			-background => $old_bg,
			-command => sub { 
				$group->set(rw => 'REC');
				refresh();
				}
			],[
			'command' => 'MON',
			-background => $old_bg,
			-command => sub { 
				$group->set(rw => 'MON');
				refresh();
				}
			],[
			'command' => 'MUTE',
			-background => $old_bg,
			-command => sub { 
				$group->set(rw => 'MUTE');
				refresh();
				}
			],);
$group_rw

}
sub global_version_buttons {
	
	local $debug = 1;
	if (defined $tracker_group_widget) {
		my @children = $tracker_group_widget->children;
		for (@children) {
			$_->cget(-value) and $_->destroy;
		}; # remove menubuttons
	}
		
	$debug and print "making global version buttons range:",

	join ' ',1..$ti[-1]->group_last, " \n";

 	for my $v (undef, 1..$ti[-1]->group_last) { 

	# the highest version number of all tracks in the
	# $tracker group
	
	my @user_track_indices = grep { $_ > 2 } map {$_->n} ::Track::all;
	
		next unless grep{  grep{ $v == $_ } @{ $ti[$_]->versions } }
			@user_track_indices;
		
			# scalar grep{ $-> > 2 } @all_chains; # excludes master (1), mix (2)
			$tracker_group_widget->radiobutton( 

				-label => ($v ? $v : ''),
				-value => $v,
				-command => sub { 
					$tracker->set(version => $v); 
					setup_transport() and connect_transport();
					refresh();
					}

 					);
 	}
}
sub track_gui { 
	$debug2 and print "&track_gui\n";
	@_ = discard_object(@_);
	my $n = shift;
	print "found index: $n\n";
	my @rw_items = @_ ? @_ : (
			[ 'command' => "REC",
				-foreground => 'red',
				-command  => sub { 
					$ti[$n]->set(rw => "REC");
					refresh_c($n);
			}],
			[ 'command' => "MON",
				-command  => sub { 
					$ti[$n]->set(rw => "MON");
					refresh_c($n);
			}],
			[ 'command' => "MUTE", 
				-command  => sub { 
					$ti[$n]->set(rw => "MUTE");
					refresh_c($n);
			}],
		);
	my ($name, $version, $rw, $ch_r, $ch_m, $vol, $mute, $solo, $unity, $pan, $center);
	my $this_take = $t; 
	my $stub = " ";
	$stub .= $ti[$n]->active;
	$name = $track_frame->Label(
			-text => $ti[$n]->name,
			-justify => 'left');
	$version = $track_frame->Menubutton( 
					-text => $stub,
					-tearoff => 0);
	my @versions = '';
	push @versions, @{$ti[$n]->versions} if @{$ti[$n]->versions};
	for my $v (@versions) {
					$version->radiobutton(
						-label => $v,
						# -value => $v,
						-command => 
		sub { 
			$ti[$n]->set( active => $v );
			return if $ti[$n]->rec_status eq "REC";
			$version->configure( -text=> $ti[$n]->current_version ) 
			}
					);
	}

	# skip the rest of the widgets for the mixdown track
	
# if ( $n != 2 ){


	$ch_r = $track_frame->Menubutton(
					-tearoff => 0,
				);
	for my $v ("",1..$tk_input_channels) {
		$ch_r->radiobutton(
			-label => $v,
			-value => $v,
			-command => sub { 
			#	$ti[$n]->set(rw => 'REC');
				$ti[$n]->set(ch_r  => $v);
				refresh_c($n) }
			)
	}
	$ch_m = $track_frame->Menubutton(
					-tearoff => 0,
				);
				for my $v ("",1..10) {
					$ch_m->radiobutton(
						-label => $v,
						-value => $v,
						-command => sub { 
			#				$ti[$n]->set(rw  => "MON");
							$ti[$n]->set(ch_m  => $v);
							refresh_c($n) }
				 		)
				}
	$rw = $track_frame->Menubutton(
		-text => $ti[$n]->rw,
		-tearoff => 0,
	);
	map{$rw->AddItems($_)} @rw_items; 

 
	# Volume

	my $p_num = 0; # needed when using parameter controllers
	my $vol_id = $ti[$n]->vol;

	local $debug = 1;


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


	# Unity

	$unity = $track_frame->Button(
	  		-command => sub { 
				$copp{$vol_id}->[0] = 100;
	 			effect_update($p{chain}, $p{cop_id}, $p{p_num}, 100);
			}
	  );

	  
	# Pan
	
	my $pan_id = $ti[$n]->pan;
	
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
			$copp{$pan_id}->[0] = 50;
			effect_update($q{chain}, $q{cop_id}, $q{p_num}, 50);
		}
	  );
	
	my $effects = $effect_frame->Frame->pack(-fill => 'both');;

	# effects, held by widget_c->n->effects is the frame for
	# all effects of the track

	@{ $widget_c{$n} }{qw(name version rw ch_r ch_m mute effects)} 
		= ($name,  $version, $rw, $ch_r, $ch_m, $mute, \$effects);#a ref to the object
	#$debug and print "=============\n\%widget_c\n",yaml_out(\%widget_c);
	my $independent_effects_frame 
		= ${ $widget_c{$n}->{effects} }->Frame->pack(-fill => 'x');


	my $controllers_frame 
		= ${ $widget_c{$n}->{effects} }->Frame->pack(-fill => 'x');
	
	# parents are the independent effects
	# children are controllers for various paramters

	$widget_c{$n}->{parents} = $independent_effects_frame;

	$widget_c{$n}->{children} = $controllers_frame;
	
	$independent_effects_frame
		->Label(-text => uc $ti[$n]->name )->pack(-side => 'left');

	#$debug and print( "Number: $n\n"),MainLoop if $n == 2;
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

	refresh_c($n);

=comment
	} else { # Mixdown track
#	#my @filler = map{ "x" } 1..14;
	$name->grid($version, $rw);
#	$version, $rw);

	refresh_c($n);
	}
=cut
}

sub update_version_button {
	@_ = discard_object(@_);
	my ($n, $v) = @_;
	carp ("no version provided \n") if ! $v;
	my $w = $widget_c{$n}->{version};
					$w->radiobutton(
						-label => $v,
						-value => $v,
						-command => 
		sub { $widget_c{$n}->{version}->configure(-text=>$v) 
				unless $ti[$n]->rec_status eq "REC" }
					);
}
=comment
sub update_master_version_button {
				$tracker_group_widget->radiobutton( 
						-label => $ti[1]->last, 
						-value => $ti[3]->last_version,
						-command => sub {
						$::Group::by_name{Tracker}->set(version
						=> $ti[3]->last_version)}
					);
}
=cut


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
		if ($effects[$i]->{params}->[$p]->{hint} =~ /logarithm/ )
		#	or $code eq 'ea') 
		
			{
			my $log_display = $frame->Label(
				-text => exp $effects[$i]->{params}->[$p]->{default},
				-width => 5,
				);
			$controller->configure(
		  		-command => sub { 
					effect_update($n, $id, $p, exp $copp{$id}->[$p]);
					$log_display->configure(
						-text => 
						$effects[$i]->{params}->[$p]->{name} =~ /hz/i
							? int exp $copp{$id}->[$p]
							: dn(exp $copp{$id}->[$p], 1)
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
	#		-command => sub { effect_update($n, $id, $p, $copp{$id}->[$p]) },
			# doesn't work with Entry widget
			);	

	}
	else { croak "missing or unexpected display type: $display_type" }

}
sub arm_mark_toggle { 
	if ($markers_armed) {
		$markers_armed = 0;
		$mark_remove->configure( -background => $old_bg);
	}
	else{
		$markers_armed = 1;
		$mark_remove->configure( -background => 'yellow');
	}
}
sub marker {
	@_ = discard_object( @_);
	my $pos = shift;
	print $pos, " ", int $pos, $/;
	print "mark frame: ", ref $mark_frame, $/;
		$widget_m{$pos} = $mark_frame->Button( 
			-text => colonize(int ($pos) ),
			-background => $old_bg,
			-command => sub { mark($pos) },
		) ->pack(-side => 'left');
}

sub restore_time_marks {
	my @times =  sort keys %marks;
	%marks = (); # reset
	map{ drop_mark $_ } @times;
}
sub destroy_marker {
	@_ = discard_object( @_);
	my $pos = shift;
	$widget_m{$pos}->destroy; 
}
sub colonize { # convert seconds to minutes:seconds 
	my $sec = shift;
	my $min = int ($sec / 60);
	$sec = $sec % 60;
	$sec = "0$sec" if $sec < 10;
	qq($min:$sec);
}
sub update_clock { 
	$ui->clock_config(-text => colonize(eval_iam('cs-get-position')));
}

### end
