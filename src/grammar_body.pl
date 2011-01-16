#command: test
#test: 'test' shellish { print "found $item{shellish}\n" }

# CASE 0: Midish command 

meta: midish_cmd 

midish_cmd: /[a-z]+/ predicate { 
	return unless $::midish_command{$item[1]};
	my $line = "$item[1] $item{predicate}";
	::midish_command($line);
	1;
}

# CASE 1: Shell code, perl code or 'for' commands consume text up to ;; or 
# to the end of line.  The remaining text will be parsed again at the top level
# until all text is consumed.

# execute shell command if leading '!'

meta: bang shellcode stopper {
	$::debug and print "Evaluating shell commands!\n";
	my $output = qx( $item{shellcode});
	::pager($output) if $output;
	print "\n";
	1;
}

# execute perl code if leading 'eval'

meta: eval perlcode stopper {
	$::debug and print "Evaluating perl code\n";
	::eval_perl($item{perlcode});
	1;
}

# execute for each specified track if leading 'for'

meta: for bunch_spec ';' namacode stopper { 
 	$::debug and print "namacode: $item{namacode}\n";
 	my @tracks = ::bunch_tracks($item{bunch_spec});
 	for my $t(@tracks) {
 		::leading_track_spec($t);
		$::parser->meta($item{namacode});
 		#print("$t; $item{namacode}\n");
	}
	1;
}

bunch_spec: text 

# CASE 2: 

# If we have reached here (and we match the grammar) we are
# dealing with either:
# (1) a Nama command (possibly specifying a new current track) or
# (2) an Ecasound-IAM command.

# Split text on semicolons, and pass each segment
# to the parser's 'do_part' command.


#meta: text semicolon(?) { $::parser->do_part($item{text}) }
meta: nosemi(s /\s*;\s*/) semicolon(?) 

nosemi: text { $::parser->do_part($item{text}) }

text: /[^;]+/ 
semicolon: ';'

do_part: track_spec command end
do_part: track_spec end
do_part: command end

predicate: nonsemi semistop { $item{nonsemi}}
predicate: /$/
iam_cmd: ident { $item{ident} if $::iam_cmd{$item{ident}} }
track_spec: ident { ::leading_track_spec($item{ident}) }
bang: '!'
eval: 'eval'
for: 'for'
stopper: ';;' | /$/ 
shellcode: somecode #{ print "shellcode: $item{somecode}\n"}
perlcode: somecode #{ print "perlcode: $item{somecode}\n"}
namacode: somecode #{ print "namacode: $item{somecode}\n"}
somecode: /.+?(?=;;|$)/ 
nonsemi: /[^;]+/
semistop: /;|$/
#semi_stop: ';' | /$/

# execute Ecasound IAM command

command: iam_cmd predicate { 
	my $user_input = "$item{iam_cmd} $item{predicate}"; 
	$::debug and print "Found Ecasound IAM command: $user_input\n";
	my $result = ::eval_iam($user_input);
	::pager( $result );  
	1 }

command: user_command predicate {
	#print "user command: $item{user_command}\n";
	#print "predicate: $item{predicate}\n";
	# why does command name get into predicate ??
	#::do_user_command($item{user_command}, split " ",$item{predicate});
	::do_user_command(split " ",$item{predicate});
	1;
}
command: user_alias predicate {
	#print "alias: $item{user_alias}\n";
	$::parser->do_part("$item{user_alias} $item{predicate}"); 1
}
user_alias: ident { 
	#print "alias: $item{ident}\n";
		$::user_alias{$item{ident}} }
user_command: ident { return $item{ident} if $::user_command{$item{ident}} }

# other commands (generated automatically)
#
# command: command_name


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
dd: /\d+/			# digits {1,}
shellish: /"(.+)"/ { $1 }
shellish: /'(.+)'/ { $1 }
shellish: anytag | <error>

					# used in: help, do_script
					 # 
jack_port: shellish
effect: /\w[\w:]*/   | <error: illegal identifier, only word characters and colon allowed>
project_id: ident slash(?) { $item{ident} }
slash: '/'
					# used in create_project, load_project
anytag: /\S+/
ident: /[-\w]+/  #| <error: illegal name!> 
					# used in: bunch_name, effect_profile,
					# track_name
					# existing_effect_profile
					# save_state, get_state
					 # remove_mark new_mark name_mark to_mark
					 # new_effect_chain add_effect_chain list_effect_chains
					 # delete_effect_chain overwrite_effect_chain

statefile: /[-:\w\.]+/
marktime: /\d+\.\d+/ # decimal required
markname: /\w+/ { 	 # word characters
	print("$item[1]: non-existent mark name. Skipping\n"), return undef 
		unless $::Mark::by_name{$item[1]};
	$item[1];
}
#region_default_end: 'END' | ''
path: /~?[\w\-\.\/]+/ # optional tilde [word char, dot, hyphen, slash]{1,}
path: shellish
modifier: 'audioloop' | 'select' | 'reverse' | 'playat' | value
end: /[;\s]*$/ 		# [space char, semicolon]{0,}
					# end-of-string

help_effect: _help_effect effect { ::Text::help_effect($item{effect}) ; 1}
find_effect: _find_effect anytag(s) { 
	::Text::find_effect(@{$item{"anytag(s)"}}); 1}
help: _help 'yml' { ::pager($::commands_yml); 1}
help: _help anytag  { ::Text::help($item{anytag}) ; 1}
help: _help { print $::help_screen ; 1}
project_name: _project_name { 
	print "project name: ", $::project_name, $/; 1}
create_project: _create_project project_id { 
	::Text::t_create_project $item{project_id} ; 1}
list_projects: _list_projects { ::list_projects() ; 1}
load_project: _load_project project_id {
	::Text::t_load_project $item{project_id} ; 1}
new_project_template: _new_project_template key text(?) {
	::new_project_template($item{key}, $item{text});
	1;
}
use_project_template: _use_project_template key {
	::use_project_template($item{key}); 1;
}
list_project_templates: _list_project_templates {
	::list_project_templates(); 1;
}
remove_project_template: _remove_project_template key(s) {
	::remove_project_template(@{$item{'key(s)'}}); 1;
}
save_state: _save_state ident { ::save_state( $item{ident}); 1}
save_state: _save_state { ::save_state(); 1}
get_state: _get_state statefile {
 	::load_project( 
 		name => $::project_name,
 		settings => $item{statefile}
 		); 1}
get_state: _get_state {
 	::load_project( name => $::project_name,) ; 1}
getpos: _getpos {  
	print ::d1( ::eval_iam q(getpos) ), $/; 1}
setpos: _setpos timevalue {
	::set_position($item{timevalue}); 1}
forward: _forward timevalue {
	::forward( $item{timevalue} ); 1}
rewind: _rewind timevalue {
	::rewind( $item{timevalue} ); 1}
timevalue: min_sec | seconds
seconds: value
min_sec: /\d+/ ':' /\d+/ { $item[1] * 60 + $item[3] }

to_start: _to_start { ::to_start(); 1 }
to_end: _to_end { ::to_end(); 1 }
add_track: _add_track track_name(s) {
	::add_track(@{$item{'track_name(s)'}}); 1}
add_tracks: _add_tracks track_name(s) {
	map{ ::add_track($_)  } @{$item{'track_name(s)'}}; 1}
track_name: ident
# was set bus Brass
move_to_bus: _move_to_bus existing_bus_name {
	$::this_track->set( group => $item{existing_bus_name}); 1
} 
xxset_track: _xxset_track key someval {
	 $::this_track->set( $item{key}, $item{someval} ); 1}
dump_track: _dump_track { ::pager($::this_track->dump); 1}
dump_group: _dump_group { ::pager($::main->dump); 1}
dump_all: _dump_all { ::dump_all(); 1}
remove_track: _remove_track quiet(?) { 
 	my $quiet = scalar @{$item{'quiet(?)'}};
 	# remove track quietly if requested
 	$::this_track->remove, return 1 if $quiet or $::quietly_remove_tracks;
 
 	my $name = $::this_track->name; 
 	my $reply = $::term->readline("remove track $name? [n] ");
 	if ( $reply =~ /y/i ){
 		print "Removing track. All WAV files will be kept.\n";
 		$::this_track->remove; 
 	}
 	1;
}
quiet: 'quiet'
link_track: _link_track track_name target project {
	::add_track_alias_project($item{track_name}, $item{target}, $item{project}); 1
}
link_track: _link_track track_name target {
	::add_track_alias($item{track_name}, $item{target}); 1
}
target: track_name
project: ident
set_region: _set_region beginning ending { 
	::set_region( @item{ qw( beginning ending ) } );
	1;
}
set_region: _set_region beginning { ::set_region( $item{beginning}, 'END' );
	1;
}
remove_region: _remove_region { ::remove_region(); 1; }
new_region: _new_region beginning ending track_name(?) {
	my $name = $item{'track_name(?)'}->[0];
	::new_region(@item{qw(beginning ending)}, $name); 1
}

shift_track: _shift_track start_position {
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
		$::this_track->set(playat => $pos);
		1;
	} else { print 
	"Shift value is neither decimal nor mark name. Skipping.\n";
	0;
	}
}

start_position:  float | mark_name
mark_name: ident

unshift_track: _unshift_track {
	$::this_track->set(playat => undef)
}
beginning: marktime | markname
ending: 'END' | marktime | markname 
generate: _generate { ::generate_setup(); 1}
arm: _arm { ::arm(); 1}
connect: _connect { ::connect_transport(); 1}
disconnect: _disconnect { ::disconnect_transport(); 1}
engine_status: _engine_status { 
	print(::eval_iam q(engine-status)); print "\n" ; 1}
start: _start { ::start_transport(); 1}
stop: _stop { ::stop_transport(); 1}
ecasound_start: _ecasound_start { ::eval_iam("stop"); 1}
ecasound_stop: _ecasound_stop  { ::eval_iam("start"); 1}
show_tracks: _show_tracks { 	
	::pager( ::Text::show_tracks(::Text::showlist()));
	1;
}
show_tracks_all: _show_tracks_all { 	
	my $list = [undef, undef, sort{$a->n <=> $b->n} ::Track::all()];
	::pager(::Text::show_tracks($list));
	1;
}
show_bus_tracks: _show_bus_tracks { 	

	my $bus = $::bn{$::this_bus};
	my $list = $bus->trackslist;
	::pager(::Text::show_tracks($list));
	1;
}
modifiers: _modifiers modifier(s) {
 	$::this_track->set(modifiers => (join q(,),
	@{$item{"modifier(s)"}}, q() ));
	1;}

modifiers: _modifiers { print $::this_track->modifiers, "\n"; 1}
nomodifiers: _nomodifiers { $::this_track->set(modifiers => ""); 1}
show_chain_setup: _show_chain_setup { ::pager($::chain_setup); 1}
show_io: _show_io { ::show_io(); 1}
show_track: _show_track {
	my $output = $::format_top;
	$output .= ::Text::show_tracks_section($::this_track);
	$output .= ::Text::show_region();
	$output .= ::Text::show_effects();
	$output .= ::Text::show_versions();
	$output .= ::Text::show_send();
	$output .= ::Text::show_bus();
	$output .= ::Text::show_modifiers();
	$output .= join "", "Signal width: ", ::width($::this_track->width), "\n";
	$output .= ::Text::show_effect_chain_stack();
	$output .= ::Text::show_inserts();
	::pager( $output );
	1;}
show_track: _show_track track_name { 
 	::pager( ::Text::show_tracks( 
	$::tn{$item{track_name}} )) if $::tn{$item{track_name}};
	1;}
show_track: _show_track dd {  
	::pager( ::Text::show_tracks( $::ti{$item{dd}} )) if
	$::ti{$item{dd}};
	1;}

show_mode: _show_mode { print STDOUT ::Text::show_status; 1}
bus_rec: _bus_rec {
	my $bus = $::bn{$::this_bus}; 
	$bus->set(rw => 'REC');
	# set up mix track
	$::tn{$bus->send_id}->busify
		if $bus->send_type eq 'track' and $::tn{$bus->send_id};
	print "Setting REC-enable for " , $::this_bus ,
		" bus. You may record member tracks.\n";
	1; }
bus_mon: _bus_mon {
	my $bus = $::bn{$::this_bus}; 
	$bus->set(rw => 'MON');
	# set up mix track
	$::tn{$bus->send_id}->busify
		if $bus->send_type eq 'track' and $::tn{$bus->send_id};
	print "Setting MON mode for " , $::this_bus , 
		" bus. Monitor only for member tracks.\n";
 	1  
}
bus_off: _bus_off {
	my $bus = $::bn{$::this_bus}; 
	$bus->set(rw => 'OFF');
	# turn off mix track
	if($bus->send_type eq 'track' and my $mix = $::tn{$bus->send_id})
	{ $mix->set(rw => 'OFF') }
	print "Setting OFF mode for " , $::this_bus,
		" bus. Member tracks disabled.\n"; 1  
}
bus_version: _bus_version { 
	use warnings;
	no warnings qw(uninitialized);
	print $::this_bus, " bus default version is: ", 
		$::bn{$::this_bus}->version, "\n" ; 1}
bus_version: _bus_version dd { 
	my $n = $item{dd};
	$n = undef if $n == 0;
	$::bn{$::this_bus}->set( version => $n ); 
	print $::this_bus, " bus default version set to: ", 
		$::bn{$::this_bus}->version, "\n" ; 1}
mixdown: _mixdown { ::Text::mixdown(); 1}
mixplay: _mixplay { ::Text::mixplay(); 1}
mixoff:  _mixoff  { ::Text::mixoff(); 1}
automix: _automix { ::automix(); 1 }
autofix_tracks: _autofix_tracks { ::command_process("for mon; fixdc; normalize"); 1 }
master_on: _master_on { ::master_on(); 1 }

master_off: _master_off { ::master_off(); 1 }

exit: _exit {   ::save_state($::state_store_file); 
					::cleanup_exit();
                    1}	

source: _source source_id { $::this_track->set_source($item{source_id}); 1 }
source_id: shellish
source: _source { 
	print $::this_track->name, ": input set to ", $::this_track->input_object, "\n";
	print "however track status is ", $::this_track->rec_status, "\n"
		if $::this_track->rec_status ne 'REC';
	1;
}
send: _send jack_port { $::this_track->set_send($item{jack_port}); 1}
send: _send { $::this_track->set_send(); 1}
remove_send: _remove_send {
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

#off: 'off' {$::this_track->set_off(); 1}
#rec: 'rec' { $::this_track->set_rec(); 1}
#mon: 'mon' {$::this_track->set_mon(); 1}

# dummy defs to avoid warnings from command.yml entries
off: 'Xxx' {}
rec: 'Xxx' {}
mon: 'Xxx' {}

command: rw end # XX 'end' required to make test suite pass

rw_setting: 'rec'|'mon'|'off'
rw: rw_setting {
	::rw_set($::Bus::by_name{$::this_bus},$::this_track,$item{rw_setting}); 1
}
rec_defeat: _rec_defeat { 
	$::this_track->set(rec_defeat => 1);
	print $::this_track->name, ": WAV recording disabled!\n";
}
rec_enable: _rec_enable { 
	$::this_track->set(rec_defeat => 0);
	print $::this_track->name, ": WAV recording enabled";
	my $rw = $::bn{$::this_track->group}->rw;
	if ( $rw ne 'REC'){
		print qq(, but bus "),$::this_track->group, qq(" has rw setting of $rw.\n),
		"No WAV file will be recorded.\n";
	} else { print "!\n" }
}

set_version: _set_version dd { $::this_track->set_version($item{dd}); 1}

vol: _vol value { 
	$::this_track->vol or 
		print( $::this_track->name . ": no volume control available\n"), return;
	::modify_effect(
		$::this_track->vol,
		0,
		undef,
		$item{value});
	1;
} 
vol: _vol sign(?) value { 
	$::this_track->vol or 
		print( $::this_track->name . ": no volume control available\n"), return;
	::modify_effect(
		$::this_track->vol,
		0,
		$item{'sign(?)'}->[0],
		$item{value});
	1;
} 
vol: _vol { print $::copp{$::this_track->vol}[0], "\n" ; 1}

mute: _mute { $::this_track->mute; 1}

unmute: _unmute { $::this_track->unmute; 1}
# solo: _solo 'bus' track_name {
# 	print ("$item{track_name}: Expected bus track_name. Skipping.\n"), return 1
# 		unless $::bn{$item{track_name}};
# 	::command_process("for all; off;; $item{track_name} mon");
# 	1;
# }
solo: _solo { ::solo(); 1}
all: _all { ::all() ; 1}


unity: _unity { 
	::effect_update_copp_set( 
		$::this_track->vol, 
		0, 
		$::unity_level{$::cops{$::this_track->vol}->{type}}
	);
	1;}

pan: _pan dd { 
	::effect_update_copp_set( $::this_track->pan, 0, $item{dd});
	1;} 
pan: _pan sign dd {
	::modify_effect( $::this_track->pan, 0, $item{sign}, $item{dd} );
	1;} 
pan: _pan { print $::copp{$::this_track->pan}[0], "\n"; 1}
pan_right: _pan_right { ::pan_check( 100 ); 1}
pan_left:  _pan_left  { ::pan_check(   0 ); 1}
pan_center: _pan_center { ::pan_check(  50 ); 1}
pan_back:  _pan_back {
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
remove_mark: _remove_mark dd {
	my @marks = ::Mark::all();
	$marks[$item{dd}]->remove if defined $marks[$item{dd}];
	1;}
remove_mark: _remove_mark ident { 
	my $mark = $::Mark::by_name{$item{ident}};
	$mark->remove if defined $mark;
#	eval q( $mark->jump_here ) or $debug and print "jump failed: $@\n";
	1;}
remove_mark: _remove_mark { 
	return unless (ref $::this_mark) =~ /Mark/;
	$::this_mark->remove;
	1;}
new_mark: _new_mark ident { ::drop_mark $item{ident}; 1}
new_mark: _new_mark {  ::drop_mark(); 1}
next_mark: _next_mark { ::next_mark(); 1}
previous_mark: _previous_mark { ::previous_mark(); 1}
loop_enable: _loop_enable someval(s) {
	my @new_endpoints = @{ $item{"someval(s)"}}; # names or indexes of marks
	#print join $/, @new_endpoints;
	$::loop_enable = 1;
	@::loop_endpoints = (@new_endpoints, @::loop_endpoints); 
	@::loop_endpoints = @::loop_endpoints[0,1];
	1;}
loop_disable: _loop_disable { $::loop_enable = 0; 1}
name_mark: _name_mark ident {$::this_mark->set_name( $item{ident}); 1}
list_marks: _list_marks { 
	my $i = 0;
	map{ print( $_->{time} == $::this_mark->{time} ? q(*) : q()
	,join " ", $i++, sprintf("%.1f", $_->{time}), $_->name, "\n")  } 
		  #sort { $a->time <=> $b->time } 
		  @::Mark::all;
	my $start = my $end = "undefined";
	print "now at ", sprintf("%.1f", ::eval_iam "getpos"), "\n";
	1;}
to_mark: _to_mark dd {
	my @marks = ::Mark::all();
	$marks[$item{dd}]->jump_here;
	1;}
to_mark: _to_mark ident { 
	my $mark = $::Mark::by_name{$item{ident}};
	$mark->jump_here if defined $mark;
#	eval q( $mark->jump_here ) or $debug and print "jump failed: $@\n";
	1;}
modify_mark: _modify_mark sign value {
	my $newtime = eval($::this_mark->{time} . $item{sign} . $item{value});
	$::this_mark->set( time => $newtime );
	print $::this_mark->name, ": set to ", ::d2( $newtime), "\n";
	print "adjusted to ",$::this_mark->time, "\n" 
		if $::this_mark->time != $newtime;
	::eval_iam("setpos ".$::this_mark->time);
	$::regenerate_setup++;
	1;
	}
modify_mark: _modify_mark value {
	$::this_mark->set( time => $item{value} );
	my $newtime = $item{value};
	print $::this_mark->name, ": set to ", ::d2($newtime),"\n";
	print "adjusted to ",$::this_mark->time, "\n" 
		if $::this_mark->time != $newtime;
	::eval_iam("setpos ".$::this_mark->time);
	$::regenerate_setup++;
	1;
	}		
remove_effect: _remove_effect op_id(s) {
	#print join $/, @{ $item{"op_id(s)"} }; 
	::mute();
	map{ print "removing effect id: $_\n"; ::remove_effect( $_ )
	} grep { $_ }  @{ $item{"op_id(s)"}} ;
	# map{ print "op_id: $_\n"; ::remove_effect( $_ )}  @{ $item{"op_id(s)"}} ;
	::sleeper(0.5);
	::unmute();
	1;}

add_controller: _add_controller parent effect value(s?) {
	my $code = $item{effect};
	my $parent = $item{parent};
	my $values = $item{"value(s?)"};
	#print "values: " , ref $values, $/;
	#print join ", ", @{$values} if $values;
	my $id = ::Text::t_add_ctrl($parent, $code, $values);
	if($id)
	{
		my $i = 	::effect_index($code);
		my $iname = $::effects[$i]->{name};

		my $pi = 	::effect_index($::cops{$parent}->{type});
		my $pname = $::effects[$pi]->{name};

		print "\nAdded $id ($iname) to $parent ($pname)\n\n";

	}
	1;
}
add_effect: _add_effect effect value(s?) {
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
 	my $id = ::Text::t_add_effect($::this_track, $code, $values);
	if ($id)
	{
		my $i = ::effect_index($code);
		my $iname = $::effects[$i]->{name};

		print "\nAdded $id ($iname)\n\n";
	}
 	1;
}

insert_effect: _insert_effect before effect value(s?) {
	my $before = $item{before};
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
	#print "values: " , ref $values, $/;
	print join ", ", @{$values} if $values;
	my $id = ::Text::t_insert_effect($before, $code, $values);
	if($id)
	{
		my $i = ::effect_index($code);
		my $iname = $::effects[$i]->{name};

		my $bi = 	::effect_index($::cops{$before}->{type});
		my $bname = $::effects[$bi]->{name};

 		print "\nInserted $id ($iname) before $before ($bname)\n\n";
	}
	1;}

before: op_id
parent: op_id
modify_effect: _modify_effect parameter(s /,/) value {
	print("Operator \"$::this_op\" does not exist.\n"), return 1
		unless $::cops{$::this_op};
	::modify_multiple_effects( 
		[$::this_op], 
		$item{'parameter(s)'},
		undef,
		$item{value});
	print ::Text::show_effect($::this_op);
	1;
}
modify_effect: _modify_effect parameter(s /,/) sign value {
	print("Operator \"$::this_op\" does not exist.\n"), return 1
		unless $::cops{$::this_op};
	::modify_multiple_effects( [$::this_op], @item{qw(parameter(s) sign value)});
	print ::Text::show_effect($::this_op);
	1;
}

modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) value {
	::modify_multiple_effects( @item{qw(op_id(s) parameter(s) sign value)});
	# note that 'sign' results in undef value
	::pager(::Text::show_effect(@{ $item{'op_id(s)'} }));
	1;
}
modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) sign value {
	::modify_multiple_effects( @item{qw(op_id(s) parameter(s) sign value)});
	::pager(::Text::show_effect(@{ $item{'op_id(s)'} }));
	1;
}
show_effect: _show_effect op_id(s) {
	my @lines = 
		map{ ::Text::show_effect($_) } 
		grep{ $::cops{$_} }
		@{ $item{'op_id(s)'}};
	$::this_op = $item{'op_id(s)'}->[-1];
	::pager(@lines); 1
}
show_effect: _show_effect {
	print("Operator \"$::this_op\" does not exist.\n"), return 1
	unless $::cops{$::this_op};
	print ::Text::show_effect($::this_op);
	1;
}
new_bunch: _new_bunch ident(s) { ::Text::bunch( @{$item{'ident(s)'}}); 1}
list_bunches: _list_bunches { ::Text::bunch(); 1}
remove_bunches: _remove_bunches ident(s) { 
 	map{ delete $::bunch{$_} } @{$item{'ident(s)'}}; 1}
add_to_bunch: _add_to_bunch ident(s) { ::Text::add_to_bunch( @{$item{'ident(s)'}});1 }
list_versions: _list_versions { 
	print join " ", @{$::this_track->versions}, "\n"; 1}
ladspa_register: _ladspa_register { 
	::pager( ::eval_iam("ladspa-register")); 1}
preset_register: _preset_register { 
	::pager( ::eval_iam("preset-register")); 1}
ctrl_register: _ctrl_register { 
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
import_audio: _import_audio path frequency {

	::import_audio($::this_track, $item{path}, $item{frequency}); 1;
}
import_audio: _import_audio path {
	::import_audio($::this_track, $item{path}); 1;
}
frequency: value
list_history: _list_history {
	my @history = $::term->GetHistory;
	my %seen;
	map { print "$_\n" unless $seen{$_}; $seen{$_}++ } @history
}
main_off: _main_off { 
	$::main_out = 0;
1;
} 
main_on: _main_on { 
	$::main_out = 1;
1;
} 
add_send_bus_cooked: _add_send_bus_cooked bus_name destination {
	::add_send_bus( $item{bus_name}, $item{destination}, 'cooked' );
	1;

}
add_send_bus_raw: _add_send_bus_raw bus_name destination {
	::add_send_bus( $item{bus_name}, $item{destination}, 'raw' );
	1;
}
add_sub_bus: _add_sub_bus bus_name { ::add_sub_bus( $item{bus_name}); 1 }

existing_bus_name: bus_name {
	if ( $::bn{$item{bus_name}} ){  $item{bus_name} }
	else { print("$item{bus_name}: no such bus\n"); undef }
}

bus_name: ident 
user_bus_name: ident 
{
	if($item[1] =~ /^[A-Z]/){ $item[1] }
	else { print("Bus name must begin with capital letter.\n"); undef} 
}

destination: jack_port # include channel, loop,device, jack_port

remove_bus: _remove_bus existing_bus_name { 
	$::bn{$item{existing_bus_name}}->remove; 1; 
}
update_send_bus: _update_send_bus existing_bus_name {
 	::update_send_bus( $item{existing_bus_name} );
 	1;
}
set_bus: _set_bus key someval { $::bn{$::this_bus}->set($item{key} => $item{someval}); 1 }

list_buses: _list_buses { ::pager(map{ $_->dump } ::Bus::all()) ; 1}
add_insert: _add_insert prepost send_id return_id(?) {
	my $return_id = $item{'return_id(?)'}->[0];
	my $send_id = $item{send_id};
	::Insert::add_insert( "$item{prepost}fader_insert",$send_id, $return_id);
	1;
}
prepost: 'pre' | 'post'
send_id: jack_port
return_id: jack_port

set_insert_wetness: _set_insert_wetness prepost(?) parameter {
	my $prepost = $item{'prepost(?)'}->[0];
	my $p = $item{parameter};
	my $id = ::Insert::get_id($::this_track,$prepost);
	print($::this_track->name.  ": Missing or ambiguous insert. Skipping\n"), 
		return 1 unless $id;
	print("wetness parameter must be an integer between 0 and 100\n"), 
		return 1 unless ($p <= 100 and $p >= 0);
	my $i = $::Insert::by_index{$id};
	print("track '",$::this_track->n, "' has no insert.  Skipping.\n"),
		return 1 unless $i;
	$i->{wetness} = $p;
	::modify_effect($i->wet_vol, 0, undef, $p);
	::sleeper(0.1);
	::modify_effect($i->dry_vol, 0, undef, 100 - $p);
	1;
}

set_insert_wetness: _set_insert_wetness prepost(?) {
	my $prepost = $item{'prepost(?)'}->[0];
	my $id = ::Insert::get_id($::this_track,$prepost);
	$id or print($::this_track->name.  ": Missing or ambiguous insert. Skipping\n"), return 1 ;
	my $i = $::Insert::by_index{$id};
	 print "The insert is ", 
		$i->wetness, "% wet, ", (100 - $i->wetness), "% dry.\n";
}

remove_insert: _remove_insert prepost(?) { 

	# use prepost spec if provided
	# remove lone insert without prepost spec
	
	my $prepost = $item{'prepost(?)'}->[0];
	my $id = ::Insert::get_id($::this_track,$prepost);
	$id or print($::this_track->name.  ": Missing or ambiguous insert. Skipping\n"), return 1 ;
	print $::this_track->name.": removing $prepost". "fader insert\n";
	$::Insert::by_index{$id}->remove;
	1;
}

cache_track: _cache_track additional_time(?) {
	my $time = $item{'additional_time(?)'}->[0];
	::cache_track($::this_track, $time); 1 
}
additional_time: float | dd
uncache_track: _uncache_track { ::uncache_track($::this_track); 1 }
new_effect_chain: _new_effect_chain ident op_id(s?) {
	#print "ident $item{ident}, ops: ", @{$item{'op_id(s?)'}}, $/;
	::new_effect_chain($::this_track, $item{ident}, @{ $item{'op_id(s?)'} });
	1;
}
add_effect_chain: _add_effect_chain ident {
	::add_effect_chain($::this_track, $item{ident});
	1;
}
delete_effect_chain: _delete_effect_chain ident(s) {
	map{ delete $::effect_chain{$_} } @{ $item{'ident(s)'} };
	1;
}
list_effect_chains: _list_effect_chains ident(s?) {
	::pager(::list_effect_chains( @{ $item{'ident(s?)'} } )); 1;
}

    
bypass_effects:   _bypass_effects { 
	::push_effect_chain($::this_track) and
	print $::this_track->name, ": bypassing effects\n"; 1}
restore_effects: _restore_effects { 
	::restore_effects($::this_track) and
	print $::this_track->name, ": restoring effects\n"; 1}
overwrite_effect_chain: _overwrite_effect_chain ident {
	::overwrite_effect_chain($::this_track, $item{ident}); 1;
}
bunch_name: ident { 
	::is_bunch($item{ident}) or ::bunch_tracks($item{ident})
		or print("$item{ident}: no such bunch name.\n"), return; 
	$item{ident};
}

effect_profile_name: ident
existing_effect_profile_name: ident {
	print("$item{ident}: no such effect profile\n"), return
		unless $::effect_profile{$item{ident}};
	$item{ident}
}
new_effect_profile: _new_effect_profile bunch_name effect_profile_name {
	::new_effect_profile($item{bunch_name}, $item{effect_profile_name}); 1 }
delete_effect_profile: _delete_effect_profile existing_effect_profile_name {
	::delete_effect_profile($item{existing_effect_profile_name}); 1 }
apply_effect_profile: _apply_effect_profile effect_profile_name {
	::apply_effect_profile(\&::overwrite_effect_chain, $item{effect_profile_name}); 1 }
overlay_effect_profile: _overlay_effect_profile effect_profile_name {
	::apply_effect_profile(\&::add_effect_chain, $item{effect_profile_name}); 1 }
list_effect_profiles: _list_effect_profiles {
	::pager(::list_effect_profiles()); 1 }
do_script: _do_script shellish { ::do_script($item{shellish});1}
scan: _scan { print "scanning ", ::this_wav_dir(), "\n"; ::rememoize() }
add_fade: _add_fade in_or_out mark1 duration(?)
{ 	::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $::default_fade_length, 
					relation => 'fade_from_mark',
					track => $::this_track->name,
	); 
	++$::regenerate_setup;
}
add_fade: _add_fade in_or_out duration(?) mark1 
{ 	::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $::default_fade_length, 
					track => $::this_track->name,
					relation => 'fade_to_mark',
	);
	++$::regenerate_setup;
}
add_fade: _add_fade in_or_out mark1 mark2
{ 	::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					mark2 => $item{mark2},
					track => $::this_track->name,
	);
	++$::regenerate_setup;
}
#add_fade: _add_fade in_or_out time1 time2 # not implemented
in_or_out: 'in' | 'out'
duration: value
mark1: ident
mark2: ident
remove_fade: _remove_fade fade_index(s) { 
	my @i = @{ $item{'fade_index(s)'} };
	::Text::remove_fade($_) for (@i);
	$::regenerate_setup++;
	1
}
fade_index: dd 
 { if ( $::Fade::by_index{$item{dd}} ){ return $item{dd}}
   else { print("invalid fade number: $item{dd}\n"); return 0 }
 }
list_fade: _list_fade {  ::pager(join "\n",
		map{ s/^---//; s/...\s$//; $_} map{$_->dump}
		sort{$a->n <=> $b->n} values %::Fade::by_index) }
add_comment: _add_comment text { 
 	print $::this_track->name, ": comment: $item{text}\n"; 
 	$::this_track->set(comment => $item{text});
 	1;
}
remove_comment: _remove_comment {
 	print $::this_track->name, ": comment removed\n";
 	$::this_track->set(comment => undef);
 	1;
}
show_comment: _show_comment {
	map{ print "(",$_->group,") ", $_->name, ": ", $_->comment, "\n"; } $::this_track;
	1;
}
show_comments: _show_comments {
	map{ print "(",$_->group,") ", $_->name, ": ", $_->comment, "\n"; } ::Track::all();
	1;
}
add_version_comment: _add_version_comment dd(?) text {
	my $t = $::this_track;
	my $v = $item{'dd(?)'}->[0] // $t->monitor_version // return 1;
	print ::add_version_comment($t,$v,$item{text});
}	
remove_version_comment: _remove_version_comment dd {
	my $t = $::this_track;
	print ::remove_version_comment($t,$item{dd}); 1
}
show_version_comment: _show_version_comment dd(s?) {
	my $t = $::this_track;
	my @v = @{$item{'dd(s?)'}};
	if(!@v){ @v = $t->monitor_version}
	@v or return 1;
	::show_version_comments($t,@v);
	 1;
}
show_version_comments_all: _show_version_comments_all {
	my $t = $::this_track;
	my @v = @{$t->versions};
	::show_version_comments($t,@v); 1;
}
set_system_version_comment: _set_system_version_comment dd text {
	print ::set_system_version_comment($::this_track,@item{qw(dd text)});1;
}
midish_command: _midish_command text {
	::midish_command( $item{text} ); 1
}

new_edit: _new_edit {
	::new_edit();
	1;
}
set_edit_points: _set_edit_points { ::set_edit_points(); 1 }
list_edits: _list_edits { ::list_edits(); 1}

destroy_edit: _destroy_edit { ::destroy_edit(); 1}

select_edit: _select_edit dd { ::select_edit($item{dd}); 1}

preview_edit_in: _preview_edit_in { ::edit_action($item[0]); 1}

preview_edit_out: _preview_edit_out { ::edit_action($item[0]); 1}

play_edit: _play_edit { ::edit_action($item[0]); 1}

record_edit: _record_edit { ::edit_action($item[0]); 1}

edit_track: _edit_track { 
	print("You need to select an edit first (list_edits, select_edit)\n"),
		return unless defined $::this_edit;
	$::this_track = $::this_edit->edit_track; 1
}
host_track_alias: _host_track_alias { 
	print("You need to select an edit first (list_edits, select_edit)\n"),
		return unless defined $::this_edit;
	$::this_track = $::this_edit->host_alias_track; 1 
}
host_track: _host_track { 
	print("You need to select an edit first (list_edits, select_edit)\n"),
		return unless defined $::this_edit;
	$::this_track = $::this_edit->host; 1 
}
version_mix_track: _version_mix_track { 
	print("You need to select an edit first (list_edits, select_edit)\n"),
		return unless defined $::this_edit;
	$::this_track = $::this_edit->version_mix; 1 
}
play_start_mark: _play_start_mark {
	my $mark = $::this_edit->play_start_mark;
	$mark->jump_here; 1;
}
rec_start_mark: _rec_start_mark {
	$::this_edit->rec_start_mark->jump_here; 1;
}
rec_end_mark: _rec_end_mark {
	$::this_edit->rec_end_mark->jump_here; 1;
}
set_play_start_mark: _set_play_start_mark {
	$::edit_points[0] = ::eval_iam('getpos'); 1}
set_rec_start_mark: _set_rec_start_mark {
	$::edit_points[1] = ::eval_iam('getpos'); 1}
set_rec_end_mark: _set_rec_end_mark {
	$::edit_points[2] = ::eval_iam('getpos'); 1}
end_edit_mode: _end_edit_mode { ::end_edit_mode(); 1;}

disable_edits: _disable_edits { ::disable_edits();1 }

merge_edits: _merge_edits { ::merge_edits(); 1; }

explode_track: _explode_track {
	::explode_track($::this_track)
}
promote_version_to_track: _promote_version_to_track version {
	my $v = $item{version};
	my $t = $::this_track;
	$t->versions->[$v] or print($t->name,": version $v does not exist.\n"),
		return;
	::VersionTrack->new(
		name 	=> $t->name.":$v",
		version => $v, # fixed
		target  => $t->name,
		rw		=> 'MON',
		group   => $t->group,
	);
}
version: dd

read_user_customizations: _read_user_customizations {
	::setup_user_customization(); 1
}
limit_run_time: _limit_run_time sign(?) dd { 
	my $sign = $item{'sign(?)'}->[-0];
	$::run_time = $sign
		? eval "$::length $sign $item{dd}"
		: $item{dd};
	print "Run time limit: ", ::heuristic_time($::run_time), "\n"; 1;
}
limit_run_time_off: _limit_run_time_off { 
	print "Run timer disabled\n";
	::disable_length_timer();
	1;
}
offset_run: _offset_run markname {
	::offset_run( $item{markname} ); 1
}
offset_run_off: _offset_run_off {
	print "no run offset.\n";
	::offset_run_mode(0); 1
}
