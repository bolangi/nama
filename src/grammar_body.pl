# regex contraining of values
key: /\w+/
someval: /[\w.+-]+/
sign: /[+-]/
op_id: /[A-Z]+/
parameter: /\d+/
value: /[\d\.eE+-]+/ # -1.5e-6
last: ('last' | '$' ) 
dd: /\d+/
name: /[\w:]+\/?/
name2: /[\w-]+/
name3: /\S+/
modifier: 'audioloop' | 'select' | 'reverse' | 'playat' | value
nomodifiers: _nomodifiers end { $::this_track->set(modifiers => ""); }
end: /[;\s]*$/ 
exit: _exit end { ::save_state(); CORE::exit }
help_effect: _help_effect name end { ::Text::help_effect($item{name}) }
find_effect: _find_effect name3(s) { ::Text::find_effect(@{$item{"name3(s)"}})}
help: _help 'yml' end { ::pager($::commands_yml)}
help: _help name2  { ::Text::help($item{name2}) }
help: _help end { print $::help_screen }
project_name: _project_name end { print "project name: ", $::project_name, $/ }
create_project: _create_project name end { ::Text::t_create_project $item{name} }

list_projects: _list_projects end { ::list_projects() }

load_project: _load_project name end {
	::Text::t_load_project $item{name} 
}
save_state: _save_state name end { ::save_state( $item{name} ); }
save_state: _save_state end { ::save_state() }


get_state: _get_state name end {
 	::load_project( 
 		name => $::project_name,
 		settings => $item{name}
 		);
 	}
get_state: _get_state end {
 	::load_project( 
 		name => $::project_name,
 		);
 	}
getpos: _getpos end {  
	print ::d1( ::eval_iam q(getpos) ), $/; }
setpos: _setpos value end {
	::set_position($item{value});
}
forward: _forward value {
	::forward( $item{value} )
}
rewind: _rewind value {
	::rewind( $item{value} )
}

add_track: _add_track name(s) end { ::add_track(@{$item{'name(s)'}}); }

set_track: _set_track key someval end {
	 $::this_track->set( $item{key}, $item{someval} );
}
dump_track: _dump_track { ::pager($::this_track->dump) }

dump_group: _dump_group { ::pager($::tracker->dump) }

dump_all: _dump_all { ::dump_all() }

remove_track: _remove_track name end {
	$::tn{ $item{name} }->set(hide => 1); }

generate: _generate end { ::generate_setup(); }

arm: _arm end { ::arm() }

connect: _connect end { ::connect_transport(); }

disconnect: _disconnect end { ::disconnect_transport(); }

renew_engine: _renew_engine end { ::new_engine(); }
engine_status: _engine_status end { print(::eval_iam
q(engine-status));print $/ }

start: _start end { ::start_transport(); }
stop: _stop end { ::stop_transport(); }

ecasound_start: _ecasound_start end { ::eval_iam("stop") }
ecasound_stop: _ecasound_stop  end { ::eval_iam("start") }

show_tracks: _show_tracks end { 	

	::Text::show_tracks ( ::Track::all );
	use warnings; 
	no warnings qw(uninitialized); 
	print $/, "Group control", " " x 8, 
	  $::tracker->rw, " " x 24 , $::tracker->version, $/, $/;
}


modifiers: _modifiers modifier(s) end {
 	 $::this_track->set(modifiers => (join q(,),
	 @{$item{"modifier(s)"}}, q() ))
}

modifiers: _modifiers end { print $::this_track->modifiers, $/; }
	
show_chain_setup: _show_chain_setup { ::show_chain_setup(); }

show_io: _show_io { ::show_io() }


show_track: _show_track end {
	::Text::show_tracks($::this_track);
	::Text::show_effects();
	::Text::show_versions();
	::Text::show_modifiers();
}
show_track: _show_track name end { 
 	::Text::show_tracks( $::tn{$item{name}} ) if $::tn{$item{name}}
}
show_track: _show_track dd end {  
	::Text::show_tracks( $::ti[$item{dd}] ) if $::ti[$item{dd}]
}
	
#show_setup: _show_setup end { 
#		::io(::join_path(::project_dir(),  ) > $contents;

group_rec: _group_rec end { ::Text::group_rec() }
group_mon: _group_mon end  { ::Text::group_mon() }
group_off: _group_off end { ::Text::group_off() }

mixdown: _mixdown end { ::Text::mixdown()}
mixplay: _mixplay end { ::Text::mixplay() }
mixoff:  _mixoff  end { ::Text::mixoff() }

exit: 'exit' end { ::save_state($::state_store_file); exit; }

source: _source name {
	my $old_source = $::this_track->source;
	my $new_source = $::this_track->source($item{name});
	my $object = ::Track::input_object( $new_source );
	if ( $old_source  eq $new_source ){
		print $::this_track->name, ": input unchanged, $object\n";
	} else {
		print $::this_track->name, ": input set to $object\n";
	}
}
source: _source end { 
	my $source = $::this_track->source;
	my $object = ::Track::input_object( $source );
	print $::this_track->name, ": input from $object.\n";
}
send: _send name { $::this_track->set_send($item{name}) }

send: _send end { 
	if ( ! $::this_track->send){
		print $::this_track->name, ": no auxilary output.\n";
		return;
	}
	my $object = $::this_track->output_object;
	print $::this_track->name, ": auxilary output to $object.\n";
}

stereo: _stereo { $::this_track->set(ch_count => 2) }
mono:   _mono   { $::this_track->set(ch_count => 1) }

off: 'off' end {$::this_track->set_off() }
rec: 'rec' end { $::this_track->set_rec() }
mon: 'mon' end {$::this_track->set_mon() }

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

mute: _mute end { ::mute() }

unmute: _unmute end { ::unmute() }
solo: _solo end { ::solo() }

all: _all end { ::all()  }

unity: _unity end { $::copp{ $::this_track->vol }->[0] = 100;
				::sync_effect_param( $::this_track->vol, 0);
}

pan: _pan dd end { $::copp{ $::this_track->pan }->[0] = $item{dd};
	my $current = $::copp{ $::this_track->pan }->[0];
	$::this_track->set(old_pan_level => $current);
				::sync_effect_param( $::this_track->pan, 0);

} 
pan: _pan '+' dd end { $::copp{ $::this_track->pan }->[0] += $item{dd} ;
	my $current = $::copp{ $::this_track->pan }->[0];
	$::this_track->set(old_pan_level => $current);
				::sync_effect_param( $::this_track->pan, 0);
} 
pan: _pan '-' dd end { $::copp{ $::this_track->pan }->[0] -= $item{dd} ;
	my $current = $::copp{ $::this_track->pan }->[0];
	$::this_track->set(old_pan_level => $current);
				::sync_effect_param( $::this_track->pan, 0);
} 
pan: _pan end { print $::copp{$::this_track->pan}[0], $/ }

pan_right: _pan_right   end { 
	$::copp{ $::this_track->pan }->[0] = 100;
				::sync_effect_param( $::this_track->pan, 0);
}
pan_left:  _pan_left end { $::copp{ $::this_track->pan }->[0] = 0; 
				::sync_effect_param( $::this_track->pan, 0);
}
pan_center: _pan_center end { $::copp{ $::this_track->pan }->[0] = 50   ;
				::sync_effect_param( $::this_track->pan, 0);
}
pan_back:  _pan_back end {
	$::copp{ $::this_track->pan }->[0] = $::this_track->old_pan_level;

}
remove_mark: _remove_mark dd end {
	my @marks = ::Mark::all();
	$marks[$item{dd}]->remove if defined $marks[$item{dd}];
}

remove_mark: _remove_mark name end { 
	my $mark = $::Mark::by_name{$item{name}};
	$mark->remove if defined $mark;
#	eval q( $mark->jump_here ) or $debug and print "jump failed: $@\n";
}
	
remove_mark: _remove_mark end { 
	return unless (ref $::this_mark) =~ /Mark/;
	$::this_mark->remove;
}
	

mark: _mark name end { ::drop_mark $item{name}  }
mark: _mark end {  ::drop_mark()  }

next_mark: _next_mark end { ::next_mark() }

previous_mark: _previous_mark end { ::previous_mark() }

loop_enable: _loop_enable someval(s) end {
	my @new_endpoints = @{ $item{"someval(s)"}}; # names or indexes of marks
	#print join $/, @new_endpoints;
	$::loop_enable = 1;
	@::loop_endpoints = (@new_endpoints, @::loop_endpoints); 
	@::loop_endpoints = @::loop_endpoints[0,1];
}
loop_disable: _loop_disable end {
	$::loop_enable = 0;
}
	
name_mark: _name_mark name end {$::this_mark->set_name( $item{name}) }

list_marks: _list_marks end { 
	my $i = 0;
	map{ print( $_->time == $::this_mark->time ? q(*) : q()
	,join " ", $i++, sprintf("%.1f", $_->time), $_->name, $/)  } 
		  #sort { $a->time <=> $b->time } 
		  @::Mark::all;
	my $start = my $end = "undefined";
	print "now at ", sprintf("%.1f", ::eval_iam "getpos"), $/;

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

show_effects: _show_effects end {}

remove_effect: _remove_effect op_id(s) end {
	#print join $/, @{ $item{"op_id(s)"} }; 
	map{ print "removing effect id: $_\n"; ::remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	# map{ print "op_id: $_\n"; ::remove_effect( $_ )}  @{ $item{"op_id(s)"}} ;

}

add_ctrl: _add_ctrl parent name value(s?) end {
	my $code = $item{name};
	my $parent = $item{parent};
	my $values = $item{"value(s?)"};
	#print "values: " , ref $values, $/;
	#print join ", ", @{$values} if $values;
	::Text::t_add_ctrl $parent, $code, $values;
}
parent: op_id
add_effect: _add_effect name value(s?)  end { 
	my $code = $item{name};
	my $values = $item{"value(s?)"};
	::Text::t_add_effect $code, $values;
}

modify_effect: _modify_effect op_id parameter sign(?) value end {

		#print join $/, %item, $/;
		$item{parameter}--; # user's one-based indexing to our zero-base
		my $new_value = $item{value}; 

		if ($item{"sign(?)"} and @{ $item{"sign(?)"} }) {
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
group_version: _group_version end { 
	use warnings;
	no warnings qw(uninitialized);
	print $::tracker->version, $/ }

group_version: _group_version dd end { $::tracker->set( version => $item{dd} )}

bunch: _bunch name(s?) { ::Text::bunch( @{$item{'name(s?)'}} ) }

list_versions: _list_versions end { 
	print join " ", @{$::this_track->versions}, $/;
}

ladspa_register: _ladspa_register end { ::pager( ::eval_iam("ladspa-register")) }
preset_register: _preset_register end { ::pager( ::eval_iam("preset-register"))}
ctrl_register: _ctrl_register end { ::pager( ::eval_iam("ctrl-register"))}

preview: _preview { ::preview() }

normalize: _normalize { $::this_track->normalize }
fixdc: _fixdc { $::this_track->fixdc}
