command: fail
end: /\s*$/
help: _help end { print "hello_from your command line gramar\n"; 1 }
fail: 'f' end { print "your command line gramar will get a zero\n"; 0 }

new_project: _new_project name end {
	::load_project( 
		name => ::remove_spaces($item{name}),
		create => 1,
	);

	1;
}

load_project: _load_project name end {
	::load_project( name => ::remove_spaces($item{name}) );
	1;
}

add_track: _add_track wav channel(s?) end { 
	if ($::track_names{$item{wav}} ){ 
		print "Track name already in use.\n";

	} else { ::add_track($item{wav})  }
	1;
}

generate_setup: _generate_setup end { ::setup_transport(); 1 }

generate_and_connect_setup: _generate_and_connect_setup end { 
	::setup_transport() and ::connect_transport(); 1 }

connect_setup: _connect_setup end { ::connect_transport(); 1 }

disconnect_setup: _disconnect_setup end { ::disconnect_transport(); 1 }

save_setup: _save_setup end { ::save_state($::state_store_file); 1 }

list_marks: _list_marks end {}

show_setup: _show_setup end { 	
	map { 	push @::format_fields,  
			$_,
			$::state_c{$_}->{active},
			$::state_c{$_}->{file},
			$::state_c{$_}->{rw},
			&::rec_status($_),
			$::state_c{$_}->{ch_r},
			$::state_c{$_}->{ch_m},

		} sort keys %::state_c;
		
	write; # using format at end of file UI.pm
	1;
}

name: /\w+/

wav: name { $::select_track = $item{name} }

mix: 'mix' end {1}

norm: 'norm' end {1}

record: 'record' end {} # set to Tracker-Record 

exit: 'exit' end { ::save_state($::state_store_file); exit; }


channel: r | m

r: 'r' dd  { $::state_c{$::chain{$::select_track}}->{ch_r} = $item{dd} }
m: 'm' dd  { $::state_c{$::chain{$::select_track}}->{ch_m} = $item{dd} }


rec: 'rec' wav(s?) end { 
	map{$::state_c{$::chain{$::select_track}}->{rw} = "REC"} @{$item{wav}} 
}
mon: 'mon' wav(s?) end { 
	map{$::state_c{$::chain{$::select_track}}->{rw} = "MON"} @{$item{wav}} 
}
mute: 'mute' wav(s?) end { 
	map{$::state_c{$::chain{$::select_track}}->{rw} = "MUTE"} @{$item{wav}}  
}

mute: 'mute' end {$::state_c{$::chain{$::select_track}} = "MUTE"; }

mon: 'mon' end {$::state_c{$::chain{$::select_track}} = "MON"; }

rec: 'rec' end {$::state_c{$::chain{$::select_track}} = "REC"; }


last: ('last' | '$' ) 

dd: /\d+/

