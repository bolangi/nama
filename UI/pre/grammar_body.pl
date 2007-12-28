new_project: _new_project name {
	$::project = $item{name};
	&::new_project;
	1;
}

load_project: _load_project name {
	$::project = $item{name};
	&::load_project unless $::project_name eq $item{name};
	1;
}

add_track: _add_track wav channel(s?) { 
	if ($::track_names{$item{wav}} ){
		print "Track name already in use.\n";
	} else {
		&::add_track($item{wav}) ;
		my %ch = ( @{$item{channel}} );	
		$ch{r} and $::state_c{$::i}->{ch_r} = $::ch{r};
		$ch{m} and $::state_c{$::i}->{ch_m} = $::ch{m};
		
	}
	1;
}

generate_setup: _generate_setup {}
setup: 'setup'{ &::setup_transport and &::connect_transport; 1}

list_marks: _list_marks {}

show_setup: _show_setup { 	
	map { 	push @::format_fields,  
			$_,
			$::state_c{$_}->{active},
			$::state_c{$_}->{file},
			$::state_c{$_}->{rw},
			&::rec_status($_),
			$::state_c{$_}->{ch_r},
			$::state_c{$_}->{ch_m},

		} sort keys %::state_c;
		
	write; # using format at end of file Flow.pm
				1;
}

name: /\w+/

wav: name


mix: 'mix' {1}

norm: 'norm' {1}

exit: 'exit' { &::save_state($::statestore); exit; }


channel: r | m

r: 'r' dd  { $::state_c{$::chain{$::select_track}}->{ch_r} = $item{dd} }
m: 'm' dd  { $::state_c{$::chain{$::select_track}}->{ch_m} = $item{dd} }


rec: 'rec' wav(s?) { 
	map{$::state_c{$::chain{$_}}->{rw} = q(rec)} @{$item{wav}} 
}
mon: 'mon' wav(s?) { 
	map{$::state_c{$::chain{$_}}->{rw} = q(mon)} @{$item{wav}} 
}
mute: 'mute' wav(s?) { 
	map{$::state_c{$::chain{$_}}->{rw} = q(mute)} @{$item{wav}}  
}

mon: 'mon' {$::state_c{$::chain{$::select_track}} = q(mon); }

mute: 'mute' {$::state_c{$::chain{$::select_track}} = q(mute); }

rec: 'rec' {$::state_c{$::chain{$::select_track}} = q(rec); }

last: ('last' | '$' ) 

dd: /\d+/

