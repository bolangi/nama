# i'm a comment!
asdf: 'asdf' { print "hello"}
read: command(s)
command: fail
end: /\s*$/ 
#end: /\s*;\s*/ 
end: ';' 
helpx: 'helpx' end { print "hello_from your command line gramar\n"; 1 }
help: _help dd end { print "hello_from your command line gramar\n"; 1 }
fail: 'f' end { print "your command line gramar will get a zero\n"; 0 }

create_project: _create_project name end {
	::load_project( 
		name => ::remove_spaces($item{name}),
		create => 1,
	);
	print "created project: $::project_name\n";

}

load_project: _load_project name end {
	my $untested = ::remove_spaces($item{name});
	print ("Project $untested does not exist\n"), return
	unless -d ::join_path ::wav_dir(), $untested; 
	::load_project( name => ::remove_spaces($item{name}) );
	::setup_transport() and ::connect_transport();

	print "loaded project: $::project_name\n";
}
save_state: _save_state name(?) end { 
	::save_state( $item{name} ); 
	}
get_state: _get_state name(?) end {
 	::load_project( 
 		name => $::project_name,
 		settings => $item{name}
 		);
 #	print "set state:  $item{name}\n";
 	}

add_track: _add_track name channel(s?) end { 
	#carp ("track name already in use: $item{name}\n"),
	#	return if $::Track::track_names{$item{name}}; 
	::add_track($item{name}); 
	print "added track $item{name}\n";
}

# add_track: _add_track name(s) end { 
#  	map { ::add_track $_ } @{ $item{name} };
#  	1;
#  }

set_track: _set_track key someval end {
	 $::this_track->set( $item{key}, $item{someval} );
}
dump_track: _dump_track { $::this_track->dumpp }

dump_group: _dump_group { $::tracker->dumpp }

key: /\w+/

someval: /[\w.+-]+/
 
remove_track: _remove_track name end {
	$::tn{ $item{name} }->set(hide => 1); }

generate: _generate end { ::setup_transport(); 1 }

arm: _arm end { 
	::setup_transport() and ::connect_transport(); 1 }

connect: _connect end { ::connect_transport(); 1 }

disconnect: _disconnect end { ::disconnect_transport(); 1 }

## we reach here

renew_engine: _renew_engine end { ::new_engine(); 1  }

start: _start end { ::start_transport(); 1}
stop: _stop end { ::stop_transport();
1}

S: _S end { ::eval_iam("stop") }
T: _T end { ::eval_iam("start") }

show_setup: _show_setup end { 	

	::Text::show_tracks ( ::Track::all );
}

show_chain_setup: _show_chain_setup {
	#my $chain_setup;
	#::io(join_path($project_dir, $chain_setup_file) ) > $chain_setup; 
	#print $chain_setup;
}

show_track: _show_track end {
	::Text::show_tracks($::this_track);
# 	print "Versions: ", join " ", @{$::this_track->versions}, $/;
 	map { 
 		my $op_id = $_;
 		 my $i = 	$::effect_i{ $::cops{ $op_id }->{type} };
 		 print $op_id, ": " , $::effects[ $i ]->{name},  " ";
 		 my @pnames =@{$::effects[ $i ]->{params}};
			map{ print join " ", 
			 	$pnames[$_]->{name}, 
				$::copp{$op_id}->[$_],'' 
		 	} (0..scalar @pnames - 1);
		 print $/;
		#  print ::yaml_out( \@pnames );
		#print scalar @pnames;
		#print $pnames[0]->{name};
		#print map{ 
		#print $_, $/;
			#join " ", $pnames[$_]->{name}, $_,
	# $::copp{$op_id}->[$_], 
		#$/ 
		
		#}
			  ;
 		#map { 
		# print $pnames[$_]->{name}, " ",  , 
		# print ref $pnames[$_] , 
 		# 	$/
		 #	print $_, " ";
		#	} 0 .. scalar @pnames - 1;
 
 	 } @{ $::this_track->ops };
}
show_track: _show_track name end { 
 	::Text::show_tracks( $::tn{$item{name}} ) if $::tn{$item{name}}
}
show_track: _show_track dd end {  
	::Text::show_tracks( $::ti[$item{dd}] ) if $::ti[$item{dd}]
}
	
	# print "name: $item{name}\nnumber: $item{dd}\n";
# print ("unknown track\n"), return 
# 		if $item{dd}   and ! $::ti[$item{dd}]
# 		or $item{name} and ! $::tn{$item{name}};
# 
# 	map { 	push @::format_fields,  
# 			$_->n,
# 			$_->active,
# 			$_->name,
# 			$_->rw,
# 			$_->rec_status,
# 			($_->ch_r or 1),
# 			($_->ch_m or 1),
# 
# 		} ($::tn{$item{name}} or $::ti[item{dd}] or $::this_track;
# 		
# 	write; # using format at end of file UI.pm
# 	1;
#}

group_rec: _group_rec end { $::tracker->set( rw => 'REC') }
group_mon: _group_mon end  { $::tracker->set( rw => 'MON') }
group_off: _group_mute end { $::tracker->set(rw => 'OFF') }

mixdown: _mixdown end { $::mixdown_track->set(rw => 'REC')}
mixplay: _mixplay end { $::mixdown_track->set(rw => 'MON');
						$::tracker->set(rw => 'OFF');
}
mixoff:  _mixoff  end { $::mixdown_track->set(rw => 'OFF');
						$::tracker->set(rw => 'MON')}



mix: 'mix' end {1}

norm: 'norm' end {1}

record: 'record' end {} # set to Tracker-Record 

exit: 'exit' end { ::save_state($::state_store_file); exit; }


channel: r | m

r: 'r' dd  {	
				$::this_track->set(ch_r => $item{dd});
				$::ch_r = $item{dd};
				print "setting $::ch_r to $item{dd}\n";
				
				}
m: 'm' dd  {	
				$::this_track->set(ch_m => $item{dd}) ;
				$::ch_m = $item{dd};
				print "Output switched to channel $::ch_m\n";
				
				}

off: 'off' end {$::this_track->set(rw => 'OFF'); }
rec: 'rec' end {$::this_track->set(rw => 'REC'); }
mon: 'mon' end {$::this_track->set(rw => 'MON'); }


last: ('last' | '$' ) 

dd: /\d+/

name: /\w+/


wav: name { $::this_track = $::tn{$item{name}} if $::tn{$item{name}}  }

set_version: _set_version dd end { $::this_track->set(active => $item{dd})}
 
vol: _vol dd end { $::copp{ $::this_track->vol }->[0] = $item{dd}; 
				::sync_effect_param( $::this_track->vol, 0);
} 
vol: _vol '+' dd end { $::copp{ $::this_track->vol }->[0] += $item{dd};
				::sync_effect_param( $::this_track->vol, 0);
} 
vol: _vol '-' dd end { $::copp{ $::this_track->vol }->[0] -= $item{dd} ;
				::sync_effect_param( $::this_track->vol, 0);
} 
vol: _vol end { print $::copp{$::this_track->vol}[0], $/ }

cut: _cut end { $::copp{ $::this_track->vol }->[0] = 0;
				::sync_effect_param( $::this_track->vol, 0);
}

unity: _unity end { $::copp{ $::this_track->vol }->[0] = 100;
				::sync_effect_param( $::this_track->vol, 0);
}

pan: _pan dd end { $::copp{ $::this_track->pan }->[0] = $item{dd};
				::sync_effect_param( $::this_track->pan, 0);

} 
pan: _pan '+' dd end { $::copp{ $::this_track->pan }->[0] += $item{dd} ;
				::sync_effect_param( $::this_track->pan, 0);
} 
pan: _pan '-' dd end { $::copp{ $::this_track->pan }->[0] -= $item{dd} ;
				::sync_effect_param( $::this_track->pan, 0);
} 
pan: _pan end { print $::copp{$::this_track->pan}[0], $/ }
 
pan_right: _pan_right   end { $::copp{ $::this_track->pan }->[0] = 100;
				::sync_effect_param( $::this_track->pan, 0);
}
pan_left:  _pan_left    end { $::copp{ $::this_track->pan }->[0] = 0; 
				::sync_effect_param( $::this_track->pan, 0);
}
pan_center: _pan_center end { $::copp{ $::this_track->pan }->[0] = 50   ;
				::sync_effect_param( $::this_track->pan, 0);
}
pan_back:  _pan_back end {}

list_marks: _list_marks end {'TODO' }

remove_mark: _remove_mark end {'TODO' }

mark: _mark end { }

next_mark: _next_mark end {}

previous_mark: _previous_mark end {}

mark_loop: _mark_loop end {}

name_mark: _name_mark end {}

list_marks: _list_marks end {}

show_effects: _show_effects end {}

remove_effect: _remove_effect op_id(s) end {
	#print join $/, @{ $item{"op_id(s)"} }; 
	map{ print "removing op_id: $_\n"; ::remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	# map{ print "op_id: $_\n"; ::remove_effect( $_ )}  @{ $item{"op_id(s)"}} ;

}
op_id: /[A-Z]+/


add_effect: _add_effect name value(s?)  end { 
print join $/, keys %item;
#print "itemdd:", $item{"dd(s?)"} , ":\n";
#print "itemdd2:", $item{"dd"} , ":\n";
#print "ref:", ref $item{dd} , ":\n";

print "code: ", $item{name}, $/;
	my %p = (
		chain => $::this_track->n,
		values => $item{"value(s?)"},
		type => $item{name},
		);
		print "adding effect\n";
		#print (::yaml_out(\%p));
	::add_effect( \%p );
}

delta_effect: _delta_effect op_id parameter sign value {
		$item{parameter}--; # user's one-based indexing to our zero-base
		my $new_value = 
 			eval (join " ",
 				$::copp{$item{op_id}}->[$item{parameter}], 
 				$item{sign},
 				$item{value});

	::effect_update_copp_set( 
		$::cops{ $item{op_id} }->{chain}, 
		$item{op_id}, 
		$item{parameter}, 
		$new_value);

}
	
modify_effect: _modify_effect op_id parameter value sign(?) end {

		$item{parameter}--; # user's one-based indexing to our zero-base

		my $new_value = $item{value}; 

		if ($item{"sign(?)"}) {
			$new_value = 
 			eval (join " ",
 				$::copp{$item{op_id}}->[$item{parameter}], 
 				@{$item{"sign(?)"}},
 				$item{value});
		}
			
	::effect_update_copp_set( 
		$::cops{ $item{op_id} }->{chain}, 
		$item{op_id}, 
		$item{parameter}, 
		$new_value);

}
sign: /[+-]/
op_id: /[A-Z]+/

parameter: /\d+/

value: /[\d\.eE+-]+/ # -1.5e-6
	
group_version: _group_version dd end { $::tracker->set( version => $item{dd} )}


list_versions: _list_versions end { 
	print join " ", @{$::this_track->versions}, $/;
}


