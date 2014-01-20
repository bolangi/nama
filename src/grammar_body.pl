# command: test
#command: 'a-test' { print "aa-test" }
command: _a_test { print "aaa-test" }
_a_test: /something_else\b/ | /a-test\b/
#test: 'test' shellish { 
#	::pager( "found $item{shellish}");
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
	my $olddir = ::getcwd();
	my $prefix = "chdir ". ::project_dir().";";
	$shellcode = "$prefix $shellcode" if $shellcode =~ /^\s*git /;

	::pager( "executing this shell code:  $shellcode" )
		if $shellcode ne $item{shellcode};
	my $output = qx( $shellcode );
	chdir $olddir;
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
 		::user_set_current_track($t);
		$::text->{parser}->meta($item{namacode});
 		#::pager(("$t); $item{namacode}");
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

do_part: command end
do_part: track_spec command end
do_part: track_spec end

predicate: nonsemi end { $item{nonsemi}}
predicate: /$/
iam_cmd: ident { $item{ident} if $::text->{iam}->{$item{ident}} }
#track_spec: existing_track_name { ::user_set_current_track($item{existing_track_name}) }
track_spec: ident { ::user_set_current_track($item{ident}) }
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
		$::config->{alias}->{command}->{$item{ident}} }
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
effect: /\w[^, ]+/
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
					 # delete_effect_chain 

save_target: /[-:\w.]+/
decimal_seconds: /\d+(\.\d+)?/ 
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

help_effect: _help_effect effect { ::help_effect($item{effect}) ; 1}
find_effect: _find_effect anytag(s) { 
	::find_effect(@{$item{"anytag(s)"}}); 1}
help: _help 'yml' { ::pager($::text->{commands_yml}); 1}
help: _help anytag  { ::help($item{anytag}) ; 1}
help: _help { ::pager( $::help->{screen} ); 1}
project_name: _project_name { 
	::pager( "project name: ", $::project->{name}); 1}
new_project: _new_project project_id { 
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
destroy_project_template: _destroy_project_template key(s) {
	::remove_project_template(@{$item{'key(s)'}}); 1;
}

tag: _tag tagname message(?) {   
	::git_snapshot();
	my @args = ('tag', $item{tagname});
	push @args, '-m', "@{$item{'message(?)'}}" if @{$item{'message(?)'}};
	::git(@args);
	1;
}
commit: _commit message(?) { 
	::git_snapshot(@{$item{'message(?)'}});
	1;
}
branch: _branch branchname { 
	::throw("$item{branchname}: branch does not exist.  Skipping."), return 1
		if ! ::git_branch_exists($item{branchname});
	# reload git-altered State.json file
	if(::git_checkout($item{branchname})){
		::load_project(name => $::project->{name})
	} else { } # git_checkout tells us what went wrong
	1;
}
branch: _branch { ::list_branches(); 1}

list_branches: _list_branches end { ::list_branches(); 1}

new_branch: _new_branch branchname branchfrom(?) { 
	my $name = $item{branchname};
	my $from = "@{$item{'branchfrom(?)'}}";
	::throw("$name: branch already exists. Doing nothing."), return 1
		if ::git_branch_exists($name);
	::git_create_branch($name, $from);
}
tagname: ident
branchname: ident
branchfrom: ident
message: /.+/

save_state: _save_state save_target message(?) { 
	my $name = $item{save_target};
	my $default_msg = "user save - $name";
	my $message = "@{$item{'message(?)'}}" || $default_msg;
	::pager("save target name: $name\n");
	::pager("commit message: $message\n") if $message;
	
	# save as named file
	
	if(  ! $::config->{use_git} or $name =~ /\.json$/ )
	{
	 	::pager("saving as file\n"), ::save_state( $name)
	}
	else 
	{
		# save state if necessary
		::git_snapshot();

		# tag the current commit
		my @args = ('tag', $name);
		push @args, '-m', $message if $message;
		::git(@args);
		::pager_newline(qq/tagged HEAD commit as "$name"/,
			qq/type "get $name" to return to this commit./)
	}
	1
}
save_state: _save_state { ::git_snapshot('user save'); 1}

# load project from named state file
get_state: _get_state save_target {
 	::load_project( 
 		name => $::project->{name},
 		settings => $item{save_target}
 		); 1}
# # reload project if given with no arguments
# get_state: _get_state {
#  	::load_project( name => $::project->{name},) ; 1}
getpos: _getpos {  
	::pager( ::d1( ::eval_iam q(getpos) )); 1}
setpos: _setpos timevalue {
	::set_position($item{timevalue}); 1}
forward: _forward timevalue {
	::forward( $item{timevalue} ); 1}
rewind: _rewind timevalue {
	::rewind( $item{timevalue} ); 1}
timevalue: min_sec | decimal_seconds
seconds: samples  # samples returns seconds
seconds: /\d+/
samples: /\d+sa/ {
	my ($samples) = $item[1] =~ /(\d+)/;
 	#print "found $samples samples\n";
 	$return = $samples/$::config->{sample_rate}
}
min_sec: /\d+/ ':' /\d+/ { $item[1] * 60 + $item[3] }

to_start: _to_start { ::to_start(); 1 }
to_end: _to_end { ::to_end(); 1 }
add_track: _add_track new_track_name {
	::add_track($item{new_track_name});
    1
}
arg: anytag
add_tracks: _add_tracks track_name(s) {
	map{ ::add_track($_)  } @{$item{'track_name(s)'}}; 1}
new_track_name: anytag  { #$item{anytag} 
  	my $proposed = $item{anytag};
  	::throw( qq(Track name "$proposed" needs to start with a letter)), 
  		return undef if  $proposed !~ /^[A-Za-z]/;
  	::throw( qq(Track name "$proposed" cannot contain a colon.)), 
  		return undef if  $proposed =~ /:/;
 	::throw( qq(A track named "$proposed" already exists.)), 
 		return undef if $::Track::by_name{$proposed};
 	::throw( qq(Track name "$proposed" conflicts with Ecasound command keyword.)), 
 		return undef if $::text->{iam}->{$proposed};
 
 	::throw( qq(Track name "$proposed" conflicts with user command.)), 
 		return undef if $::text->{user_command}->{$proposed};
 
  	::throw( qq(Track name "$proposed" conflicts with Nama command or shortcut.)), 
  		return undef if $::text->{commands}->{$proposed} 
				 or $::text->{command_shortcuts}->{$proposed}; 
;
$proposed
} 
			
track_name: ident
existing_track_name: track_name { 
	my $track_name = $item{track_name};
	if ($::tn{$track_name}){
		$track_name;
	}
	else {	
		::throw("$track_name: track does not exist.\n");
		undef
	}
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
	local $::quiet = 1;
	::remove_track_cmd($::this_track);
	1
}
remove_track: _remove_track existing_track_name {
		::remove_track_cmd($::tn{$item{existing_track_name}});
		1
}
remove_track: _remove_track end { 
		::remove_track_cmd($::this_track) ;
		1
}
quiet: 'quiet'
link_track: _link_track existing_project_name track_name new_track_name end
{
	::add_track_alias_project(
		$item{new_track_name},
		$item{track_name}, 
		$item{existing_project_name}
	); 
1
}
link_track: _link_track target track_name end {
	::add_track_alias($item{track_name}, $item{target}); 1
}
target: existing_track_name

existing_project_name: ident {
	$item{ident} if -d ::join_path(::project_root(),$item{ident})
}
project: ident
set_region: _set_region beginning ending { 
	::set_region( @item{ qw( beginning ending ) } );
	1;
}
set_region: _set_region beginning { ::set_region( $item{beginning}, 'END' );
	1;
}
remove_region: _remove_region { ::remove_region(); 1; }
add_region: _add_region beginning ending track_name(?) {
	my $name = $item{'track_name(?)'}->[0];
	::new_region(@item{qw(beginning ending)}, $name); 1
}

shift_track: _shift_track start_position {
	my $pos = $item{start_position};
	if ( $pos =~ /\d+\.\d+/ ){
		::pager($::this_track->name, ": Shifting start time to $pos seconds");
		$::this_track->set(playat => $pos);
		1;
	}
	# elsif ( pos =~ /^\d+$/ ) { # skip the mark index case
	elsif ( $::Mark::by_name{$pos} ){
		my $time = ::Mark::mark_time( $pos );
		::pager($::this_track->name, qq(: Shifting start time to mark "$pos", $time seconds));
		$::this_track->set(playat => $pos);
		1;
	} else { 
		::throw( "Shift value is neither decimal nor mark name. Skipping.");
	0;
	}
}

start_position:  float | samples | mark_name
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
engine_status: _engine_status { ::pager(::eval_iam q(engine-status)); 1}
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

modifiers: _modifiers { ::pager( $::this_track->modifiers); 1}
nomodifiers: _nomodifiers { $::this_track->set(modifiers => ""); 1}
show_chain_setup: _show_chain_setup { ::pager(::ChainSetup::ecasound_chain_setup); 1}
dump_io: _dump_io { ::ChainSetup::show_io(); 1}
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

show_mode: _show_mode { ::pager( ::show_status()); 1}
bus_mon: _bus_mon {
	my $bus = $::bn{$::this_bus}; 
	$bus->set(rw => 'REC');
	# set up mix track
	$::tn{$bus->send_id}->busify
		if $bus->send_type eq 'track' and $::tn{$bus->send_id};
	::pager( "Setting MON mode for $::this_bus bus.");
	1; }
bus_off: _bus_off {
	my $bus = $::bn{$::this_bus}; 
	$bus->set(rw => 'OFF');
	# turn off mix track
	if($bus->send_type eq 'track' and my $mix = $::tn{$bus->send_id})
	{ $mix->set(rw => 'OFF') }
	::pager( "Setting OFF mode for " , $::this_bus, " bus. Member tracks disabled."); 1  
}
bus_version: _bus_version dd { 
	my $n = $item{dd};
	::process_command("for $::this_bus; version $n");
}
mixdown: _mixdown { ::mixdown(); 1}
mixplay: _mixplay { ::mixplay(); 1}
mixoff:  _mixoff  { ::mixoff(); 1}
automix: _automix { ::automix(); 1 }
autofix_tracks: _autofix_tracks { ::process_command("for mon; fixdc; normalize"); 1 }
master_on: _master_on { ::master_on(); 1 }

master_off: _master_off { ::master_off(); 1 }

exit: _exit {   
	::save_state(); 
	CORE::exit;
}	
source: _source ('track'|'t') trackname { 
	$::this_track->set_source($item{trackname}, 'track'); 1
} 
trackname: existing_track_name
source: _source source_id { $::this_track->set_source($item{source_id}); 1 }
source_id: shellish
source: _source { 
	::pager_newline($::this_track->name, ": input set to ", $::this_track->input_object_text, "\n",
	"however track status is ", $::this_track->rec_status)
		if $::this_track->rec_status ne 'REC';
	1;
}
send: _send ('track'|'t') trackname { 
	$::this_track->set_send($item{trackname}, 'track'); 1
} 
send: _send send_id { $::this_track->set_send($item{send_id}); 1}
send: _send { $::this_track->set_send(); 1}
send_id: shellish
remove_send: _remove_send {
					$::this_track->set(send_type => undef);
					$::this_track->set(send_id => undef); 1
}
stereo: _stereo { 
	$::this_track->set(width => 2); 
	::pager($::this_track->name, ": setting to stereo\n");
	1;
}
mono: _mono { 
	$::this_track->set(width => 1); 
	::pager($::this_track->name, ": setting to mono\n");
	1; }

# dummy defs to avoid warnings from command.yml entries
off: 'dummy'
record: 'dummy'
mon: 'dummy'
play: 'dummy'

# some ordering fixes
command: mono
command: rw

rw_setting: 'rec'|'play'|'mon'|'off' { $return = $item[1] }
rw: rw_setting {
	$::this_track->is_system_track 
		# for system tracks, just set track 'rw' field
		? $::this_track->set(rw => uc $item{rw_setting}) 

		# that make sure bus settings are cooperative
		: ::rw_set($::Bus::by_name{$::this_bus},$::this_track,$item{rw_setting}); 
	1
}

set_version: _set_version dd { $::this_track->set_version($item{dd}); 1}

vol: _vol value { 
	$::this_track->vol or 
		::throw(( $::this_track->name . ": no volume control available")), return;
	::modify_effect(
		$::this_track->vol,
		1,
		undef,
		$item{value});
	1;
} 
vol: _vol sign(?) value { 
	$::this_track->vol or 
		::throw( $::this_track->name . ": no volume control available"), return;
	::modify_effect(
		$::this_track->vol,
		1,
		$item{'sign(?)'}->[0],
		$item{value});
	1;
} 
vol: _vol { ::pager( $::fx->{params}->{$::this_track->vol}[0]); 1}

mute: _mute { $::this_track->mute; 1}

unmute: _unmute { $::this_track->unmute; 1}


solo: _solo ident(s) {
	::solo(@{$item{'ident(s)'}}); 1
}

solo: _solo { ::solo($::this_track->name); 1}
all: _all { ::all() ; 1}
nosolo: _nosolo { ::nosolo() ; 1}

unity: _unity { ::unity($::this_track); 1}

pan: _pan panval { 
	::effect_update_copp_set( $::this_track->pan, 0, $item{panval});
	1;} 
pan: _pan sign panval {
	::modify_effect( $::this_track->pan, 1, $item{sign}, $item{panval} );
	1;} 
panval: float 
      | dd
pan: _pan { ::pager( $::fx->{params}->{$::this_track->pan}[0]); 1}
pan_right: _pan_right { ::pan_check($::this_track, 100 ); 1}
pan_left:  _pan_left  { ::pan_check($::this_track,    0 ); 1}
pan_center: _pan_center { ::pan_check($::this_track,   50 ); 1}
pan_back:  _pan_back { ::pan_back($::this_track); 1;}
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
add_mark: _add_mark ident { ::drop_mark $item{ident}; 1}
add_mark: _add_mark {  ::drop_mark(); 1}
next_mark: _next_mark { ::next_mark(); 1}
previous_mark: _previous_mark { ::previous_mark(); 1}
loop: _loop someval(s) {
	my @new_endpoints = @{ $item{"someval(s)"}}; # names or indexes of marks
	#::pager( @new_endpoints);
	$::mode->{loop_enable} = 1;
	@{$::setup->{loop_endpoints}} = (@new_endpoints, @{$::setup->{loop_endpoints}}); 
	@{$::setup->{loop_endpoints}} = @{$::setup->{loop_endpoints}}[0,1];
	1;}
noloop: _noloop { $::mode->{loop_enable} = 0; 1}
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
	::pager($::this_mark->name, ": set to ", ::d2( $newtime), "\n");
	::pager("adjusted to ",$::this_mark->time, "\n") 
		if $::this_mark->time != $newtime;
	::set_position($::this_mark->time);
	::request_setup();
	1;
	}
modify_mark: _modify_mark value {
	$::this_mark->set( time => $item{value} );
	my $newtime = $item{value};
	::pager($::this_mark->name, ": set to ", ::d2($newtime),"\n");
	::pager("adjusted to ",$::this_mark->time, "\n")
		if $::this_mark->time != $newtime;
	::set_position($::this_mark->time);
	::request_setup();
	1;
	}		
remove_effect: _remove_effect fx_alias_remove(s) {
	#print join $/, @{ $item{"fx_alias_remove(s)"} }; 
	::mute();
	map{ 
		my $id = $_;
		my ($use) = grep{ $id eq $::this_track->$_ } qw(vol pan fader);
		if($use){
			::throw("Effect $id is used as $use by track",$::this_track->name, 
			".\nSee 'remove_fader_effect to remove it'\n")
		}
		else { ::remove_effect( $_ ) }
	} grep { $_ }  map{ split ' ', $_} @{ $item{"fx_alias_remove(s)"}} ;
	# map{ print "fx_alias_remove: $_\n"; ::remove_effect( $_ )}  @{ $item{"fx_alias_remove(s)"}} ;
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

		my $pi = 	::effect_index(::fxn($parent)->type);
		my $pname = $::fx_cache->{registry}->[$pi]->{name};

		::pager("\nAdded $id ($iname) to $parent ($pname)\n\n");

	}
	1;
}
add_controller: _add_controller effect value(s?) {
	::throw("current effect is undefined, skipping\n"), return 1 if ! ::this_op();
	my $code = $item{effect};
	my $parent = ::this_op();
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

		my $pi = 	::effect_index(::fxn($parent)->type);
		my $pname = $::fx_cache->{registry}->[$pi]->{name};

		::pager("\nAdded $id ($iname) to $parent ($pname)\n\n");

	}
	1;
}
existing_effect_chain: ident { $item{ident} if ::is_effect_chain($item{ident}) }

fx_or_fxc: fx_nick | existing_effect_chain | known_effect_type

nickname_effect: _nickname_effect ident {
	my $ident = $item{ident};
	::this_op_o()->set_name($ident);
	::throw("$ident: no such nickname. Skipping."), return unless defined ::this_op_o();
	my $type = ::this_op_o()->type;
	my $fxname = ::this_op_o()->fxname;
	$::fx->{alias}->{$ident} = $type;
	::pager_newline("$ident: nickname created for $type ($fxname)");
	1
}
remove_nickname: _remove_nickname { ::this_op_o()->remove_name() }
delete_nickname_definition: _delete_nickname_definition ident {
	my $was = delete $::fx->{alias}->{$item{ident}};
	$was or ::throw("$item{ident}: no such nickname"), return 0;
	::pager_newline("$item{ident}: effect nickname deleted");
}
list_nickname_definitions: _list_nickname_definitions {
	my @lines;
	while( my($nick,$code) = each %{ $::fx->{alias} } )
	{
		#push @lines, join " ","$nick:",::fxn($code)->fxname, "($code)";
		push @lines, join " ",
			"$nick:",
			$::fx_cache->{registry}->[::effect_index($code)]->{name},
			"($code)\n";
	}
	::pager(@lines);
	1
}
known_effect_type: effect { 
	::full_effect_code($item{effect})
	#::throw(qq{$item{effect}: unknown effect. Try "find_effect keyword(s)\n}), 
}
before: fx_alias
this_track_effect_chain: ident { my $id = $::this_track->effect_chain_leading_id($item{ident}) }
add_effect: _add_effect fx_or_fxc value(s?) before(?) {
	my ($code, $effect_chain);
	my $values = $item{'value(s?)'};
	my $args = { 	track  => $::this_track, 
					values => $values };
	if( my $fxc = ::is_effect_chain($item{fx_or_fxc}) )
	{ 
		if( $fxc->ops_data and $item{'values(s?)'} and
			scalar @{$fxc->ops_data} == 1 and scalar @{$item{'values(s?)'}})
			{ $args->{type} 		= $fxc->ops_data->[0]->{type} 	}
		else{ $args->{effect_chain}	= $fxc 					}
	}
	else{ 	  $args->{type}			= $item{fx_or_fxc}				}
	# place effect before fader if there is one
	my $fader = 
			   ::fxn($::this_track->pan) && $::this_track->pan
			|| ::fxn($::this_track->vol) && $::this_track->vol;
	{ no warnings 'uninitialized';
	::logpkg('debug',$::this_track->name,": effect insert point is $fader", 
	::Dumper($args));
	}
	my $predecessor = $item{'before(?)'}->[0] || $fader;
	$args->{before} = $predecessor if $predecessor; 
 	my $id = ::add_effect($args);
	return 1 if $effect_chain;
	if ($id)
	{
		no warnings 'uninitialized';
		my $i = ::effect_index($code);
		my $iname = $::fx_cache->{registry}->[$i]->{name};

		::pager("Added $id ($iname)");
		::set_current_op($id);
	}
	else { } 
	1
}

add_effect: _add_effect ('first'  | 'f')  fx_or_fxc value(s?) {
	my $command = join " ", 
		qw(add_effect), 
		$item{fx_or_fxc},
		@{$item{'value(s?)'}},
		$::this_track->{ops}->[0];
		print "command is $command\n";
	::process_command($command)
}
add_effect: _add_effect ('last'   | 'l')  fx_or_fxc value(s?) { 
	my $command = join " ", 
		qw(add_effect),
		$item{fx_or_fxc},
		@{$item{'value(s?)'}},
		qw(ZZZ);
		print "command is $command\n";
	::process_command($command)
}
add_effect: _add_effect ('before' | 'b')  before fx_or_fxc value(s?) {
	my $command = join " ", 
		qw(add_effect),
		$item{fx_or_fxc},
		@{$item{'value(s?)'}},
		$item{before};
		print "command is $command\n";
	::process_command($command)
}

parent: op_id
modify_effect: _modify_effect fx_alias(s /,/) parameter(s /,/) value {
	::modify_multiple_effects( @item{qw(fx_alias(s) parameter(s) sign value)});
	::pager(::show_effect(@{ $item{'fx_alias(s)'} }))
}
modify_effect: _modify_effect fx_alias(s /,/) parameter(s /,/) sign value {
	::modify_multiple_effects( @item{qw(fx_alias(s) parameter(s) sign value)});
	::pager(::show_effect(@{ $item{'fx_alias(s)'} }));
}
modify_effect: _modify_effect parameter(s /,/) value {
	::throw("current effect is undefined, skipping"), return 1 if ! ::this_op();
	::modify_multiple_effects( 
		[::this_op()], 
		$item{'parameter(s)'},
		undef,
		$item{value});
	::pager( ::show_effect(::this_op(), "with track affiliation"))
}
modify_effect: _modify_effect parameter(s /,/) sign value {
	::throw("current effect is undefined, skipping"), return 1 if ! ::this_op();
	::modify_multiple_effects( [::this_op()], @item{qw(parameter(s) sign value)});
	::pager( ::show_effect(::this_op()));
}
fx_alias3: ident { 
	join " ", 
	map{ $_->id } 
	grep { $_->surname eq $item{ident} } $::this_track->fancy_ops_o;
}
fx_alias_remove: fx_alias1 | fx_alias3
fx_alias: fx_alias2 | fx_alias1
fx_nick: ident { $::fx->{alias}->{$item{ident}} }
fx_alias1: op_id
fx_alias1: fx_pos
fx_alias1: this_track_effect_chain 
fx_alias2: fx_type
#fx_pos |fx_type | this_track_effect_chain |  op_id { $item[-1] }
fx_pos: dd { $::this_track->{ops}->[$item{dd} - 1] }
fx_type: effect { 
	my $FX = $::this_track->first_effect_of_type($item{effect});
	$FX ? $FX->id : undef
}
position_effect: _position_effect op_to_move new_following_op {
	my $op = $item{op_to_move};
	my $pos = $item{new_following_op};
	::position_effect($op, $pos);
	::set_current_op($op);
	1;
}

op_to_move: op_id
new_following_op: op_id
	
show_effect: _show_effect fx_alias(s) {
	my @lines = 
		map{ ::show_effect($_, "with track affiliation") } 
		grep{ ::fxn($_) }
		@{ $item{'fx_alias(s)'}};
	::set_current_op($item{'fx_alias(s)'}->[-1]);
	::pager(@lines); 1
}
show_effect: _show_effect {
	::throw("current effect is undefined, skipping"), return 1 if ! ::this_op();
	::pager( ::show_effect(::this_op(), "with track affiliation"));
	1;
}
dump_effect: _dump_effect fx_alias { ::pager( ::json_out(::fxn($item{fx_alias})->as_hash) ); 1}
dump_effect: _dump_effect { ::pager( ::json_out(::this_op_o()->as_hash) ); 1}
list_effects: _list_effects { ::pager(::list_effects()); 1}
add_bunch: _add_bunch ident(s) { ::bunch( @{$item{'ident(s)'}}); 1}
list_bunches: _list_bunches { ::bunch(); 1}
remove_bunch: _remove_bunch ident(s) { 
 	map{ delete $::project->{bunch}->{$_} } @{$item{'ident(s)'}}; 1}
add_to_bunch: _add_to_bunch ident(s) { ::add_to_bunch( @{$item{'ident(s)'}});1 }
list_versions: _list_versions { 
	::pager( join " ", @{$::this_track->versions}); 1}
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
	::pager( grep{ ! $seen{$_} and $seen{$_}++ } @history );
}
add_user: _add_user bus_name destination {
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
	 ::pager( "The insert is ", $i->wetness, "% wet, ", (100 - $i->wetness), "% dry.");
}

remove_insert: _remove_insert prepost(?) { 

	# use prepost spec if provided
	# remove lone insert without prepost spec
	
	my $prepost = $item{'prepost(?)'}->[0];
	my $id = ::Insert::get_id($::this_track,$prepost);
	$id or ::throw($::this_track->name.  ": Missing or ambiguous insert. Skipping"), return 1 ;
	::pager( $::this_track->name.": removing ". $prepost ?  "$prepost fader insert" : "insert");
	$::Insert::by_index{$id}->remove;
	1;
}

cache_track: _cache_track additional_time(?) {
	my $time = $item{'additional_time(?)'}->[0];
	::cache_track($::this_track, $time); 1 
}
additional_time: float | dd
uncache_track: _uncache_track { ::uncache_track($::this_track); 1 }
overwrite_effect_chain: 'dummy' # avoid warnings
new_effect_chain: (_new_effect_chain | _overwrite_effect_chain ) ident op_id(s?) end {
 	my $name = $item{ident};
	my @existing = ::EffectChain::find(user => 1, name => $name);
	if ( scalar @existing ){
		$item[1] eq 'overwrite_effect_chain'
 			? ::process_command("delete_effect_chain $name")
 			: ::throw(qq/$name: effect chain with this name is already defined. 
Use a different name, or use "overwrite_effect_chain"/) && return;
	}

	my $ops = scalar @{$item{'op_id(s?)'}}
				?  $item{'op_id(s?)'} 
				: [ $::this_track->fancy_ops ];
	my @options;
	::EffectChain->new(
		user   => 1,
		global => 1,
		name   => $item{ident},
		ops_list => $ops,
		inserts_data => $::this_track->inserts,
		@options,
	);
	1;
}
delete_effect_chain: _delete_effect_chain ident(s) {
	map { 
		map{$_->destroy()} ::EffectChain::find( user => 1, name => $_);
	} @{ $item{'ident(s)'} };
	1;
}
find_effect_chains: _find_effect_chains ident(s?) 
{
	my @args;
	push @args, @{ $item{'ident(s?)'} } if $item{'ident(s?)'};
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
	my @illegal = grep { ! ::fxn($_) } @$arr_ref;
	::throw("@illegal: non-existing effect(s), skipping."), return 0 if @illegal;
 	::pager( "track ",$::this_track->name,", bypassing effects:");
	::pager( ::named_effects_list(@$arr_ref));
	::bypass_effects($::this_track,@$arr_ref);
	# set current effect in special case of one op only
	::set_current_op($arr_ref->[0]) if scalar @$arr_ref == 1;
}
#
#  all effects on current track
#
bypass_effects: _bypass_effects 'all' { 
	::pager( "track ",$::this_track->name,", bypassing all effects (except vol/pan)");
	::bypass_effects($::this_track, $::this_track->fancy_ops)
		if $::this_track->fancy_ops;
	1; 
}
#
#  current effect 
#
bypass_effects: _bypass_effects { 
	::throw("current effect is undefined, skipping"), return 1 if ! ::this_op();
 	::pager( "track ",$::this_track->name,", bypassing effects:"); 
	::pager( ::named_effects_list(::this_op()));
 	::bypass_effects($::this_track, ::this_op());  
 	1; 
}
bring_back_effects:   _bring_back_effects end { 
	::pager("current effect is undefined, skipping"), return 1 if ! ::this_op();
	::pager( "restoring effects:");
	::pager( ::named_effects_list(::this_op()));
	::restore_effects( $::this_track, ::this_op());
}
bring_back_effects:   _bring_back_effects op_id(s) { 
	my $arr_ref = $item{'op_id(s)'};
	return unless (ref $arr_ref) =~ /ARRAY/  and scalar @{$arr_ref};
	my @illegal = grep { ! ::fxn($_) } @$arr_ref;
	::throw("@illegal: non-existing effect(s), aborting."), return 0 if @illegal;
	::pager( "restoring effects:");
	::pager( ::named_effects_list(@$arr_ref));
	::restore_effects($::this_track,@$arr_ref);
	# set current effect in special case of one op only
	::set_current_op($arr_ref->[0]) if scalar @$arr_ref == 1;
}
bring_back_effects:   _bring_back_effects 'all' { 
	::pager( "restoring all effects");
	::restore_effects( $::this_track, $::this_track->fancy_ops);
}
# effect_on_current_track: op_id { 
# 	my $id = $item{op_id};
# 	my $found = 
# 	$::fxn($id) or ::pager("$id: effect does not exist."), return 0;
# 	grep{$id eq $_  } @{$::this_track->ops} 
# 			   or ::pager("$id: effect does not belong to track",
# 						$::this_track->name), return 0;			  
# 	$id;
# }

fxc_val: shellish

this_track_op_id: op_id(s) { 
	my %ops = map{ $_ => 1 } @{$::this_track->ops};
	my @ids = @{$item{'op_id(s)'}};
	my @belonging 	= grep {   $ops{$_} } @ids;
	my @alien 		= grep { ! $ops{$_} } @ids;
	@alien and ::pager("@alien: don't belong to track ",$::this_track->name, "skipping."); 
	@belonging	
}

bunch_name: ident { 
	::is_bunch($item{ident}) or ::bunch_tracks($item{ident})
		or ::throw("$item{ident}: no such bunch name."), return; 
	$item{ident};
}

effect_profile_name: ident
existing_effect_profile_name: ident {
	::pager("$item{ident}: no such effect profile"), return
		unless ::EffectChain::find(profile => $item{ident});
	$item{ident}
}
new_effect_profile: _new_effect_profile bunch_name effect_profile_name {
	::new_effect_profile($item{bunch_name}, $item{effect_profile_name}); 1 }
destroy_effect_profile: _destroy_effect_profile existing_effect_profile_name {
	::delete_effect_profile($item{existing_effect_profile_name}); 1 }
apply_effect_profile: _apply_effect_profile existing_effect_profile_name {
	::apply_effect_profile($item{effect_profile_name}); 1 }
list_effect_profiles: _list_effect_profiles {
	my %profiles;
	map{ $profiles{$_->profile}++ } ::EffectChain::find(profile => 1);
	my @output = keys %profiles;
	if( @output )
	{ ::pager( join " ","Effect Profiles available:", @output) }
	else { ::throw("no match") }
	1;
}
show_effect_profiles: _show_effect_profiles ident(?) {
	my $name;
	$name = $item{'ident(?)'}->[-1] if $item{'ident(?)'};
	$name ||= 1;
	my %profiles;
	map{ $profiles{$_->profile}++ } ::EffectChain::find(profile => $name);
	my @names = keys %profiles;
	my @output;
	for $name (@names) {
		push @output, "\nprofile name: $name\n";
		map { push @output, $_->summary } ::EffectChain::find(profile => $name)
	}
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
scan: _scan { ::pager( "scanning ", ::this_wav_dir()); ::restart_wav_memoize() }
add_fade: _add_fade in_or_out mark1 duration(?)
{ 	::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $::config->{engine_fade_default_length}, 
					relation => 'fade_from_mark',
					track => $::this_track->name,
	); 
	::request_setup();
}
add_fade: _add_fade in_or_out duration(?) mark1 
{ 	::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					duration => $item{'duration(?)'}->[0] 
								|| $::config->{engine_fade_default_length}, 
					track => $::this_track->name,
					relation => 'fade_to_mark',
	);
	::request_setup();
}
add_fade: _add_fade in_or_out mark1 mark2
{ 	::Fade->new(  type => $item{in_or_out},
					mark1 => $item{mark1},
					mark2 => $item{mark2},
					track => $::this_track->name,
	);
	::request_setup();
}
add_fade: _add_fade in_or_out time1 time2 
{ 	
	my $mark1 = ::Mark->new( 
		name => join('_',$::this_track->name, 'fade', ::Mark::next_id()),
		time => $item{time1}
	);
	my $mark2 = ::Mark->new( 
		name => join('_',$::this_track->name, 'fade', ::Mark::next_id()),
		time => $item{time2}
	);
	::Fade->new(  type => $item{in_or_out},
					mark1 => $mark1->name,
					mark2 => $mark2->name,
					track => $::this_track->name,
	);
	::request_setup();
}
time1: value
time2: value
in_or_out: 'in' | 'out'
duration: value
mark1: markname
mark2: markname
remove_fade: _remove_fade fade_index(s) { 
	my @i = @{ $item{'fade_index(s)'} };
	::remove_fade($_) for (@i);
	::request_setup();
	1
}
fade_index: dd 

list_fade: _list_fade {  ::pager(join "\n",
		map{ s/^---//; s/...\s$//; $_} map{$_->dump}
		sort{$a->n <=> $b->n} values %::Fade::by_index) }
add_comment: _add_comment text { 
 	::pager( $::this_track->name, ": comment: $item{text}"); 
 	$::project->{track_comments}->{$::this_track->name} = $item{text};
 	1;
}
remove_comment: _remove_comment {
 	::pager( $::this_track->name, ": comment removed");
 	delete $::project->{track_comments}->{$::this_track->name};
 	1;
}
show_comment: _show_comment {
	map{ ::pager( "(",$_->group,") ", $_->name, ": ", $_->comment) } $::this_track;
	1;
}
show_comments: _show_comments {
	map{ ::pager( "(",$_->group,") ", $_->name, ": ", $_->comment) } ::Track::all();
	1;
}
add_version_comment: _add_version_comment dd(?) text {
	my $t = $::this_track;
	my $v = $item{'dd(?)'}->[0] // $t->monitor_version // return 1;
	::pager( $t->add_version_comment($v,$item{text})); 
}	
remove_version_comment: _remove_version_comment dd {
	my $t = $::this_track;
	::pager( $t->remove_version_comment($item{dd})); 1
}
show_version_comment: _show_version_comment dd(s?) {
	my $t = $::this_track;
	my @v = @{$item{'dd(s?)'}};
	if(!@v){ @v = $t->monitor_version}
	@v or return 1;
	$t->show_version_comments(@v);
	 1;
}
show_version_comments_all: _show_version_comments_all {
	my $t = $::this_track;
	my @v = @{$t->versions};
	$t->show_version_comments(@v); 1;
}
set_system_version_comment: _set_system_version_comment dd text {
	::pager( ::set_system_version_comment($::this_track,@item{qw(dd text)}));1;
}
midish_command: _midish_command text {
	::midish_command( $item{text} ); 1
}
midish_mode_on: _midish_mode_on { 
	::pager("Setting midish terminal mode!! Return with 'midish_mode_off'.");
	$::mode->{midish_terminal}++;
}
 
midish_mode_off: _midish_mode_off { 
	::pager("Releasing midish terminal mode. Sync is not enabled.");
	undef $::mode->{midish_terminal};
	undef $::mode->{midish_transport_sync};
	1;
}
midish_mode_off_ready_to_play: _midish_mode_off_ready_to_play { 
	::pager("Releasing midish terminal mode.
Will sync playback with Ecasound."); 
	undef $::mode->{midish_terminal} ;
	$::mode->{midish_transport_sync} = 'play';
	1;
}
midish_mode_off_ready_to_record: _midish_mode_off_ready_to_record { 
	::pager("Releasing midish terminal mode. 
Will sync record with Ecasound.");
	undef $::mode->{midish_terminal} ;
	$::mode->{midish_transport_sync} = 'record';
	1;
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
	$t->versions->[$v] or ::pager($t->name,": version $v does not exist."),
		return;
	::VersionTrack->new(
		name 	=> $t->name.":$v",
		version => $v, # fixed
		target  => $t->name,
		rw		=> 'PLAY',
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
	::pager( "Run time limit: ", ::heuristic_time($::setup->{runtime_limit})); 1;
}
limit_run_time_off: _limit_run_time_off { 
	::pager( "Run timer disabled");
	::disable_length_timer();
	1;
}
offset_run: _offset_run markname {
	::set_offset_run_mark( $item{markname} ); 1
}
offset_run_off: _offset_run_off {
	::pager( "no run offset.");
	::disable_offset_run_mode(); 
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
		::pager(
			scalar @{$::setup->{_last_rec_tracks}} 
				?  "Toggling previous recording tracks to REC"
				:  "No tracks in REC list. Skipping."
		);
		
		map{ $_->set(rw => 'REC') } @{$::setup->{_last_rec_tracks}}; 
		::restore_preview_mode();
		1;
}

show_track_latency: _show_track_latency {
	my $node = $::setup->{latency}->{track}->{$::this_track->name};
	::pager( ::json_out($node)) if $node;
	1;
}
show_latency_all: _show_latency_all { 
	::pager( ::json_out($::setup->{latency})) if $::setup->{latency};
	1;
}
analyze_level: _analyze_level { ::check_level($::this_track);1 }
git: _git shellcode stopper { 
#print ::json_out(\%item);
::pager(map {$_.="\n"} $::project->{repo}->run( split " ", $item{shellcode})) 
}
edit_rec_setup_hook: _edit_rec_setup_hook { 
	system("$ENV{EDITOR} ".$::this_track->rec_setup_script() );
	chmod 0755, $::this_track->rec_setup_script();
	1
}
edit_rec_cleanup_hook: _edit_rec_cleanup_hook { 
	system("$ENV{EDITOR} ".$::this_track->rec_cleanup_script() );
	chmod 0755, $::this_track->rec_cleanup_script();
	1
}
remove_fader_effect: _remove_fader_effect fader_role {
	::remove_fader_effect($::this_track, $item{fader_role});
	1
}
fader_role: 'vol'|'pan'|'fader'
hotkeys: _hotkeys { ::setup_hotkeys()}
hotkeys_always: _hotkeys_always { $::config->{hotkeys_always}++; ::setup_hotkeys(); }
hotkeys_off: _hotkeys_off { undef $::config->{hotkeys_always}; 1 }

select_sequence: _select_sequence existing_sequence_name { 
	$::this_sequence = $::bn{$item{existing_sequence_name}}
} 
existing_sequence_name: ident { 
		my $buslike = $::bn{$item{ident}};
		$return = $item{ident} if (ref $buslike) =~ /Sequence/
}
convert_to_sequence: _convert_to_sequence {
	my $sequence_name = $::this_track->name;
	::process_command("nsq $sequence_name");
	$::this_sequence->new_clip($::this_track);
	1
}
merge_sequence: _merge_sequence { cache_track($::tn{$::this_sequence->name}); 1 }
	
new_sequence: _new_sequence new_sequence_name track_identifier(s?) {

	# as with sub-buses, use the same name for
	# the bus and the bus mix track
	::new_sequence( name   => $item{new_sequence_name},
					tracks => $item{'track_identifier(s?)'} || []
	);
	1
}
new_sequence_name: ident { $return = 
	$::bn{$item{ident}}
		? do { ::pager("$item{ident}: name already in use\n"), undef}
		: $item{ident} 
}
track_identifier: tid {  # allow either index or name
	my $tid = $::tn{$item{tid}} || $::ti{$item{tid}} ;
	if ($tid) { $tid }
	else 
	{ 	::throw("$item{tid}: track name or index not found.\n"); 
		undef
	}
}
tid: ident
list_sequences: _list_sequences { 
	::pager( map {::json_out($_->as_hash)} 
			grep {$_->{class} =~ /Sequence/} ::Bus::all() );
}
show_sequence: _show_sequence { ::pager($::this_sequence->list_output) }
append_to_sequence: _append_to_sequence track_identifier(s?) { 
	my $seq = $::this_sequence;
	my $items = $item{'track_identifier(s?)'} || [$::this_track];
	map { my $clip = $seq->new_clip($_); $seq->append_item($clip) } @$items; 
	1;
}
insert_in_sequence: _insert_in_sequence position track_identifier(s) {
	my $seq = $::this_sequence;
	my $items = $item{'track_identifier(s)'};
	my $position = $item{position};
	for ( reverse map{ $seq->new_clip($_) } @$items ){ $seq->insert_item($_,$position) }
}
remove_from_sequence: _remove_from_sequence position(s) {
	my $seq = $::this_sequence;
	my @positions = sort { $a <=> $b } @{ $item{'position(s)'}};
	$seq->verify_item($_) 
		?  $seq->delete_item($_) 
		: ::throw("skipping index $_: out of bounds")
	for reverse @positions
}
delete_sequence: _delete_sequence existing_sequence_name {
	$::bn{$item{existing_sequence_name}}->remove
}
position: dd { $::this_sequence->verify_item($item{dd}) and $item{dd} }
add_spacer: _add_spacer value position {
	$::this_sequence->new_spacer(
		duration => $item{value},
		position => $item{position},
		hidden   => 1,
	);
	::request_setup();
	1
}
add_spacer: _add_spacer value { 
	$::this_sequence->new_spacer(
		duration => $item{value},
        hidden   => 1,
	);
	::request_setup();
	1
}
snip: _snip track_identifier mark_pair(s) { 
	# convert this track to sequence, removing regions
	my $track = $item{track_identifier};
	my @pairs = $item{'mark_pair(s)'};
	my @list = map{ @$_ } @pairs;	
	@list = (0, @list, $track->length);
	@pairs = ();
	while ( scalar @list ){ push @pairs, [splice( @list, 0, 2)] }
	::compose_sequence($track->name, $track, \@pairs);
}
compose: _compose ident track_identifier mark_pair(s) {
	::compose_sequence(@item{qw/ident track_identifier mark_pair(s)/});
}
mark_pair: mark1 mark2 { 
	my @marks = map{ $::mn{$_}} @item{qw(mark1 mark2)};
 	::throw(join" ",(map{$_->name} @marks), 
		": pair must be ascending in time"), return undef
 	 	if not( $marks[0]->time < $marks[1]->time );
 	\@marks
}
mark1: ident { $::mn{$item{ident}} }
mark2: mark1

snip: _snip new_sequence_name mark_pair(s) {}

rename_track: _rename_track existing_track_name new_track_name { 
	::rename_track(
		@item{qw(existing_track_name new_track_name)}, 
		$::file->git_state_store, 
		::this_wav_dir()
	);
}
undo: _undo { ::undo() }

redo: _redo { ::redo() }

show_head_commit: _show_head_commit { ::show_head_commit() }

eager: _eager on_or_off { $::mode->{eager} = $item{on_or_off} =~ /[1n]/ ? 1 : 0 }
on_or_off: 'on' | '1' | 'off' | '0'

new_engine: _new_engine ident port { ::Engine->new(name => $item{ident}, port => $item{port}) }

port: dd

select_engine: _select_engine ident {
	my $new_choice = $::Engine::by_name{$item{ident}};
	$::this_engine = $new_choice if defined $new_choice;
	::pager("Current engine is ".$::this_engine->name)
}
set_track_engine_group: _set_track_engine_group ident {
	$::this_track->set(engine_group => $item{ident});
	::pager($::this_track->name. ": engine group set to $item{ident}");
}
set_bus_engine_group: _set_bus_engine_group ident {
	$::bn{$::this_bus}->set(engine_group => $item{ident});
 	::pager("$::this_bus: bus engine group set to $item{ident}");
}
select_user: _select_user existing_bus_name { 
	$::this_user = $::bn{$item{existing_bus_name}}
}
trim_user: _trim_user effect parameter sign(?) value { 
	#my($nick, $real) = @{$item{fx_alias}};
	my $real_track = join '_', $::this_user->name, $::this_track->name;
	::pager("real track: $real_track\n");
	my $FX = $::tn{$real_track}->first_effect_of_type(::full_effect_code($item{effect}));
 	::modify_effect($FX->id, $item{parameter}, @{$item{'sign(?)'}}, $item{value});
}
set_effect_name: _set_effect_name ident { ::this_op_o->set_name($item{ident}); 1}
remove_effect_name: _remove_effect_name { ::this_op_o->set_name(); 1 			  }
set_effect_surname: _set_effect_surname ident { ::this_op_o->set_surname($item{ident}); 1}
remove_effect_surname: _remove_effect_surname { ::this_op_o()->set_surname(); 1} 
