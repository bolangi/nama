# sign: /[+-]/
# op_id: /[A-Z]+/
# parameter: /\d+/
# value: /[\d\.eE+-]+/ # -1.5e-6
# key: /\w+/
#someval: /[\w.+-]+/

helpx => sub { print "hello_from your command line gramar\n"} ,
help => sub { print "hello_from your command line gramar\n"} ,
fail => sub { print "your command line gramar will get a zero\n" } ,
create_project => sub { my @args = split " ", $predicate;
	my $name = shift;
	load_project( 
		name => remove_spaces($name),
		create => 1,
	);
	print "created project: $project_name\n";

},
load_project => sub { 
	my @args = split " ", $predicate;
	my $name = shift;
	my $untested = remove_spaces($name);
	print ("Project $untested does not exist\n"), return
	unless -d join_path wav_dir(), $untested; 
	load_project( name => remove_spaces($name) );
	generate_setup() and connect_transport();

	print "loaded project: $project_name\n";
},
save_state => sub { 
	my @args = split " ", $predicate;
	my $name = shift;
	save_state( $name ); 
	},
get_state => sub { 
	my @args = split " ", $predicate;
	my $settings_file = shift @args;
 	load_project( 
 		name => $project_name,
 		settings => $settings_file,
 		),
 	print "set state: $settings_file\n";
 	},
add_track => sub { 
	my @args = split " ", $predicate;
	my $name = shift;
	add_track($name); 
},

set_track => sub { 
	my @args = split " ", $predicate;
	#print join $/, @args, $/;
	my $key = shift;
	my $value = shift;
 $this_track->set( $key, $value),
},
dump_track => sub { $this_track->dumpp } ,
dump_group => sub { $tracker->dumpp } ,

remove_track => sub { 
	my @args = split " ", $predicate;
	my $name = shift;
	$tn{ $name }->set(hide => 1), },
generate => sub { generate_setup() },

arm => sub { 
	generate_setup() and connect_transport() },

connect => sub { connect_transport() },

disconnect => sub { disconnect_transport()}, 

renew_engine => sub { new_engine()},

start => sub { start_transport()},
stop => sub { stop_transport()},

S => sub { eval_iam("stop") } ,
T => sub { eval_iam("start") },

);
__END__
show_setup => sub { 	

	::Text::show_tracks ( Trackall );
},

show_chain_setup => sub {
	my $chain_setup;
	io(join_path(project_dir(), $chain_setup_file) ) > $chain_setup; 
	print $chain_setup;
},

show_track => sub {
	::Text::show_tracks($this_track);
# 	print "Versions: ", join " ", @{$this_track->versions}, $/;
 	map { 
 		my $op_id = $_;
 		 my $i = 	$effect_i{ $cops{ $op_id }->{type} };
 		 print $op_id, ": " , $effects[ $i ]->{name},  " ";
 		 my @pnames =@{$effects[ $i ]->{params}};
			map{ print join " ", 
			 	$pnames[$_]->{name}, 
				$copp{$op_id}->[$_],'' 
		 	} (0..scalar @pnames - 1);
		 print $/;
 	 } @{ $this_track->ops };
},
show_track => sub { 
	my @args = split " ", $predicate;
	my $name = shift;
 	::Text::show_tracks( $tn{$name} ) if $tn{$name}
},
show_track => sub {  
	::Text::show_tracks( $ti[$dd] ) if $ti[$dd]
},
	

group_rec => sub { $tracker->set( rw => 'REC') },
group_mon => sub { $tracker->set( rw => 'MON') },
group_off => sub { $tracker->set(rw => 'OFF') },

mixdown => sub { $mixdown_track->set(rw => 'REC')},
mixplay => sub { $mixdown_track->set(rw => 'MON');
						$tracker->set(rw => 'OFF');
},
mixoff => sub { $mixdown_track->set(rw => 'OFF');
						$tracker->set(rw => 'MON')},



mix => sub {1},

norm => sub {1},

record => sub {}, # set to Tracker-Record 

exit => sub { save_state($state_store_file); exit; },


r => sub {	
				$this_track->set(ch_r => $dd);
				$ch_r = $dd;
				print "setting $ch_r to $dd\n";
				
				},
m => sub {	
				$this_track->set(ch_m => $dd) ;
				$ch_m = $dd;
				print "Output switched to channel $ch_m\n";
				
				},

off => sub {$this_track->set(rw => 'OFF'); },
rec => sub {$this_track->set(rw => 'REC'); },
mon => sub {$this_track->set(rw => 'MON'); },


# last: ('last' | '$' ) 

#dd: /\d+/

#name: /\w+/


#wav: name { $this_track = $tn{$name} if $tn{$name}  }

set_version => sub { $this_track->set(active =>
$dd)},
 
vol => sub { $copp{ $this_track->vol }->[0] = $dd; 
				sync_effect_param( $this_track->vol, 0);
}, 
vol => sub { $copp{ $this_track->vol }->[0] += $dd;
				sync_effect_param( $this_track->vol, 0);
}, 
vol => sub { $copp{ $this_track->vol }->[0] -= $dd ;
				sync_effect_param( $this_track->vol, 0);
}, 
vol => sub { print $copp{$this_track->vol}[0], $/ },

cut => sub { $copp{ $this_track->vol }->[0] = 0;
				sync_effect_param( $this_track->vol, 0);
},

unity => sub { $copp{ $this_track->vol }->[0] = 100;
				sync_effect_param( $this_track->vol, 0);
},

pan => sub { $copp{ $this_track->pan }->[0] = $dd;
				sync_effect_param( $this_track->pan, 0);

}, 
pan => sub { $copp{ $this_track->pan }->[0] += $dd ;
				sync_effect_param( $this_track->pan, 0);
}, 
pan => sub { $copp{ $this_track->pan }->[0] -= $dd ;
				sync_effect_param( $this_track->pan, 0);
}, 
pan => sub { print $copp{$this_track->pan}[0], $/ },
 
pan_right => sub { $copp{ $this_track->pan }->[0] = 100;
				sync_effect_param( $this_track->pan, 0);
},
pan_left => sub { $copp{ $this_track->pan }->[0] = 0; 
				sync_effect_param( $this_track->pan, 0);
},
pan_center => sub { $copp{ $this_track->pan }->[0] = 50   ;
				sync_effect_param( $this_track->pan, 0);
},
pan_back => sub {},

list_marks => sub {'TODO' },

remove_mark => sub {'TODO' },

mark => sub { },

next_mark => sub {},

previous_mark => sub {},

mark_loop => sub {},

name_mark => sub {},

list_marks => sub {},

show_effects => sub {},

remove_effect => sub {
	#print join $/, @{ $item{"op_id(s)"} }; 
	map{ print "removing op_id: $_\n"; remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	# map{ print "op_id: $_\n"; remove_effect( $_ )}  @{ $item{"op_id(s)"}} ;

},
# op_id: /[A-Z]+/


add_effect => sub { 
#print join $/, keys %item;
	my @args = split " ", $predicate;
	my $name = shift;
print "code: ", $name, $/;
	my %p = (
		chain => $this_track->n,
		values => [@args],
		type => $name,
		);
		print "adding effect\n";
		#print (yaml_out(\%p));
	add_effect( \%p );
},

delta_effect => sub {
	my @args = split " ", $predicate;
	my $op_id = shift;
	my $parameter = shift;
	my $value = shift;
		$parameter--; # user's one-based indexing to our zero-base
		my $new_value = 
 			eval (join " ",
 				$copp{$op_id}->[$parameter], 
 				$item{sign},
 				$value);

	effect_update_copp_set( 
		$cops{ $op_id }->{chain}, 
		$op_id, 
		$parameter, 
		$new_value);

},
	
modify_effect => sub {

		$parameter--; # user's one-based indexing to our zero-base

		my $new_value = $value; 

		if ($item{"sign(?)"}) {
			$new_value = 
 			eval (join " ",
 				$copp{$op_id}->[$parameter], 
 				@{$item{"sign(?)"}},
 				$value);
		}
			
	effect_update_copp_set( 
		$cops{ $op_id }->{chain}, 
		$op_id, 
		$parameter, 
		$new_value);

},
group_version => sub { $tracker->set( version => $dd
)},


list_versions => sub { 
	print join " ", @{$this_track->versions}, $/;
 
