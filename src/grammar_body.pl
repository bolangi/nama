#command: test
#test: 'test' shellish { 
#	::pager2( "found $item{shellish}");
#	}

# CASE 0: Midish command 

meta: midish_cmd 

midish_cmd: /[a-z]+/ predicate { 
	return unless $::midi->{keywords}->{$item[1]};
	my $line = "$item[1] $item{predicate}";
	::midish_command($line);
	1;
}

# CASE 1: Shell code, perl code or 'for' commands consume text up to ;; or 
# to the end of line.  The remaining text will be parsed again at the top level
# until all text is consumed.

# execute shell command if leading '!'

meta: bang shellcode stopper {
	::logit('::Grammar','debug',"Evaluating shell commands!");
	my $shellcode = $item{shellcode};
	$shellcode =~ s/\$thiswav/$::this_track->full_path/e;
	::pager2( "executing this shell code:  $shellcode" )
		if $shellcode ne $item{shellcode};
	my $output = qx( $shellcode );
	::pager($output) if $output;
	1;
}

# execute perl code if leading 'eval'

meta: eval perlcode stopper {
	::logit('::Grammar','debug',"Evaluating perl code");
	::eval_perl($item{perlcode});
	1
}
# execute for each specified track if leading 'for'

meta: for bunch_spec ';' namacode stopper { 
 	::logit('Grammar','debug',"namacode: $item{namacode}");
 	my @tracks = ::bunch_tracks($item{bunch_spec});
 	for my $t(@tracks) {
 		::leading_track_spec($t);
		$::text->{parser}->meta($item{namacode});
 		#::pager2(("$t); $item{namacode}");
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


#meta: text semicolon(?) { $::text->{parser}->do_part($item{text}) }
meta: nosemi(s /\s*;\s*/) semicolon(?) 

nosemi: text { $::text->{parser}->do_part($item{text}) }

text: /[^;]+/ 
semicolon: ';'

do_part: track_spec command end
do_part: track_spec end
do_part: command end

predicate: nonsemi end { $item{nonsemi}}
predicate: /$/
iam_cmd: ident { $item{ident} if $::text->{iam}->{$item{ident}} }
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
	::logit('::Grammar','debug',"Found Ecasound IAM command: $user_input");
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
	$::text->{parser}->do_part("$item{user_alias} $item{predicate}"); 1
}
user_alias: ident { 
	#print "alias: $item{ident}\n";
		$::text->{user_alias}->{$item{ident}} }
user_command: ident { return $item{ident} if $::text->{user_command}->{$item{ident}} }

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
effect: /\w[^, ]+/ | <error: illegal identifier, only word characters and colon allowed>
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
markname: /[A-Za-z]\w*/ { 
	::throw("$item[1]: non-existent mark name. Skipping"), return undef 
		unless $::Mark::by_name{$item[1]};
	$item[1];
}
#region_default_end: 'END' | ''
path: shellish
modifier: 'audioloop' | 'select' | 'reverse' | 'playat' | value
end: /[;\s]*$/ 		# [space char, semicolon]{0,}
					# end-of-string

connect_target: connect_type connect_id { [ @item{qw(connect_type connect_id)} ] }
connect_type: 'track' | 'loop' | 'jack' 
connect_id: shellish 

help_effect: _help_effect effect { ::help_effect($item{effect}) ; 1}
find_effect: _find_effect anytag(s) { 
	::find_effect(@{$item{"anytag(s)"}}); 1}
help: _help 'yml' { ::pager($::text->{commands_yml}); 1}
help: _help anytag  { ::help($item{anytag}) ; 1}
help: _help { ::pager2( $::help->{screen} ); 1}
project_name: _project_name { 
	::pager2( "project name: ", $::gui->{_project_name}->{name}); 1}
create_project: _create_project project_id { 
	::t_create_project $item{project_id} ; 1}
list_projects: _list_projects { ::list_projects() ; 1}
load_project: _load_project project_id {
	::t_load_project $item{project_id} ; 1}
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
save_state: _save_state { ::save_state(); ::git_save_state(); 1}
get_state: _get_state statefile {
 	::load_project( 
 		name => $::gui->{_project_name}->{name},
 		settings => $item{statefile}
 		); 1}
get_state: _get_state {
 	::load_project( name => $::gui->{_project_name}->{name},) ; 1}
getpos: _getpos {  
	::pager2( ::d1( ::eval_iam q(getpos) )); 1}
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
existing_track_name: track_name { 
	my $track_name = $item{track_name};
	return $track_name if $::tn{$track_name}; 
	print("$track_name: track does not exist.\n"),
	undef
}
# was set bus Brass
move_to_bus: _move_to_bus existing_bus_name {
	$::this_track->set( group => $item{existing_bus_name}); 1
} 
set_track: _set_track key someval {
	 $::this_track->set( $item{key}, $item{someval} ); 1}
dump_track: _dump_track { ::pager($::this_track->dump); 1}
dump_group: _dump_group { ::pager($::bn{Main}->dump); 1}
dump_all: _dump_all { ::dump_all(); 1}
remove_track: _remove_track quiet end {
	::remove_track_cmd($::this_track, $item{quiet});
	1
}
# remove_track: _remove_track existing_track_name {
# 		::remove_track_cmd($::tn{$item{existing_track_name}});
# 		1
# }
remove_track: _remove_track end { 
		::remove_track_cmd($::this_track) ;
		1
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
		::pager2($::this_track->name, ": Shifting start time to $pos seconds");
		$::this_track->set(playat => $pos);
		1;
	}
	# elsif ( pos =~ /^\d+$/ ) { # skip the mark index case
	elsif ( $::Mark::by_name{$pos} ){
		my $time = ::Mark::mark_time( $pos );
		pager2($::this_track->name, qq(: Shifting start time to mark "$pos", $time seconds));
		$::this_track->set(playat => $pos);
		1;
	} else { 
		::throw( "Shift value is neither decimal nor mark name. Skipping.");
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
arm_start: _arm_start { ::arm(); ::start_transport(); 1 }
connect: _connect { ::connect_transport(); 1}
disconnect: _disconnect { ::disconnect_transport(); 1}
engine_status: _engine_status { ::pager2(::eval_iam q(engine-status)); 1}
start: _start { ::start_transport(); 1}
stop: _stop { ::stop_transport(); 1}
ecasound_start: _ecasound_start { ::eval_iam('start'); 1}
ecasound_stop: _ecasound_stop  { ::eval_iam('stop'); 1}
restart_ecasound: _restart_ecasound { ::restart_ecasound(); 1 }
show_tracks: _show_tracks { 	
	::pager( ::show_tracks(::showlist()));

	1;
}
show_tracks_all: _show_tracks_all { 	
	my $list = [undef, undef, sort{$a->n <=> $b->n} ::Track::all()];
	::pager(::show_tracks($list));
	1;
}
show_bus_tracks: _show_bus_tracks { 	

	my $bus = $::bn{$::this_bus};
	my $list = $bus->trackslist;
	::pager(::show_tracks($list));
	1;
}
modifiers: _modifiers modifier(s) {
 	$::this_track->set(modifiers => (join q(,),
	@{$item{"modifier(s)"}}, q() ));
	1;}

modifiers: _modifiers { ::pager2( $::this_track->modifiers); 1}
nomodifiers: _nomodifiers { $::this_track->set(modifiers => ""); 1}
show_chain_setup: _show_chain_setup { ::pager(::ChainSetup::ecasound_chain_setup); 1}
show_io: _show_io { ::ChainSetup::show_io(); 1}
show_track: _show_track {
	my $output = $::text->{format_top};
	$output .= ::show_tracks_section($::this_track);
	$output .= ::show_region();
	$output .= ::show_versions();
	$output .= ::show_send();
	$output .= ::show_bus();
	$output .= ::show_modifiers();
	$output .= join "", "Signal width: ", ::width($::this_track->width), "\n";
	$output .= ::show_inserts();
	$output .= ::show_effects();
	::pager( $output );
	1;}
show_track: _show_track track_name { 
 	::pager( ::show_tracks( 
	$::tn{$item{track_name}} )) if $::tn{$item{track_name}};
	1;}
show_track: _show_track dd {  
	::pager( ::show_tracks( $::ti{$item{dd}} )) if
	$::ti{$item{dd}};
	1;}

show_mode: _show_mode { ::pager2( ::show_status()); 1}
bus_rec: _bus_rec {
	my $bus = $::bn{$::this_bus}; 
	$bus->set(rw => 'REC');
	# set up mix track
	$::tn{$bus->send_id}->busify
		if $bus->send_type eq 'track' and $::tn{$bus->send_id};
	::pager2( "Setting REC-enable for " , $::this_bus , " bus. You may record member tracks.");
	1; }
bus_mon: _bus_mon {
	my $bus = $::bn{$::this_bus}; 
	$bus->set(rw => 'MON');
	# set up mix track
	$::tn{$bus->send_id}->busify
		if $bus->send_type eq 'track' and $::tn{$bus->send_id};
	::pager2( "Setting MON mode for " , $::this_bus , " bus. Monitor only for member tracks.");
 	1  
}
bus_off: _bus_off {
	my $bus = $::bn{$::this_bus}; 
	$bus->set(rw => 'OFF');
	# turn off mix track
	if($bus->send_type eq 'track' and my $mix = $::tn{$bus->send_id})
	{ $mix->set(rw => 'OFF') }
	::pager2( "Setting OFF mode for " , $::this_bus, " bus. Member tracks disabled."); 1  
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
mixdown: _mixdown { ::mixdown(); 1}
mixplay: _mixplay { ::mixplay(); 1}
mixoff:  _mixoff  { ::mixoff(); 1}
automix: _automix { ::automix(); 1 }
autofix_tracks: _autofix_tracks { ::command_process("for mon; fixdc; normalize"); 1 }
master_on: _master_on { ::master_on(); 1 }

master_off: _master_off { ::master_off(); 1 }

exit: _exit {   
	::save_state(); 
	::cleanup_exit();
	1
}	
source: _source connect_target { 
	$::this_track->set_source(@{$item{connect_target}}); 1 }
source: _source source_id { $::this_track->set_source($item{source_id}); 1 }
source_id: shellish
source: _source { 
	print $::this_track->name, ": input set to ", $::this_track->input_object_text, "\n";
	print "however track status is ", $::this_track->rec_status, "\n"
		if $::this_track->rec_status ne 'REC';
	1;
}
send: _send connect_target { 
	$::this_track->set_send(@{$item{connect_target}}); 1 }
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
	# skip fancy logic for system tracks, just set track 'rw' field
	$::this_track->is_system_track 
		? $::this_track->set(rw => uc $item{rw_setting}) 
		: ::rw_set($::Bus::by_name{$::this_bus},$::this_track,$item{rw_setting}); 
	1
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
		::throw(( $::this_track->name . ": no volume control available")), return;
	::modify_effect(
		$::this_track->vol,
		0,
		undef,
		$item{value});
	1;
} 
vol: _vol sign(?) value { 
	$::this_track->vol or 
		::throw( $::this_track->name . ": no volume control available"), return;
	::modify_effect(
		$::this_track->vol,
		0,
		$item{'sign(?)'}->[0],
		$item{value});
	1;
} 
vol: _vol { ::pager2( $::fx->{params}->{$::this_track->vol}[0]); 1}

mute: _mute { $::this_track->mute; 1}

unmute: _unmute { $::this_track->unmute; 1}


solo: _solo ident(s) {
	::solo(@{$item{'ident(s)'}}); 1
}

solo: _solo { ::solo($::this_track->name); 1}
all: _all { ::all() ; 1}
nosolo: _nosolo { ::nosolo() ; 1}

unity: _unity { 
	::effect_update_copp_set( 
		$::this_track->vol, 
		0, 
		$::config->{unity_level}->{::type($::this_track->vol)}
	);
	1;}

pan: _pan panval { 
	::effect_update_copp_set( $::this_track->pan, 0, $item{panval});
	1;} 
pan: _pan sign panval {
	::modify_effect( $::this_track->pan, 0, $item{sign}, $item{panval} );
	1;} 
panval: float 
      | dd
pan: _pan { ::pager2( $::fx->{params}->{$::this_track->pan}[0]); 1}
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
#	eval q( $mark->jump_here ) or ::logit('::Grammar','debug',"jump failed: $@");
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
	#::pager2( @new_endpoints);
	$::mode->{loop_enable} = 1;
	@{$::setup->{loop_endpoints}} = (@new_endpoints, @{$::setup->{loop_endpoints}}); 
	@{$::setup->{loop_endpoints}} = @{$::setup->{loop_endpoints}}[0,1];
	1;}
loop_disable: _loop_disable { $::mode->{loop_enable} = 0; 1}
name_mark: _name_mark ident {$::this_mark->set_name( $item{ident}); 1}
list_marks: _list_marks { 
	my $i = 0;
	my @lines = map{ ( $_->{time} == $::this_mark->{time} ? q(*) : q()
	,join " ", $i++, sprintf("%.1f", $_->{time}), $_->name, "\n")  } 
		  #sort { $a->time <=> $b->time } 
		  @::Mark::all;
	my $start = my $end = "undefined";
	push @lines, "now at ". sprintf("%.1f", ::eval_iam "getpos"). "\n";
	::pager(@lines);
	1;}
to_mark: _to_mark dd {
	my @marks = ::Mark::all();
	$marks[$item{dd}]->jump_here;
	1;}
to_mark: _to_mark ident { 
	my $mark = $::Mark::by_name{$item{ident}};
	$mark->jump_here if defined $mark;
#	eval q( $mark->jump_here ) or ::logit('::Grammar','debug',"jump failed: $@");
	1;}
modify_mark: _modify_mark sign value {
	my $newtime = eval($::this_mark->{time} . $item{sign} . $item{value});
	$::this_mark->set( time => $newtime );
	print $::this_mark->name, ": set to ", ::d2( $newtime), "\n";
	print "adjusted to ",$::this_mark->time, "\n" 
		if $::this_mark->time != $newtime;
	::set_position($::this_mark->time);
	$::setup->{changed}++;
	1;
	}
modify_mark: _modify_mark value {
	$::this_mark->set( time => $item{value} );
	my $newtime = $item{value};
	print $::this_mark->name, ": set to ", ::d2($newtime),"\n";
	print "adjusted to ",$::this_mark->time, "\n" 
		if $::this_mark->time != $newtime;
	::set_position($::this_mark->time);
	$::setup->{changed}++;
	1;
	}		
remove_effect: _remove_effect op_id(s) {
	#print join $/, @{ $item{"op_id(s)"} }; 
	::mute();
	map{ 
		::remove_effect( $_ )
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
	my $id = ::add_effect({
		parent_id => $parent, 
		type	  => $code, 
		values	  => $values,
	});
	if($id)
	{
		my $i = 	::effect_index($code);
		my $iname = $::fx_cache->{registry}->[$i]->{name};

		my $pi = 	::effect_index(::type($parent));
		my $pname = $::fx_cache->{registry}->[$pi]->{name};

		print "\nAdded $id ($iname) to $parent ($pname)\n\n";

	}
	1;
}
add_controller: _add_controller effect value(s?) {
	print("current effect is undefined, skipping\n"), return 1 if ! $::this_op;
	my $code = $item{effect};
	my $parent = $::this_op;
	my $values = $item{"value(s?)"};
	#print "values: " , ref $values, $/;
	#print join ", ", @{$values} if $values;
	my $id = ::add_effect({
		parent_id	=> $parent, 
		type		=> $code, 
		values		=> $values,
	});
	if($id)
	{
		my $i = 	::effect_index($code);
		my $iname = $::fx_cache->{registry}->[$i]->{name};

		my $pi = 	::effect_index(::type($parent));
		my $pname = $::fx_cache->{registry}->[$pi]->{name};

		print "\nAdded $id ($iname) to $parent ($pname)\n\n";

	}
	1;
}
add_effect: _add_effect effect value(s?) {
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
	print(qq{$code: unknown effect. Try "find_effect keyword(s)\n}), return 1
		unless ::effect_index($code);
	my $args = {
		track  => $::this_track, 
		type   => ::full_effect_code($code),
		values => $values
	};
	# place effect before fader if there is one
	my $fader = $::this_track->pan || $::this_track->vol; 
	$args->{before} = $fader if $fader;
 	my $id = ::add_effect($args);
	if ($id)
	{
		my $i = ::effect_index($code);
		my $iname = $::fx_cache->{registry}->[$i]->{name};

		print "\nAdded $id ($iname)\n\n";
		$::this_op = $id;
	}
 	1;
}

# cut-and-paste copy of add_effect, without using 'before' parameter
append_effect: _append_effect effect value(s?) {
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
	::throw(qq{$code: unknown effect. Try "find_effect keyword(s)}), return 1
		unless ::effect_index($code);
	my $args = {
		track  => $::this_track, 
		type   => ::full_effect_code($code),
		values => $values
	};
 	my $id = ::add_effect($args);
	if ($id)
	{
		my $i = ::effect_index($code);
		my $iname = $::fx_cache->{registry}->[$i]->{name};

		::pager2( "Added $id ($iname)");
		$::this_op = $id;
	}
 	1;
}

insert_effect: _insert_effect before effect value(s?) {
	my $before = $item{before};
	my $code = $item{effect};
	my $values = $item{"value(s?)"};
	#::pager2( "values: " , ref $values);
	::pager2( join ", ", @{$values}) if $values;
	my $id = ::add_effect({
		before 	=> $before, 
		type	=> $code, 
		values	=> $values,
	});
	if($id)
	{
		my $i = ::effect_index($code);
		my $iname = $::fx_cache->{registry}->[$i]->{name};

		my $bi = 	::effect_index(::type($before));
		my $bname = $::fx_cache->{registry}->[$bi]->{name};

 		::pager2( "Inserted $id ($iname) before $before ($bname)");
		$::this_op = $id;
	}
	1;}

before: op_id
parent: op_id
modify_effect: _modify_effect parameter(s /,/) value {
	::throw("current effect is undefined, skipping"), return 1 if ! $::this_op;
	::modify_multiple_effects( 
		[$::this_op], 
		$item{'parameter(s)'},
		undef,
		$item{value});
	::pager2( ::show_effect($::this_op))
}
modify_effect: _modify_effect parameter(s /,/) sign value {
	::throw("current effect is undefined, skipping"), return 1 if ! $::this_op;
	::modify_multiple_effects( [$::this_op], @item{qw(parameter(s) sign value)});
	::pager2( ::show_effect($::this_op));
}

modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) value {
	::modify_multiple_effects( @item{qw(op_id(s) parameter(s) sign value)});
	# note that 'sign' results in undef value
	::pager(::show_effect(@{ $item{'op_id(s)'} }))
}
modify_effect: _modify_effect op_id(s /,/) parameter(s /,/) sign value {
	::modify_multiple_effects( @item{qw(op_id(s) parameter(s) sign value)});
	::pager(::show_effect(@{ $item{'op_id(s)'} }));
}
position_effect: _position_effect op_to_move new_following_op {
	my $op = $item{op_to_move};
	my $pos = $item{new_following_op};
	::position_effect($op, $pos);
	1;
}

op_to_move: op_id
new_following_op: op_id
	
show_effect: _show_effect op_id(s) {
	my @lines = 
		map{ ::show_effect($_) } 
		grep{ ::fx($_) }
		@{ $item{'op_id(s)'}};
	$::this_op = $item{'op_id(s)'}->[-1];
	::pager(@lines); 1
}
show_effect: _show_effect {
	::throw("current effect is undefined, skipping"), return 1 if ! $::this_op;
	::pager2( ::show_effect($::this_op));
	1;
}
list_effects: _list_effects { ::pager(::list_effects()); 1}
new_bunch: _new_bunch ident(s) { ::bunch( @{$item{'ident(s)'}}); 1}
list_bunches: _list_bunches { ::bunch(); 1}
remove_bunches: _remove_bunches ident(s) { 
 	map{ delete $::gui->{_project_name}->{bunch}->{$_} } @{$item{'ident(s)'}}; 1}
add_to_bunch: _add_to_bunch ident(s) { ::add_to_bunch( @{$item{'ident(s)'}});1 }
list_versions: _list_versions { 
	::pager2( join " ", @{$::this_track->versions}); 1}
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
	$::config->{memoize} = 1;
	memoize('candidates'); 1
}
unmemoize: _unmemoize {
	package ::Wav;
	$::config->{memoize} = 0;
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
	my @history = $::text->{term}->GetHistory;
	my %seen;
	::pager2( grep{ ! $seen{$_}; $seen{$_}++ } @history );
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
	else { ::throw("$item{bus_name}: no such bus"); undef }
}

bus_name: ident 
user_bus_name: ident 
{
	if($item[1] =~ /^[A-Z]/){ $item[1] }
	else { ::throw("Bus name must begin with capital letter."); undef} 
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
add_insert: _add_insert 'local' {
	::Insert::add_insert( $::this_track,'postfader_insert');
	1;
}
add_insert: _add_insert prepost send_id return_id(?) {
	my $return_id = $item{'return_id(?)'}->[0];
	my $send_id = $item{send_id};
	::Insert::add_insert($::this_track, "$item{prepost}fader_insert",$send_id, $return_id);
	1;
}
prepost: 'pre' | 'post'
send_id: jack_port
return_id: jack_port

set_insert_wetness: _set_insert_wetness prepost(?) parameter {
	my $prepost = $item{'prepost(?)'}->[0];
	my $p = $item{parameter};
	my $id = ::Insert::get_id($::this_track,$prepost);
	::throw($::this_track->name.  ": Missing or ambiguous insert. Skipping"), 
		return 1 unless $id;
	::throw("wetness parameter must be an integer between 0 and 100"), 
		return 1 unless ($p <= 100 and $p >= 0);
	my $i = $::Insert::by_index{$id};
	::throw("track '",$::this_track->n, "' has no insert.  Skipping."),
		return 1 unless $i;
	$i->set_wetness($p);
	1;
}
set_insert_wetness: _set_insert_wetness prepost(?) {
	my $prepost = $item{'prepost(?)'}->[0];
	my $id = ::Insert::get_id($::this_track,$prepost);
	$id or ::throw($::this_track->name.  ": Missing or ambiguous insert. Skipping"), return 1 ;
	my $i = $::Insert::by_index{$id};
	 ::pager2( "The insert is ", $i->wetness, "% wet, ", (100 - $i->wetness), "% dry.");
}

remove_insert: _remove_insert prepost(?) { 

	# use prepost spec if provided
	# remove lone insert without prepost spec
	
	my $prepost = $item{'prepost(?)'}->[0];
	my $id = ::Insert::get_id($::this_track,$prepost);
	$id or ::throw($::this_track->name.  ": Missing or ambiguous insert. Skipping"), return 1 ;
	::pager2( $::this_track->name.": removing $prepost". "fader insert");
	$::Insert::by_index{$id}->remove;
	1;
}

cache_track: _cache_track additional_time(?) {
	my $time = $item{'additional_time(?)'}->[0];
	::cache_track($::this_track, $time); 1 
}
additional_time: float | dd
uncache_track: _uncache_track { ::uncache_track($::this_track); 1 }
new_effect_chain: _new_effect_chain ident end {
	my $name = $item{ident};

	my ($old_entry) = ::EffectChain::find(user => 1, name => $name);

	# overwrite identically named effect chain
	#
	my @options;
	push(@options, 'n' , $old_entry->n) if $old_entry;
	::EffectChain->new(
		user   => 1,
		global => 1,
		name   => $item{ident},
		ops_list => [ $::this_track->fancy_ops ],
		inserts_data => $::this_track->inserts,
		@options,
	);
	1;
}
add_effect_chain: _add_effect_chain ident {
	::EffectChain::find(
		unique => 1, 
		user   => 1, 
		name   => $item{ident}
	)->add($::this_track);
	1;
}
delete_effect_chain: _delete_effect_chain ident(s) {
	map{ 
		::EffectChain::find(
			unique => 1, 
			user   => 1,
			name   => $_
		)->destroy() 

	} @{ $item{'ident(s)'} };
	1;
}
find_effect_chains: _find_effect_chains ident(s?) 
{
	my @args;
	push @args, @{ $item{'ident(s)'} } if $item{'ident(s)'};
	::pager(map{$_->dump} ::EffectChain::find(@args));
}
find_user_effect_chains: _find_user_effect_chains ident(s?)
{
	my @args = ('user' , 1);
	push @args, @{ $item{'ident(s)'} } if $item{'ident(s)'};
	(scalar @args) % 2 == 0 
		or ::throw("odd number of arguments\n@args\n"), return 0;
	::pager( map{ $_->summary} ::EffectChain::find(@args)  );
	1;
}
##### bypass
#
#  argument(s) provided
#
bypass_effects:   _bypass_effects op_id(s) { 
	my $arr_ref = $item{'op_id(s)'};
	return unless (ref $arr_ref) =~ /ARRAY/  and scalar @{$arr_ref};
	my @illegal = grep { ! ::fx($_) } @$arr_ref;
	::throw("@illegal: non-existing effect(s), skipping."), return 0 if @illegal;
 	::pager2( "track ",$::this_track->name,", bypassing effects:");
	::pager2( ::named_effects_list(@$arr_ref));
	::bypass_effects($::this_track,@$arr_ref);
	# set current effect in special case of one op only
	$::this_op = $arr_ref->[0] if scalar @$arr_ref == 1;
}
#
#  all effects on current track
#
bypass_effects: _bypass_effects 'all' { 
	::pager2( "track ",$::this_track->name,", bypassing all effects (except vol/pan)");
	::bypass_effects($::this_track, $::this_track->fancy_ops)
		if $::this_track->fancy_ops;
	1; 
}
#
#  current effect 
#
bypass_effects: _bypass_effects { 
	::throw("current effect is undefined, skipping"), return 1 if ! $::this_op;
 	::pager2( "track ",$::this_track->name,", bypassing effects:"); 
	::pager2( ::named_effects_list($::this_op));
 	::bypass_effects($::this_track, $::this_op);  
 	1; 
}
bring_back_effects:   _bring_back_effects end { 
	::pager2("current effect is undefined, skipping"), return 1 if ! $::this_op;
	::pager2( "restoring effects:");
	::pager2( ::named_effects_list($::this_op));
	::restore_effects( $::this_track, $::this_op);
}
bring_back_effects:   _bring_back_effects op_id(s) { 
	my $arr_ref = $item{'op_id(s)'};
	return unless (ref $arr_ref) =~ /ARRAY/  and scalar @{$arr_ref};
	my @illegal = grep { ! ::fx($_) } @$arr_ref;
	::throw("@illegal: non-existing effect(s), aborting."), return 0 if @illegal;
	::pager2( "restoring effects:");
	::pager2( ::named_effects_list(@$arr_ref));
	::restore_effects($::this_track,@$arr_ref);
	# set current effect in special case of one op only
	$::this_op = $arr_ref->[0] if scalar @$arr_ref == 1;
}
bring_back_effects:   _bring_back_effects 'all' { 
	::pager2( "restoring all effects");
	::restore_effects( $::this_track, $::this_track->fancy_ops);
}
# effect_on_current_track: op_id { 
# 	my $id = $item{op_id};
# 	my $found = 
# 	$::fx($id) or ::pager2("$id: effect does not exist."), return 0;
# 	grep{$id eq $_  } @{$::this_track->ops} 
# 			   or ::pager2("$id: effect does not belong to track",
# 						$::this_track->name), return 0;			  
# 	$id;
# }


effect_chain_id: effect_chain_id_pair(s) {
 		die " i found an effect chain id";
  		my @pairs = @{$item{'effect_chain_id_pair(s)'}};
  		my @found = ::EffectChain::find(@pairs);
  		@found and 
  			::pager2(
				join " ", "found effect chain(s):",
  				map{ ('name:', $_->name, 'n', $_->n )} @found
			)
  			#map{ 1 } @found;
}
effect_chain_id_pair: fxc_key fxc_val { return @$item{fxc_key fxc_val} }

fxc_key: 'n'|                #### HARDCODED XX
		'ops_list'|
        'ops_dat'|
		'inserts_data'|
		'name'|
		'id'|
		'project'|
		'global'|
		'profile'|
		'user'|
		'system'|
		'track_name'|
		'track_version'|
		'track_cache'|
		'bypass'

# [% join " | ", split " ", qx(cat ./magical_pixie_operator.pl) %]

fxc_val: shellish

this_track_op_id: op_id(s) { 
	my %ops = map{ $_ => 1 } @{$::this_track->ops};
	my @ids = @{$item{'op_id(s)'}};
	my @belonging 	= grep {   $ops{$_} } @ids;
	my @alien 		= grep { ! $ops{$_} } @ids;
	@alien and ::pager2("@alien: don't belong to track ",$::this_track->name, "skipping."); 
	@belonging	
}

overwrite_effect_chain: _overwrite_effect_chain ident {
	::overwrite_effect_chain($::this_track, $item{ident}); 1;
}
bunch_name: ident { 
	::is_bunch($item{ident}) or ::bunch_tracks($item{ident})
		or ::throw("$item{ident}: no such bunch name."), return; 
	$item{ident};
}

effect_profile_name: ident
existing_effect_profile_name: ident {
	::pager2("$item{ident}: no such effect profile"), return
		unless ::EffectChain::find(profile => $item{ident});
	$item{ident}
}
new_effect_profile: _new_effect_profile bunch_name effect_profile_name {
	::new_effect_profile($item{bunch_name}, $item{effect_profile_name}); 1 }
delete_effect_profile: _delete_effect_profile existing_effect_profile_name {
	::delete_effect_profile($item{existing_effect_profile_name}); 1 }
apply_effect_profile: _apply_effect_profile existing_effect_profile_name {
	::apply_effect_profile($item{effect_profile_name}); 1 }
list_effect_profiles: _list_effect_profiles ident(?) {
	my $name;
	$name = $item{'ident(?)'}->[-1] if $item{'ident(?)'};
	$name ||= 1;
	my @output = 
		map
		{ 	
			$name = $_->profile;
			$_->track_name;
		} ::EffectChain::find(profile => $name);
	if( @output )
	{ ::pager( "\nname: $name\ntracks: ", join " ",@output) }
	else { ::throw("no match") }
	1;
}
show_effect_profiles: _show_effect_profiles ident(?) {
	my $name;
	$name = $item{'ident(?)'}->[-1] if $item{'ident(?)'};
	$name ||= 1;
	my $old_profile_name;
	my $profile_name;
	my @output = 
		grep{ ! /index:/ }
		map
		{ 	
			
			# return profile name at top if changed
			# return summary

			my @out;
			my $profile_name = $_->profile;
			if ( $profile_name ne $old_profile_name )
			{
			 	push @out, "name: $profile_name\n";
				$old_profile_name = $profile_name 
			}
			push @out, $_->summary;
			@out
		} ::EffectChain::find(profile => $name);
	if( @output )
	{ ::pager( @output); }
	else { ::throw("no match") }
	1;
}
full_effect_profiles: _full_effect_profiles ident(?) {
	my $name;
	$name = $item{'ident(?)'}->[-1] if $item{'ident(?)'};
	$name ||= 1;
	my @output = map{ $_->dump } ::EffectChain::find(profile => $name )  ;
	if( @output )
	{ ::pager( @output); }
	else { ::throw("no match") }
	1;
}
do_script: _do_script shellish { ::do_script($item{shellish});1}
scan: _scan { ::pager2( "scanning ", ::this_wav_dir()); ::rememoize() }
add_fade: _add_fade in_or_out mark1 duration(?)
{ 	::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $::config->{engine_fade_default_length}, 
					relation => 'fade_from_mark',
					track => $::this_track->name,
	); 
	++$::setup->{changed};
}
add_fade: _add_fade in_or_out duration(?) mark1 
{ 	::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $::config->{engine_fade_default_length}, 
					track => $::this_track->name,
					relation => 'fade_to_mark',
	);
	++$::setup->{changed};
}
add_fade: _add_fade in_or_out mark1 mark2
{ 	::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					mark2 => $item{mark2},
					track => $::this_track->name,
	);
	++$::setup->{changed};
}
#add_fade: _add_fade in_or_out time1 time2 # not implemented
in_or_out: 'in' | 'out'
duration: value
mark1: markname
mark2: markname
remove_fade: _remove_fade fade_index(s) { 
	my @i = @{ $item{'fade_index(s)'} };
	::remove_fade($_) for (@i);
	$::setup->{changed}++;
	1
}
fade_index: dd 

list_fade: _list_fade {  ::pager(join "\n",
		map{ s/^---//; s/...\s$//; $_} map{$_->dump}
		sort{$a->n <=> $b->n} values %::Fade::by_index) }
add_comment: _add_comment text { 
 	::pager2( $::this_track->name, ": comment: $item{text}"); 
 	$::this_track->set(comment => $item{text});
 	1;
}
remove_comment: _remove_comment {
 	::pager2( $::this_track->name, ": comment removed");
 	$::this_track->set(comment => undef);
 	1;
}
show_comment: _show_comment {
	map{ ::pager2( "(",$_->group,") ", $_->name, ": ", $_->comment) } $::this_track;
	1;
}
show_comments: _show_comments {
	map{ ::pager2( "(",$_->group,") ", $_->name, ": ", $_->comment) } ::Track::all();
	1;
}
add_version_comment: _add_version_comment dd(?) text {
	my $t = $::this_track;
	my $v = $item{'dd(?)'}->[0] // $t->monitor_version // return 1;
	::pager2( ::add_version_comment($t,$v,$item{text})); 
}	
remove_version_comment: _remove_version_comment dd {
	my $t = $::this_track;
	::pager2( ::remove_version_comment($t,$item{dd})); 1
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
	::pager2( ::set_system_version_comment($::this_track,@item{qw(dd text)}));1;
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
	::select_edit_track('edit_track'); 1}
host_track_alias: _host_track_alias {
	::select_edit_track('host_alias_track'); 1}
host_track: _host_track { 
	::select_edit_track('host'); 1}
version_mix_track: _version_mix_track {
	::select_edit_track('version_mix'); 1}
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
	$::setup->{edit_points}->[0] = ::eval_iam('getpos'); 1}
set_rec_start_mark: _set_rec_start_mark {
	$::setup->{edit_points}->[1] = ::eval_iam('getpos'); 1}
set_rec_end_mark: _set_rec_end_mark {
	$::setup->{edit_points}->[2] = ::eval_iam('getpos'); 1}
end_edit_mode: _end_edit_mode { ::end_edit_mode(); 1;}

disable_edits: _disable_edits { ::disable_edits();1 }

merge_edits: _merge_edits { ::merge_edits(); 1; }

explode_track: _explode_track {
	::explode_track($::this_track)
}
promote_version_to_track: _promote_version_to_track version {
	my $v = $item{version};
	my $t = $::this_track;
	$t->versions->[$v] or ::pager2($t->name,": version $v does not exist."),
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
	my $sign = $item{'sign(?)'}->[-1]; 
	$::setup->{runtime_limit} = $sign
		? eval "$::setup->{audio_length} $sign $item{dd}"
		: $item{dd};
	::pager2( "Run time limit: ", ::heuristic_time($::setup->{runtime_limit})); 1;
}
limit_run_time_off: _limit_run_time_off { 
	::pager2( "Run timer disabled");
	::disable_length_timer();
	1;
}
offset_run: _offset_run markname {
	::offset_run( $item{markname} ); 1
}
offset_run_off: _offset_run_off {
	::pager2( "no run offset.");
	::offset_run_mode(0); 1
}
view_waveform: _view_waveform { 
	
	my $viewer = 'mhwaveedit';
	if( `which $viewer` =~ m/\S/){ 
		my $cmd = join " ",
			$viewer,
			"--driver",
			$::jack->{jackd_running} ? "jack" : "alsa",
			$::this_track->full_path,
			"&";
		system($cmd) 
	}
	else { ::throw("Mhwaveedit not found. No waveform viewer is available.") }
}
edit_waveform: _edit_waveform { 
	
	if ( `which audacity` =~ m/\S/ ){  # executable found
		my $cmd = join " ",
			'audacity',
			$::this_track->full_path,
			"&";
		my $old_pwd = ::getcwd();		
		chdir ::this_wav_dir();
		system($cmd);
		chdir $old_pwd;
	}
	else { ::throw("Audacity not found. No waveform editor available.") }
	1;
}

rerecord: _rerecord { 
		::pager2(
			scalar @{$::setup->{_last_rec_tracks}} 
				?  "Toggling previous recording tracks to REC"
				:  "No tracks in REC list. Skipping."
		);
		
		map{ $_->set(rw => 'REC') } @{$::setup->{_last_rec_tracks}}; 
		::restore_preview_mode();
		1;
}

eager: _eager mode_string { $::mode->{eager} = $item{mode_string} }
mode_string: 'off'    { 0 }
mode_string: 'doodle' 
mode_string: 'preview'

show_track_latency: _show_track_latency {
	my $node = $::setup->{latency}->{track}->{$::this_track->name};
	::pager2( ::yaml_out($node)) if $node;
	1;
}
show_latency_all: _show_latency_all { 
	::pager2( ::yaml_out($::setup->{latency})) if $::setup->{latency};
	1;
}
# config_key: key {
# 	my $key = $item{key};
# 	warn("$key: illegal config setting"), return 0
# 		unless grep{ /^.$key$/ } keys ::Assign::var_map();
# 	return $key
# }
# config: _config config_key shellish {
# 	my $arg = $item{shellish};
# 	my $key = $item{config_key};
# 	$::project->{config}->{$key} = $arg;
# 	return 1;
# }
# config: _config config_key {
# 	my $key = $item{config_key};
#  	my $arg = $::project->{config}->{$key};
#  	if (defined $arg) {
#  		::pager2( "project specific setting for $key: $arg");
#  	}
#  	return 1;
# }
# unset: _unset config_key {
# 	my $key = $item{config_key};
# 	my $arg = $::project->{config}->{$key};
# 	::pager2( "removing project-specific setting for $key: $arg");
# 	::pager2( "value will default to global config file (.namarc) setting");
# 	delete $::project->{$item{config_key}};
# 	::pager2( "currently ",$::config->$key, "");
# 	1;
# }
