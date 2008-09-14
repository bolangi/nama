# regex contraining of values
key: /\w+/
someval: /[\w.+-]+/
sign: /[+-]/
op_id: /[A-Z]+/
parameter: /\d+/
value: /[\d\.eE+-]+/ # -1.5e-6
last: ('last' | '$' ) 
dd: /\d+/
name: /[\w:]+/
modifier: 'audioloop' | 'select' | 'reverse' | 'playat' | value
nomodifiers: _nomodifiers end { $::this_track->set(modifiers => ""); }
asdf: 'asdf' { print "hello"}
command: fail
end: /\s*$/ 
end: ';' 
help: _help end { print $::help_screen }
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
	unless -d ::join_path ::project_root(), $untested; 
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
	print ::d1( ::eval_iam q(getpos) ), $/; }
setpos: _setpos value end {
	::eval_iam("setpos $item{value}");
}

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
engine_status: _engine_status end { print(::eval_iam
q(engine-status));print $/ }

start: _start end { ::start_transport(); }
stop: _stop end { ::stop_transport(); }

S: _S end { ::eval_iam("stop") }
T: _T end { ::eval_iam("start") }

show_tracks: _show_tracks end { 	

	::Text::show_tracks ( ::Track::all );
	use warnings; 
	no warnings qw(uninitialized); 
	print $/, " " x 7, "Group", " " x 9, $::tracker->rw, " " x 24 , $::tracker->version, $/;
}


modifiers: _modifiers modifier(s) end {
 	 $::this_track->set(modifiers => (join q(,),
	 @{$item{"modifier(s)"}}, q() ))
}

modifiers: _modifiers end { print $::this_track->modifiers, $/; }
	
	
show_chain_setup: _show_chain_setup {
	my $chain_setup;
	::io( ::join_path( ::project_dir(), $::chain_setup_file) ) > $chain_setup; 
	print $chain_setup, $/;
}

show_io: _show_io { print ::yaml_out( \%::inputs ),
::yaml_out( \%::outputs ); }

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
				print "Input switched to channel $::ch_r.\n";
				
				}
m: 'm' dd  {	
				$::this_track->set(ch_m => $item{dd}) ;
				$::ch_m = $item{dd};
				print "Output switched to channel $::ch_m.\n";
				
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

mute: _mute end {

	$::this_track->set(old_vol_level => $::copp{$::this_track->vol}[0])
		if ( $::copp{$::this_track->vol}[0]);  # non-zero volume
	$::copp{ $::this_track->vol }->[0] = 0;
	::sync_effect_param( $::this_track->vol, 0);
}
unmute: _unmute end {
	return if $::copp{$::this_track->vol}[0]; # if we are not muted
	return if ! $::this_track->old_vol_level;
	$::copp{$::this_track->vol}[0] = $::this_track->old_vol_level;
	$::this_track->set(old_vol_level => 0);
	::sync_effect_param( $::this_track->vol, 0);
}


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
	

mark: _mark end { $::ui->marker( ::mark_here() )  }

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


add_effect: _add_effect name value(s?)  end { 
#print join $/, %item;
#print "itemdd:", $item{"dd(s?)"} , ":\n";
#print "itemdd2:", $item{"dd"} , ":\n";
#print "ref:", ref $item{dd} , ":\n";

my $code = $item{name};
if ( $::effect_i{$code} ) {} # do nothing
elsif ( $::effect_j{$code} ) { $code = $::effect_j{$code} }
else { warn "effect code not found: $code\n"; return }
print "code: ", $code, $/;
	my %p = (
		chain => $::this_track->n,
		values => $item{"value(s?)"},
		type => $code,
		);
		print "adding effect\n";
		#print (::yaml_out(\%p));
	::add_effect( \%p );
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


list_versions: _list_versions end { 
	print join " ", @{$::this_track->versions}, $/;
}

ladspa_register: _ladspa_register end { print ::eval_iam("ladspa-register") }
preset_register: _preset_register end { print ::eval_iam("preset-register") }
ctrl_register: _ctrl_register end { print ::eval_iam("ctrl-register") }
project_name: _project_name end { print "project name: ", $::project_name, $/ }
