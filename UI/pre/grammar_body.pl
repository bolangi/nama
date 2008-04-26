
# i'm a comment!

command: fail
end: /\s*$/
help: _help end { print "hello_from your command line gramar\n"; 1 }
help: _help number end { print "hello_from your command line gramar\n"; 1 }
fail: 'f' end { print "your command line gramar will get a zero\n"; 0 }

new_project: _new_project name end {
	::load_project( 
		name => ::remove_spaces($item{name}),
		create => 1,
	);
	print "created project: $::project_name\n";

1;
}

load_project: _load_project name end {
	::load_project( name => ::remove_spaces($item{name}) );
	1;
	print "loaded project: $::project_name\n";
}
save_state: _save_state name(?) end { 
	::save_state( $item{name} ); 
	print "saved state as $item{name}\n";
	1;}

add_track: _add_track wav channel(s?) end { 
	::add_track($item{wav}); 
	print "added track $item{wav}\n";
	1;
}

generate_setup: _generate_setup end { ::setup_transport(); 1 }

generate_and_connect_setup: _generate_and_connect_setup end { 
	::setup_transport() and ::connect_transport(); 1 }

connect_setup: _connect_setup end { ::connect_transport(); 1 }

disconnect_setup: _disconnect_setup end { ::disconnect_transport(); 1 }

renew_engine: _renew_engine end { ::new_engine(); 1  }

start: _start end { ::start_transport(); 1}
stop: _stop end { ::stop_transport(); 1}

list_marks: _list_marks end {'TODO' }

show_setup: _show_setup end { 	
	map { 	push @::format_fields,  
			$_->n,
			$_->active,
			$_->name,
			$_->rw,
			$_->rec_status,
			$_->ch_r,
			$_->ch_m,

		} ::Track::all;
		
	write; # using format at end of file UI.pm
	1;
}

tracker_rec: _tracker_rec end { $::tracker->set( rw => 'REC') }
tracker_mon: _tracker_mon end  { $::tracker->set( rw => 'MON') }
tracker_mute: _tracker_mute end { $::tracker->set(rw => 'MUTE') }

mixdown: _mixdown end { $::mixdown_track->set(rw => 'REC')}
mixplay: _mixplay end { $::mixdown_track->set(rw => 'MON');
						$::tracker->set(rw => 'MUTE');
}
mixoff:  _mixoff  end { $::mixdown_track->set(rw => 'MUTE');
						$::tracker->set(rw => 'MON')}


name: /\w+/

wav: name { $::select_track = $item{name} }

mix: 'mix' end {1}

norm: 'norm' end {1}

record: 'record' end {} # set to Tracker-Record 

exit: 'exit' end { ::save_state($::state_store_file); exit; }


channel: r | m

r: 'r' dd  { $::ti[$::select_track]->set(ch_r => $item{dd}) }
m: 'm' dd  { $::ti[$::select_track]->set(ch_m => $item{dd}) }


rec: 'rec' wav(s?) end { 
	map{$::ti[$::select_track]->set(rw => 'REC')} @{$item{wav}} 
}
mon: 'mon' wav(s?) end { 
	map{$::ti[$::select_track]->set(rw => 'MON')} @{$item{wav}} 
}
mute: 'mute' wav(s?) end { 
	map{$::ti[$::select_track]->set(rw => 'MUTE')} @{$item{wav}} 
}

mute: 'mute' end {$::ti[$::select_track]->set(rw => 'MUTE'); }
rec: 'rec' end {$::ti[$::select_track]->set(rw => 'REC'); }
mon: 'mon' end {$::ti[$::select_track]->set(rw => 'MON'); }


last: ('last' | '$' ) 

dd: /\d+/

