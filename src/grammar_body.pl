key: /\w+/ 			# word characters {1,} 
					# used in: set_track

someval: /[\w.+-]+/ # [word character, period, plus, minus] {1,}
					# used in: set_track, loop_enable
sign: '+' | '-' | '*' | '/' 
					# [plus, minus, times, divide] {1}
value: /[+-]?([\d_]+(\.\d*)?|\.\d+)([eE][+-]?\d+)?/
					# used in: mark times and effect_parameter values
					# optional sign
					# ( 	digits/underscores {1,}
					# 		optional ( decimal point, optional digits )
					# ) or ( decimal point, digits{1,} )
					# optional: (	exponent e/E
					# 				optional sign
					# 				digits{1,}
					# 			)

float: /\d+\.\d+/   # used in: shift_track (start_position)
					# digit{1,}
					# decimal point
					# digit{1,}

op_id: /[A-Z]+/		# capital letters {1,}
parameter: /\d+/	# digits {1,}
# last: ('last' | '$' ) # word last or dollar sign {1}
					# UNUSED
dd: /\d+/			# digits {1,}
jack_port: /\w[-+:. \w]+/ 
					# used in: source
					# word character
					# [plus, minus, colon, period, space, word char]{1,}
name: /\w[\w:,]*\/?/ # word character 
					 # [word character, comma, colon]{0,}
					 # optional slash
					 # used in: help_effect, save_state, create_project
					 # get_state
					 # link_track (too flexible?) show_track
					 # set_send
					 # remove_mark new_mark name_mark to_mark
					 # add_controller add_effect append_effect insert_effect
					 # new_effect_chain add_effect_chain list_effect_chains
					 # delete_effect_chain overwrite_effect_chain
name2: /[\w\-+:]+/ # word characters, +, -, :
					# used in: help, do_script
name3: /\S+/		# non-space characters
					# used in: load_project
name4: /\w+/		# word characters
					# used in: bunch_name, effect_profile,
					# existing_effect_profile

marktime: /\d+\.\d+/ # decimal required
markname: /\w+/ { 	 # word characters
	print("$item[1]}: non-existent mark name. Skipping\n"), return undef 
		unless $::Mark::by_name{$item[1]};
	$item[1];
}
#region_default_end: 'END' | ''
path: /(["'])[\w-\. \/]+$1/ # used in: import_audio
					# single- or double-quote
					# [word char, dot, space, hyphen, slash]{1,}
					# close quote

path: /~?[\w\-\.\/]+/ # optional tilde [word char, dot, hyphen, slash]{1,}
modifier: 'audioloop' | 'select' | 'reverse' | 'playat' | value
end: /[;\s]*$/ 		# [space char, semicolon]{0,}
					# end-of-string

help_effect: _help_effect name end { ::Text::help_effect($item{name}) ; 1}
find_effect: _find_effect name3(s) { 
	::Text::find_effect(@{$item{"name3(s)"}}); 1}
help: _help 'yml' end { ::pager($::commands_yml); 1}
help: _help name2  { ::Text::help($item{name2}) ; 1}
help: _help end { print $::help_screen ; 1}
project_name: _project_name end { 
	print "project name: ", $::project_name, $/; 1}
create_project: _create_project name end { 
	::Text::t_create_project $item{name} ; 1}
list_projects: _list_projects end { ::list_projects() ; 1}
load_project: _load_project name3 end {
	::Text::t_load_project $item{name3} ; 1}
save_state: _save_state name end { ::save_state( $item{name}); 1}
save_state: _save_state end { ::save_state(); 1}
get_state: _get_state name end {
 	::load_project( 
 		name => $::project_name,
 		settings => $item{name}
 		); 1}
get_state: _get_state end {
 	::load_project( name => $::project_name,) ; 1}
getpos: _getpos end {  
	print ::d1( ::eval_iam q(getpos) ), $/; 1}
setpos: _setpos value end {
	::set_position($item{value}); 1}
forward: _forward value end {
	::forward( $item{value} ); 1}
rewind: _rewind value end {
	::rewind( $item{value} ); 1}
to_start: _to_start end { ::to_start(); 1 }
to_end: _to_end end { ::to_end(); 1 }
add_track: _add_track name2(s) end {
	::add_track(@{$item{'name2(s)'}}); 1}
add_tracks: _add_tracks name2(s) end {
	map{ ::add_track($_)  } @{$item{'name2(s)'}}; 1}
# set bus Brass
set_track: _set_track 'bus' existing_bus_name end {
	$::this_track->set( group => $item{existing_bus_name}); 1
} 
set_track: _set_track key someval end {
	 $::this_track->set( $item{key}, $item{someval} ); 1}
dump_track: _dump_track end { ::pager($::this_track->dump); 1}
dump_group: _dump_group end { ::pager($::main->dump); 1}
dump_all: _dump_all end { ::dump_all(); 1}
remove_track: _remove_track end { 
	$::this_track->remove; 
	1;
}
link_track: _link_track name target project end {
	::add_track_alias_project($item{name}, $item{target}, $item{project}); 1
}
link_track: _link_track name target end {
	::add_track_alias($item{name}, $item{target}); 1
}
target: name
project: name
set_region: _set_region beginning ending end { 
	::set_region( @item{ qw( beginning ending ) } );
	1;
}
set_region: _set_region beginning end { ::set_region( $item{beginning}, 'END' );
	1;
}
remove_region: _remove_region end { ::remove_region(); 1; }
new_region: _new_region beginning ending name(?) end {
	my ($name) = @{$item{'name(?)'}};
	::new_region(@item{qw(beginning ending)}, $name); 1
}

shift_track: _shift_track start_position end {
	my $pos = $item{start_position};
	if ( $pos =~ /\d+\.\d+/ ){
		print $::this_track->name, ": Shifting start time to $pos seconds\n";
		$::this_track->set(playat => $pos);
		1;
	}
	# elsif ( pos =~ /^\d+$/ ) { # skip the mark index case
	elsif ( $::Mark::by_name{$pos} ){
		my $time = ::Mark::mark_time( $pos );
		print $::this_track->name, 
			qq(: Shifting start time to mark "$pos", $time seconds\n);
		$::this_track->set(playat => $time);
		1;
	} else { print 
	"Shift value is neither decimal nor mark name. Skipping.\n";
	0;
	}
}

start_position:  float | mark_name
mark_name: name

unshift_track: _unshift_track end {
	$::this_track->set(playat => undef)
}
beginning: marktime | markname
ending: 'END' | marktime | markname 
generate: _generate end { ::generate_setup(); 1}
arm: _arm end { ::arm(); 1}
connect: _connect end { ::connect_transport(); 1}
disconnect: _disconnect end { ::disconnect_transport(); 1}
engine_status: _engine_status end { 
	print(::eval_iam q(engine-status)); print "\n" ; 1}
start: _start end { ::start_transport(); 1}
stop: _stop end { ::stop_transport(); 1}
ecasound_start: _ecasound_start end { ::eval_iam("stop"); 1}
ecasound_stop: _ecasound_stop  end { ::eval_iam("start"); 1}
show_tracks: _show_tracks end { 	
	::pager( ::Text::show_tracks ( ::Track::all() ) );
	1;
}
modifiers: _modifiers modifier(s) end {
 	$::this_track->set(modifiers => (join q(,),
	@{$item{"modifier(s)"}}, q() ));
	1;}

modifiers: _modifiers end { print $::this_track->modifiers, "\n"; 1}
nomodifiers: _nomodifiers end { $::this_track->set(modifiers => ""); 1}
show_chain_setup: _show_chain_setup { ::pager($::chain_setup); 1}
show_io: _show_io { ::show_io(); 1}
show_track: _show_track end {
	my $output = ::Text::show_tracks($::this_track);
	$output .= ::Text::show_effects();
	$output .= ::Text::show_versions();
	$output .= ::Text::show_send();
	$output .= ::Text::show_bus();
	$output .= ::Text::show_modifiers();
	$output .= join "", "Signal width: ", ::width($::this_track->width), "\n";
	$output .= ::Text::show_region();
	$output .= ::Text::show_effect_chain_stack();
	::pager( $output );
	1;}
show_track: _show_track name end { 
 	::pager( ::Text::show_tracks( 
	$::tn{$item{name}} )) if $::tn{$item{name}};
	1;}
show_track: _show_track dd end {  
	::pager( ::Text::show_tracks( $::ti{$item{dd}} )) if
	$::ti{$item{dd}};
	1;}

show_mode: _show_mode end { print STDOUT ::Text::show_status; 1}
group_rec: _group_rec end { ::Text::group_rec(); 1}
group_mon: _group_mon end  { ::Text::group_mon(); 1}
group_off: _group_off end { ::Text::group_off(); 1}
mixdown: _mixdown end { ::Text::mixdown(); 1}
mixplay: _mixplay end { ::Text::mixplay(); 1}
mixoff:  _mixoff  end { ::Text::mixoff(); 1}
automix: _automix { ::automix(); 1 }
autofix_tracks: _autofix_tracks { ::command_process("for mon; fixdc; normalize"); 1 }
master_on: _master_on end { ::master_on(); 1 }
master_off: _master_off end { ::master_off(); 1 }

exit: _exit end {   ::save_state($::state_store_file); 
					::cleanup_exit();
                    1}	

source: _source portsfile end { $::this_track->set_source($item{portsfile}); 1 }
portsfile: /\w+\.ports/
source: _source 'jack' end { $::this_track->set_source('jack'); 1 }
source: _source dd end { $::this_track->set_source( $item{dd} ); 1 }
source: _source jack_port end { $::this_track->set_source( $item{jack_port} ); 1 }
source: _source end { 
	my $source = $::this_track->source;
	my $object = $::this_track->input_object;
	if ( $source ) { 
		print $::this_track->name, ": input from $object.\n";
	} else {
		print $::this_track->name, ": REC disabled. No source found.\n";
	}
	1;
}
send: _send name { $::this_track->set_send($item{name}); 1}
send: _send end { $::this_track->set_send(); 1}
remove_send: _remove_send end {
					$::this_track->set(send_type => undef);
					$::this_track->set(send_id => undef); 1
}
stereo: _stereo { 
	$::this_track->set(width => 2); 
	print $::this_track->name, ": setting to stereo\n";
	1;
}
mono: _mono { 
	$::this_track->set(width => 1); 
	print $::this_track->name, ": setting to mono\n";
	1; }

off: 'off' end {$::this_track->set_off(); 1}
rec: 'rec' end { $::this_track->set_rec(); 1}
mon: 'mon' end {$::this_track->set_mon(); 1}
rec_defeat: _rec_defeat end { 
	$::this_track->set(rec_defeat => !  $::this_track->rec_defeat);
	print $::this_track->name, ": WAV record ",
		($::this_track->rec_defeat ? "disabled" : "enabled"), $/;
}

set_version: _set_version dd end { $::this_track->set_version($item{dd}); 1}

vol: _vol sign(?) value end { 
	$::this_track->vol or 
		print( $::this_track->name . ": no volume control available\n"), return;
	$item{sign} = undef;
	$item{sign} = $item{'sign(?)'}->[0] if $item{'sign(?)'};
	::modify_effect 
		$::this_track->vol,
		0,
		$item{sign},
		$item{value};
	1;
} 
vol: _vol end { print $::copp{$::this_track->vol}[0], "\n" ; 1}

mute: _mute end { $::this_track->mute; 1}

unmute: _unmute end { $::this_track->unmute; 1}
solo: _solo end { ::solo(); 1}
all: _all end { ::all() ; 1}


unity: _unity end { 
	::effect_update_copp_set( $::this_track->vol, 0, 100);
	1;}

pan: _pan dd end { 
	::effect_update_copp_set( $::this_track->pan, 0, $item{dd});
	1;} 
pan: _pan sign dd end {
	::modify_effect( $::this_track->pan, 0, $item{sign}, $item{dd} );
	1;} 
pan: _pan end { print $::copp{$::this_track->pan}[0], "\n"; 1}
pan_right: _pan_right end   { ::pan_check( 100 ); 1}
pan_left:  _pan_left  end   { ::pan_check(   0 ); 1}
pan_center: _pan_center end { ::pan_check(  50 ); 1}
pan_back:  _pan_back end {
	my $old = $::this_track->old_pan_level;
	if (defined $old){
		::effect_update_copp_set(
			$::this_track->pan,	# id
			0, 					# parameter
			$old,				# value
		);
		$::this_track->set(old_pan_level => undef);
	}
1;}
remove_mark: _remove_mark dd end {
	my @marks = ::Mark::all();
	$marks[$item{dd}]->remove if defined $marks[$item{dd}];
	1;}
remove_mark: _remove_mark name end { 
	my $mark = $::Mark::by_name{$item{name}};
	$mark->remove if defined $mark;
#	eval q( $mark->jump_here ) or $debug and print "jump failed: $@\n";
	1;}
remove_mark: _remove_mark end { 
	return unless (ref $::this_mark) =~ /Mark/;
	$::this_mark->remove;
	1;}
new_mark: _new_mark name end { ::drop_mark $item{name}; 1}
new_mark: _new_mark end {  ::drop_mark(); 1}
next_mark: _next_mark end { ::next_mark(); 1}
previous_mark: _previous_mark end { ::previous_mark(); 1}
loop_enable: _loop_enable someval(s) end {
	my @new_endpoints = @{ $item{"someval(s)"}}; # names or indexes of marks
	#print join $/, @new_endpoints;
	$::loop_enable = 1;
	@::loop_endpoints = (@new_endpoints, @::loop_endpoints); 
	@::loop_endpoints = @::loop_endpoints[0,1];
	1;}
loop_disable: _loop_disable end { $::loop_enable = 0; 1}
name_mark: _name_mark name end {$::this_mark->set_name( $item{name}); 1}
list_marks: _list_marks end { 
	my $i = 0;
	map{ print( $_->time == $::this_mark->time ? q(*) : q()
	,join " ", $i++, sprintf("%.1f", $_->time), $_->name, "\n")  } 
		  #sort { $a->time <=> $b->time } 
		  @::Mark::all;
	my $start = my $end = "undefined";
	print "now at ", sprintf("%.1f", ::eval_iam "getpos"), "\n";
	1;}
to_mark: _to_mark dd end {
	my @marks = ::Mark::all();
	$marks[$item{dd}]->jump_here;
	1;}
to_mark: _to_mark name end { 
	my $mark = $::Mark::by_name{$item{name}};
	$mark->jump_here if defined $mark;
#	eval q( $mark->jump_here ) or $debug and print "jump failed: $@\n";
	1;}
modify_mark: _modify_mark sign value end {
	my $newtime = eval($::this_mark->time . $item{sign} . $item{value});
	$::this_mark->set( time => $newtime );
	print $::this_mark->name, ": set to ", ::d2( $newtime), "\n";
	::eval_iam("setpos $newtime");
	1;
	}
modify_mark: _modify_mark value end {
	$::this_mark->set( time => $item{value} );
	print $::this_mark->name, ": set to ", ::d2( $item{value}), "\n";
	::eval_iam("setpos $item{value}");
	1;
	}		
remove_effect: _remove_effect op_id(s) end {
	#print join $/, @{ $item{"op_id(s)"} }; 
	::mute();
	map{ print "removing effect id: $_\n"; ::remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	# map{ print "op_id: $_\n"; ::remove_effect( $_ )}  @{ $item{"op_id(s)"}} ;
	::sleeper(0.5);
	::unmute();
	1;}

add_controller: _add_controller parent name value(s?) end {
	my $code = $item{name};
	my $parent = $item{parent};
	my $values = $item{"value(s?)"};
	#print "values: " , ref $values, $/;
	#print join ", ", @{$values} if $values;
	::Text::t_add_ctrl($parent, $code, $values);
	1;}
parent: op_id
add_effect: _add_effect name value(s?)  end { 
	my $code = $item{name};
	my $values = $item{"value(s?)"};
	my $before = $::this_track->vol;
	::Text::t_insert_effect($before, $code, $values);
 	1;}

append_effect: _append_effect name value(s?) end {
	my $code = $item{name};
	my $values = $item{"value(s?)"};
 	::Text::t_add_effect($::this_track, $code, $values);
 	1;}

insert_effect: _insert_effect before name value(s?) end {
	my $before = $item{before};
	my $code = $item{name};
	my $values = $item{"value(s?)"};
	#print "values: " , ref $values, $/;
	print join ", ", @{$values} if $values;
	::Text::t_insert_effect($before, $code, $values);
	1;}

before: op_id

modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) value end {
	map{ my $op_id = $_;
		map{ my $parameter = $_;
			 $parameter--;
			 ::effect_update_copp_set( $op_id, $parameter, $item{value});
		} @{$item{"parameter(s)"}};
	} @{$item{"op_id(s)"}};
	1;
}
modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) sign value end {
	map{ my $op_id = $_;
		map{ 	my $parameter = $_;
				$parameter--;
				::modify_effect($op_id, $parameter, @item{qw(sign value)}); 
		} @{$item{"parameter(s)"}};
	} @{$item{"op_id(s)"}};
	1;
}
group_version: _group_version end { 
	use warnings;
	no warnings qw(uninitialized);
	print $::main->version, "\n" ; 1}
group_version: _group_version dd end { 
	my $n = $item{dd};
	$n = undef if $n == 0;
	$::main->set( version => $n ); 1}
new_bunch: _new_bunch name4(s) { ::Text::bunch( @{$item{'name4(s)'}}); 1}
list_bunches: _list_bunches end { ::Text::bunch(); 1}
remove_bunches: _remove_bunches name4(s) { 
 	map{ delete $::bunch{$_} } @{$item{'name4(s)'}}; 1}
add_to_bunch: _add_to_bunch name4(s) end { ::Text::add_to_bunch( @{$item{'name4(s)'}});1 }
list_versions: _list_versions end { 
	print join " ", @{$::this_track->versions}, "\n"; 1}
ladspa_register: _ladspa_register end { 
	::pager( ::eval_iam("ladspa-register")); 1}
preset_register: _preset_register end { 
	::pager( ::eval_iam("preset-register")); 1}
ctrl_register: _ctrl_register end { 
	::pager( ::eval_iam("ctrl-register")); 1}
preview: _preview { ::set_preview_mode(); 1}
doodle: _doodle { ::set_doodle_mode(); 1 }
normalize: _normalize { $::this_track->normalize; 1}
fixdc: _fixdc { $::this_track->fixdc; 1}
destroy_current_wav: _destroy_current_wav { ::destroy_current_wav(); 1 }
memoize: _memoize { 
	package ::Wav;
	$::memoize = 1;
	memoize('candidates'); 1
}
unmemoize: _unmemoize {
	package ::Wav;
	$::memoize = 0;
	unmemoize('candidates'); 1
}
import_audio: _import_audio path frequency end {
	$::this_track->import_audio( $item{path}, $item{frequency}); 1;
}
import_audio: _import_audio path end {
	$::this_track->import_audio( $item{path}); 1;
}
frequency: value
list_history: _list_history end {
	my @history = $::term->GetHistory;
	my %seen;
	map { print "$_\n" unless $seen{$_}; $seen{$_}++ } @history
}
main_off: _main_off end { 
	$::main_out = 0;
1;
} 
main_on: _main_on end { 
	$::main_out = 1;
1;
} 
add_send_bus_cooked: _add_send_bus_cooked bus_name destination {
	::add_send_bus( $item{bus_name}, $item{destination}, 'cooked' );
	1;

}
add_send_bus_raw: _add_send_bus_raw bus_name destination end {
	::add_send_bus( $item{bus_name}, $item{destination}, 'raw' );
	1;
}
add_sub_bus: _add_sub_bus bus_name destination(?) end { 
	my $dest_id = $item{'destination(?)'}->[0];
	my $dest_type = $dest_id ?  ::dest_type($dest_id) : undef;
	::add_sub_bus( $item{bus_name}, $dest_type, $dest_id); 1
}

existing_bus_name: bus_name {
	if ( $::Bus::by_name{$item{bus_name}} ){  $item{bus_name} }
	else { print("$item{bus_name}: no such bus\n"); undef }
}

bus_name: /[A-Z]\w+/

destination: /\d+/ | /loop,\w+/ | name2
# digits: soundcard channel
# loop,identifier: loop device
# name2: track name

remove_bus: _remove_bus existing_bus_name end { 
	$::Bus::by_name{$item{existing_bus_name}}->remove; 1; 
}
update_send_bus: _update_send_bus existing_bus_name end {
 	::update_send_bus( $item{existing_bus_name} );
 	1;
}
set_bus: _set_bus key someval { $::Bus::by_name{$::this_bus}->set($item{key} => $item{someval}); 1 }

change_bus: _change_bus existing_bus_name { $::this_bus = $item{existing_bus_name} }

list_buses: _list_buses end { ::pager(map{ $_->dump } ::Bus::all()) }
add_insert_cooked: _add_insert_cooked send_id return_id(?) end {
	my $return_id = "@{$item{'return_id(?)'}}";
	my $send_id = $item{send_id};
	::add_insert_cooked($send_id, $return_id);
	1;
}
send_id: name
return_id: name

set_insert_wetness: _set_insert_wetness parameter end {
	my $p = $item{parameter};
	print ("wetness parameter must be an integer between 0 and 100\n"), return 1
		if ! ($p <= 100 and $p >= 0);
	my $i = $::this_track->inserts;
	print ("track '",$::this_track->n, "' has no insert.  Skipping.\n"),
		return 1 unless $i;
	$i->{wetness} = $p;
	::modify_effect($i->{wet_vol}, 0, undef, $p);
	::sleeper(0.1);
	::modify_effect($i->{dry_vol}, 0, undef, 100 - $p);
	1;
}

set_insert_wetness: _set_insert_wetness end {
	my $i = $::this_track->inserts;
	print ("track ",$::this_track->n, " has no insert.\n"), return 1 unless $i;
	 print "The insert is ", 
		$i->{wetness}, "% wet, ", (100 - $i->{wetness}), "% dry.\n";
}

remove_insert: _remove_insert end { 
	$::this_track->remove_insert;
	1;
}

cache_track: _cache_track end { ::cache_track($::this_track); 1 }
uncache_track: _uncache_track end { ::uncache_track($::this_track); 1 }
new_effect_chain: _new_effect_chain name op_id(s?) end {
	#print "name $item{name}, ops: ", @{$item{'op_id(s?)'}}, $/;
	::new_effect_chain($::this_track, $item{name}, @{ $item{'op_id(s?)'} });
	1;
}
add_effect_chain: _add_effect_chain name end {
	::add_effect_chain($::this_track, $item{name});
	1;
}
delete_effect_chain: _delete_effect_chain name(s) end {
	map{ delete $::effect_chain{$_} } @{ $item{'name(s)'} };
	1;
}
list_effect_chains: _list_effect_chains name(s?) end {
	::list_effect_chains( @{ $item{'name(s?)'} } ); 1;
}

    
bypass_effects:   _bypass_effects end { 
	::push_effect_chain($::this_track) and
	print $::this_track->name, ": bypassing effects\n"; 1}
restore_effects: _restore_effects end { 
	::restore_effects($::this_track) and
	print $::this_track->name, ": restoring effects\n"; 1}
overwrite_effect_chain: _overwrite_effect_chain name end {
	::overwrite_effect_chain($::this_track, $item{name}); 1;
}
bunch_name: name4 { 
	::is_bunch($item{name4}) 
		or print("$item{name4}: no such bunch name.\n"), return; 
	$item{name4};
}
effect_profile_name: name4
existing_effect_profile_name: name4 {
	print ("$item{name4}: no such effect profile\n"), return
		unless $::effect_profile{$item{name4}};
	$item{name4}
}
new_effect_profile: _new_effect_profile bunch_name effect_profile_name end {
	::new_effect_profile($item{bunch_name}, $item{effect_profile_name}); 1 }
#new_effect_profile: _new_effect_profile bunch_name end {
	#::new_effect_profile($item{bunch_name}, $item{bunch_name}); 1 }
delete_effect_profile: _delete_effect_profile existing_effect_profile_name end {
	::delete_effect_profile($item{existing_effect_profile_name}); 1 }
apply_effect_profile: _apply_effect_profile effect_profile_name end {
	::apply_effect_profile(\&::overwrite_effect_chain, $item{effect_profile_name}); 1 }
overlay_effect_profile: _overlay_effect_profile effect_profile_name end {
	::apply_effect_profile(\&::add_effect_chain, $item{effect_profile_name}); 1 }
list_effect_profiles: _list_effect_profiles end {
	::list_effect_profiles(); 1 }
do_script: _do_script name2 end { ::do_script($item{name2});1}
scan: _scan end { print "scanning ", ::this_wav_dir(), "\n"; ::rememoize() }
