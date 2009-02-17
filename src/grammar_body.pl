# regex contraining of values
key: /\w+/
someval: /[\w.+-]+/
sign: '+' | '-' | '*' | '/'
value: /[+-]?([\d_]+(\.\d*)?|\.\d+)([eE][+-]?\d+)?/
op_id: /[A-Z]+/
parameter: /\d+/
#value: /\d+/
#value: /[\d\.eE+-]+/
last: ('last' | '$' ) 
dd: /\d+/
name: /[\w:]+\/?/
name2: /[\w-]+/
name3: /\S+/
path: /(["'])[\w-\. \/]+$1/
path: /[\w-\.\/]+/
modifier: 'audioloop' | 'select' | 'reverse' | 'playat' | value
nomodifiers: _nomodifiers end { $::this_track->set(modifiers => ""); 1}
end: /[;\s]*$/ 
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
load_project: _load_project name end {
	::Text::t_load_project $item{name} ; 1}
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
add_track: _add_track name(s) end {
	::add_track(@{$item{'name(s)'}}); 1}
set_track: _set_track key someval end {
	 $::this_track->set( $item{key}, $item{someval} ); 1}
dump_track: _dump_track end { ::pager($::this_track->dump); 1}
dump_group: _dump_group end { ::pager($::tracker->dump); 1}
dump_all: _dump_all end { ::dump_all(); 1}
#remove_track: _remove_track name end { $::tn{ $item{name} }->set(hide => 1); 1}
# remove_track: _remove_track name end { 
# 	my $track = $::tn{ $item{name} };
# 	print("$item{name}: unknown track... skipping.\n"), return
# 		if ! defined $track;
# 	$track->set(hide => 1); 
# 	#$::ui->remove_track_gui($track->n);
# 	1;
# }
generate: _generate end { ::generate_setup(); 1}
arm: _arm end { ::arm(); 1}
connect: _connect end { ::connect_transport(); 1}
disconnect: _disconnect end { ::disconnect_transport(); 1}
renew_engine: _renew_engine end { ::new_engine(); 1}
engine_status: _engine_status end { 
	print(::eval_iam q(engine-status)); print "\n" ; 1}
start: _start end { ::start_transport(); 1}
stop: _stop end { ::stop_transport(); 1}
ecasound_start: _ecasound_start end { ::eval_iam("stop"); 1}
ecasound_stop: _ecasound_stop  end { ::eval_iam("start"); 1}
show_tracks: _show_tracks end { 	
	::Text::show_tracks ( ::Track::all );
	use warnings; 
	no warnings qw(uninitialized); 
	print $/, "Group control", " " x 4, 
	  sprintf("%2d", $::tracker->version), " " x 2, $::tracker->rw,$/, $/;
	1;
}
modifiers: _modifiers modifier(s) end {
 	$::this_track->set(modifiers => (join q(,),
	@{$item{"modifier(s)"}}, q() ));
	1;}

modifiers: _modifiers end { print $::this_track->modifiers, "\n"; 1}
show_chain_setup: _show_chain_setup { ::show_chain_setup(); 1}
show_io: _show_io { ::show_io(); 1}
show_track: _show_track end {
	::Text::show_tracks($::this_track);
	::Text::show_effects();
	::Text::show_versions();
	::Text::show_modifiers();
	print "Signal width: ", ::width($::this_track->ch_count), "\n";
	1;}
show_track: _show_track name end { 
 	::Text::show_tracks( 
	$::tn{$item{name}} ) if $::tn{$item{name}};
	1;}
show_track: _show_track dd end {  
	::Text::show_tracks( $::ti[$item{dd}] ) if
	$::ti[$item{dd}];
	1;}
	
#show_setup: _show_setup end { 
#		::io(::join_path(::project_dir(),  ) > $contents;

group_rec: _group_rec end { ::Text::group_rec(); 1}
group_mon: _group_mon end  { ::Text::group_mon(); 1}
group_off: _group_off end { ::Text::group_off(); 1}
mixdown: _mixdown end { ::Text::mixdown(); 1}
mixplay: _mixplay end { ::Text::mixplay(); 1}
mixoff:  _mixoff  end { ::Text::mixoff(); 1}

exit: _exit end { ::save_state($::state_store_file); CORE::exit(); 1}
source: _source name { $::this_track->set_source( $item{name} ); 1 }
source: _source end { 
	my $source = $::this_track->source;
	my $object = ::Track::input_object( $source );
	if ( $source ) { 
		print $::this_track->name, ": input from $object.\n";
	} else {
		print $::this_track->name, ": REC disabled. No source found.\n";
	}
	1;
}
send: _send name { $::this_track->set_send($item{name}); 1}
send: _send end { $::this_track->set_send(); 1}

stereo: _stereo { 
	$::this_track->set(ch_count => 2); 
	print $::this_track->name, ": setting to stereo\n";
	1;
}
mono: _mono { 
	$::this_track->set(ch_count => 1); 
	print $::this_track->name, ": setting to mono\n";
	1; }

off: 'off' end {$::this_track->set_off(); 1}
rec: 'rec' end { $::this_track->set_rec(); 1}
mon: 'mon' end {$::this_track->set_mon(); 1}

set_version: _set_version dd end { $::this_track->set_version($item{dd}); 1}

vol: _vol sign(?) value end { 
	$item{sign} = undef;
	$item{sign} = $item{'sign(?)'}->[0] if $item{'sign(?)'};
	::modify_effect 
		$::this_track->vol,
		1,
		$item{sign},
		$item{value};
	1;
} 
vol: _vol end { print $::copp{$::this_track->vol}[0], "\n" ; 1}

mute: _mute end { ::mute(); 1}

unmute: _unmute end { ::unmute(); 1}
solo: _solo end { ::solo(); 1}
all: _all end { ::all() ; 1}

unity: _unity end { 
	$::copp{ $::this_track->vol }->[0] = 100;
	::sync_effect_param( $::this_track->vol, 0);
	1;}

pan: _pan dd end { $::copp{ $::this_track->pan }->[0] = $item{dd};
	::sync_effect_param( $::this_track->pan, 0);
	1;} 
pan: _pan '+' dd end { $::copp{ $::this_track->pan }->[0] += $item{dd} ;
	::sync_effect_param( $::this_track->pan, 0);
	1;} 
pan: _pan '-' dd end { $::copp{ $::this_track->pan }->[0] -= $item{dd} ;
	::sync_effect_param( $::this_track->pan, 0);
	1;} 
pan: _pan end { print $::copp{$::this_track->pan}[0], "\n"; 1}
pan_right: _pan_right end   { ::pan_check( 100 ); 1}
pan_left:  _pan_left  end   { ::pan_check(   0 ); 1}
pan_center: _pan_center end { ::pan_check(  50 ); 1}
pan_back:  _pan_back end {
	my $old = $::this_track->old_pan_level;
	if (defined $old){
		::effect_update_copp_set(
			$::this_track->n,	# chain
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
mark: _mark name end { ::drop_mark $item{name}; 1}
mark: _mark end {  ::drop_mark(); 1}
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
#show_effects: _show_effects end {; 1}

remove_effect: _remove_effect op_id(s) end {
	#print join $/, @{ $item{"op_id(s)"} }; 
	map{ print "removing effect id: $_\n"; ::remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	# map{ print "op_id: $_\n"; ::remove_effect( $_ )}  @{ $item{"op_id(s)"}} ;
	1;}

add_ctrl: _add_ctrl parent name value(s?) end {
	my $code = $item{name};
	my $parent = $item{parent};
	my $values = $item{"value(s?)"};
	#print "values: " , ref $values, $/;
	#print join ", ", @{$values} if $values;
	::Text::t_add_ctrl $parent, $code, $values;
	1;}
parent: op_id
add_effect: _add_effect name value(s?)  end { 
	my $code = $item{name};
	my $values = $item{"value(s?)"};
	my $before = $::this_track->vol;
	::Text::t_insert_effect  $before, $code, $values ;
 	1;}

append_effect: _append_effect name value(s?) end {
	my $code = $item{name};
	my $values = $item{"value(s?)"};
 	::Text::t_add_effect $code, $values;
 	1;}

insert_effect: _insert_effect before name value(s?) end {
	my $before = $item{before};
	my $code = $item{name};
	my $values = $item{"value(s?)"};
	#print "values: " , ref $values, $/;
	print join ", ", @{$values} if $values;
	::Text::t_insert_effect  $before, $code, $values;
	1;}

before: op_id

modify_effect: _modify_effect op_id parameter value end {
	::modify_effect @item{ qw( op_id parameter value) }; 1
}
modify_effect: _modify_effect op_id parameter sign value end {
	::modify_effect @item{ qw( op_id parameter sign value) }; 1
}
group_version: _group_version end { 
	use warnings;
	no warnings qw(uninitialized);
	print $::tracker->version, "\n" ; 1}
group_version: _group_version dd end { 
	my $n = $item{dd};
	$n = undef if $n == 0;
	$::tracker->set( version => $n ); 1}
bunch: _bunch name(s?) { ::Text::bunch( @{$item{'name(s?)'}}); 1}
list_versions: _list_versions end { 
	print join " ", @{$::this_track->versions}, "\n"; 1}
ladspa_register: _ladspa_register end { 
	::pager( ::eval_iam("ladspa-register")); 1}
preset_register: _preset_register end { 
	::pager( ::eval_iam("preset-register")); 1}
ctrl_register: _ctrl_register end { 
	::pager( ::eval_iam("ctrl-register")); 1}
preview: _preview { ::preview(); 1}
doodle: _doodle { ::doodle(); 1 }
normalize: _normalize { $::this_track->normalize; 1}
fixdc: _fixdc { $::this_track->fixdc; 1}
destroy_current_wav: _destroy_current_wav { 
	my $old_group_status = $::tracker->rw;
	$::tracker->set(rw => 'MON');
	my $wav = $::this_track->full_path;
	print "delete WAV file $wav? [n] ";
	my $reply = <STDIN>;
	if ( $reply =~ /y/i ){
		print "Unlinking.\n";
		unlink $wav or warn "couldn't unlink $wav: $!\n";
		::rememoize();
	}
	$::tracker->set(rw => $old_group_status);
	1;
}
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
automix: _automix { ::automix(); 1 }
autofix: _autofix { ::command_process("for mon; fixdc; normalize"); 1 }
import: _import path frequency end {
	$::this_track->bring_in( $item{path}, $item{frequency}); 1;
}
import: _import path end {
	$::this_track->bring_in( $item{path}, 'auto'); 1;
}
frequency: value
