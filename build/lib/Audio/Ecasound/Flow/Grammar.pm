# Grammar.p, source for Grammar.pm

package Audio::Ecasound::Flow;

### COMMAND LINE PARSER 

$debug2 and print "Reading grammar\n";

$AUTOSTUB = 1;
$RD_HINT = 1;

# rec command changes active take

$grammar = q(

command: mon
command: m
command: r
command: rec
command: off
command: vol
command: pan
command: version
command: loop
command: save_session
command: new_session
command: load_session
command: add_track
command: generate_setup
command: list_marks
command: show_setup
command: show_effects
command: ecasound_start
command: ecasound_stop
command: add_effect
command: remove_effect
command: renew_engine
command: mark
command: start
command: stop
command: show_marks
command: rename_mark
_mon: mon
_m: m
_r: r
_rec: rec
_off: off | z
_vol: vol | v
_pan: pan | p
_version: version | n
_loop: loop
_save_session: save_session | keep | k
_new_session: new_session | new
_load_session: load_session | load
_add_track: add_track | add
_generate_setup: generate_setup | setup
_list_marks: list_marks | l
_show_setup: show_setup | show
_show_effects: show_effects | sfx
_ecasound_start: ecasound_start | T
_ecasound_stop: ecasound_stop | S
_add_effect: add_effect | fx
_remove_effect: remove_effect | rfx
_renew_engine: renew_engine | renew
_mark: mark | k
_start: start | t
_stop: stop | st
_show_marks: show_marks | sm
_rename_mark: rename_mark | rn
mon: _mon {}
m: _m {}
r: _r {}
rec: _rec {}
off: _off {}
vol: _vol {}
pan: _pan {}
version: _version {}
loop: _loop {}
save_session: _save_session {}
new_session: _new_session {}
load_session: _load_session {}
add_track: _add_track {}
generate_setup: _generate_setup {}
list_marks: _list_marks {}
show_setup: _show_setup {}
show_effects: _show_effects {}
ecasound_start: _ecasound_start {}
ecasound_stop: _ecasound_stop {}
add_effect: _add_effect {}
remove_effect: _remove_effect {}
renew_engine: _renew_engine {}
mark: _mark {}
start: _start {}
stop: _stop {}
show_marks: _show_marks {}
rename_mark: _rename_mark {}
new_session: _new_session name {
	$::session = $item{name};
	&::new_session;
	1;
}

load_session: _load_session name {
	$::session = $item{name};
	&::load_session unless $::session_name eq $item{name};
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



);

# extract top-level commands from grammar

@ecmd_commands = 
	grep{$_} map{&remove_spaces($_)}        # remove null items
	map{split /\s*\|\s*|command:\s*/, $_}  # split apart commands
	grep {/command:/} split "\n", $grammar; # only commands

@ecmd_commands{@ecmd_commands} = 1..@ecmd_commands;
#print join $/, keys %ecmd_commands; 
#

sub remove_spaces {
	my $entry = shift;
	# remove leading and trailing spaces
	
	$entry =~ s/^\s*//;
	$entry =~ s/\s*$//;

	# convert other spaces to underscores
	
	$entry =~ s/\s+/_/g;
	$entry;
}
1;

