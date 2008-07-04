# regex contraining of values
key: /\w+/
someval: /[\w.+-]+/
sign: /[+-]/
op_id: /[A-Z]+/
parameter: /\d+/
value: /[\d\.eE+-]+/ # -1.5e-6
last: ('last' | '$' ) 
dd: /\d+/
name: /\w+/
	
asdf: 'asdf' { print "hello"}
command: fail
end: /\s*$/ 
end: ';' 
help: _help end { print $::helptext }
help: _help name end { ::Text::help($item{name}) }
# iterate over commands yml
# find right command, print helptext
#	print $::helptext  }
helpx: 'helpx' end { print "hello_from your command line gramar\n"; }
fail: 'f' end { print "your command line gramar will get a zero\n"; }
exit: _exit end { ::save_state(); exit }
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

	print "loaded project: $::project_name\n";
}
save_state: _save_state name end { 
	::save_state( $item{name} ); 
	}
save_state: _save_state end { ::save_state() }


get_state: _get_state name end {
	# print "get with parameter: $item{name}\n";
 	::load_project( 
 		name => $::project_name,
 		settings => $item{name}
 		);
 #	print "set state:  $item{name}\n";
 	}
get_state: _get_state end {
	# print "get without parameter\n";
 	::load_project( 
 		name => $::project_name,
 		);
 #	print "set state:  $item{name}\n";
 	}
getpos: _getpos end {  
	print sprintf("%.1f", ::eval_iam q(getpos) )."s", $/; }

#setpos: _setpos someval end { ::eval_iam("setpos ".$item{someval}) }
add_track: _add_track name end { 
	# print "adding: ", ::yaml_out( $item{'channels(s?)'} ), $/;
	::add_track($item{name}); 
	#print "added track $item{name}\n";
}


set_track: _set_track key someval end {
	 $::this_track->set( $item{key}, $item{someval} );
}
dump_track: _dump_track { $::this_track->dumpp }

dump_group: _dump_group { $::tracker->dumpp }

 
remove_track: _remove_track name end {
	$::tn{ $item{name} }->set(hide => 1); }

generate: _generate end { ::generate_setup(); }

arm: _arm end { 
	::generate_setup() and ::connect_transport(); }

connect: _connect end { ::connect_transport(); }

disconnect: _disconnect end { ::disconnect_transport(); }


renew_engine: _renew_engine end { ::new_engine(); }

start: _start end { ::start_transport(); }
stop: _stop end { ::stop_transport(); }

S: _S end { ::eval_iam("stop") }
T: _T end { ::eval_iam("start") }

show_tracks: _show_tracks end { 	

	::Text::show_tracks ( ::Track::all );
}

show_chain_setup: _show_chain_setup {
	my $chain_setup;
	::io( ::join_path( ::project_dir(), $::chain_setup_file) ) > $chain_setup; 
	print $chain_setup, $/, $/;
}

show_io: _show_io { print ::yaml_out( \%::inputs ),
::yaml_out( \%::outputs ); }

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
 
 	 } @{ $::this_track->ops };
}
show_track: _show_track name end { 
 	::Text::show_tracks( $::tn{$item{name}} ) if $::tn{$item{name}}
}
show_track: _show_track dd end {  
	::Text::show_tracks( $::ti[$item{dd}] ) if $::ti[$item{dd}]
}
	
#show_setup: _show_setup end { 
#		::io(::join_path(::project_dir(),  ) > $contents;

group_rec: _group_rec end { $::tracker->set( rw => 'REC') }
group_mon: _group_mon end  { $::tracker->set( rw => 'MON') }
group_off: _group_mute end { $::tracker->set(rw => 'OFF') }

mixdown: _mixdown end { $::mixdown_track->set(rw => 'REC')}
mixplay: _mixplay end { $::mixdown_track->set(rw => 'MON');
						$::tracker->set(rw => 'OFF');
}
mixoff:  _mixoff  end { $::mixdown_track->set(rw => 'OFF');
						$::tracker->set(rw => 'MON')}

record: 'record' end {} # set to Tracker-Record 

exit: 'exit' end { ::save_state($::state_store_file); exit; }



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




wav: name { $::this_track = $::tn{$item{name}} if $::tn{$item{name}}  }

## we reach here
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


remove_mark: _remove_mark end { 
	$::this_mark->remove if ref $::this_mark =~ /Mark/;
}

mark: _mark end { ::mark_here() }

next_mark: _next_mark end { ::next_mark() }

previous_mark: _previous_mark end { ::previous_mark() }

mark_loop: _mark_loop end {}

name_mark: _name_mark name end {$::this_mark->set_name( $item{name}) }

list_marks: _list_marks end { 
	my $i = 0;
	map{ print( $_->time == $::this_mark->time ? q(*) : q()
	,join " ", $i++, sprintf("%.1f", $_->time)."s", $_->name, $/)  } 
		  #sort { $a->time <=> $b->time } 
		  @::Mark::all;
	print "now at ", sprintf("%.1f", ::eval_iam "getpos")  . "s", $/;
}
to_mark: _to_mark dd end {
	my @marks = ::Mark::all();
	$marks[$item{dd}]->jump_here;
}

to_mark: _to_mark name end { 
	my $mark = $::Mark::by_name{$item{name}};
	$mark->jump_here if defined $mark;
#	eval q( $mark->jump_here ) or $debug and print "jump failed: $@\n";
}

# okay to here
show_effects: _show_effects end {}

remove_effect: _remove_effect op_id(s) end {
	#print join $/, @{ $item{"op_id(s)"} }; 
	map{ print "removing op_id: $_\n"; ::remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	# map{ print "op_id: $_\n"; ::remove_effect( $_ )}  @{ $item{"op_id(s)"}} ;

}


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
group_version: _group_version dd end { $::tracker->set( version => $item{dd} )}


list_versions: _list_versions end { 
	print join " ", @{$::this_track->versions}, $/;
}


