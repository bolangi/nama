package Audio::Ecasound::Flow;

### COMMAND LINE PARSER 

print "Reading grammar\n";
$Audio::Ecasound::Flow::RD_AUTOSTUB = 1;
$Audio::Ecasound::Flow::RD_HINT = 1;

# rec command changes active take

$grammar = q(

command: loop 
command: keep  | set
command: mon   | rec | mute | r | m
command: vol   | pan 
command: version 

command: new_session
command: load_session
command: add_track
command: generate_setup
command: list_marks
command: show_setup
command: show_effects
command: add_effect
command: remove_effect
command: renew_engine
command: mark
command: start
command: stop
command: ecasound_start
command: ecasound_stop
command: show_marks
command: rename_mark

_new_session: 'new' | 'new_session'
new_session: _new_session name {
	$Audio::Ecasound::Flow::session = $item{name};
	&Audio::Ecasound::Flow::new_session;
	1;
}

_load_session: 'load' | 'load_session'
load_session: _load_session name {
	$Audio::Ecasound::Flow::session = $item{name};
	&Audio::Ecasound::Flow::load_session unless $Audio::Ecasound::Flow::session_name eq $item{name};
	1;
}

_add_track: 'add' | 'add_track'
add_track: _add_track wav channel(s?) { 
	if ($Audio::Ecasound::Flow::track_names{$item{wav}} ){
		print "Track name already in use.\n";
	} else {
		&Audio::Ecasound::Flow::add_track($item{wav}) ;
		my %ch = ( @{$item{channel}} );	
		$ch{r} and $Audio::Ecasound::Flow::state_c{$Audio::Ecasound::Flow::i}->{ch_r} = $Audio::Ecasound::Flow::ch{r};
		$ch{m} and $Audio::Ecasound::Flow::state_c{$Audio::Ecasound::Flow::i}->{ch_m} = $Audio::Ecasound::Flow::ch{m};
		
	}
	1;
}

_generate_setup: 'setup' | 'generate_setup'
generate_setup: _generate_setup {}
setup: 'setup'{ &Audio::Ecasound::Flow::setup_transport and &Audio::Ecasound::Flow::connect_transport; 1}

_list_marks: 'l' | 'list_marks'
list_marks: _list_marks {}

_show_setup: 'show' | 'show_setup'
show_setup: _show_setup { 	map { push @Audio::Ecasound::Flow::format_fields,  
							$_,
							$Audio::Ecasound::Flow::state_c{$_}->{active},
							$Audio::Ecasound::Flow::state_c{$_}->{file},
							$Audio::Ecasound::Flow::state_c{$_}->{rw},
							&Audio::Ecasound::Flow::rec_status($_),
							$Audio::Ecasound::Flow::state_c{$_}->{ch_r},
							$Audio::Ecasound::Flow::state_c{$_}->{ch_m},
					} sort keys %Audio::Ecasound::Flow::state_c;
				write; # using format at end of file
				1;
}

_show_effects: 'sfx' | 'show_effects'
show_effects: _show_effects {}

_ecasound_start: 'T' | 'ecasound_start'
ecasound_start: _ecasound_start {}

_ecasound_stop: 'S' | 'ecasound_stop'
ecasound_stop: _ecasound_stop {}

_add_effect: 'fx' | 'add_effect'
add_effect: _add_effect {}

_remove_effect: 'rfx' | 'remove_effect'
remove_effect: _remove_effect {}

_renew_engine: 'renew' | 'renew_engine'
renew_engine: _renew_engine {&Audio::Ecasound::Flow::new_engine; 1}

_mark: 'k' | 'mark'
mark: _mark {}

_start: 't' | 'start'
start: _start {}

_stop: 's' | 'stop'
stop: _stop {}

_show_marks: 'sm' | 'show_marks'
show_marks: _show_marks {}

_rename_mark: 'rn' | 'rename_mark'
rename_mark: _rename_mark {}

loop: {}

name: /\w+/

wav: name


mix: 'mix' {1}

norm: 'norm' {1}

exit: 'exit' { &Audio::Ecasound::Flow::save_state($Audio::Ecasound::Flow::statestore); exit; }


channel: r | m

r: 'r' dd  { $Audio::Ecasound::Flow::state_c{$Audio::Ecasound::Flow::chain{$Audio::Ecasound::Flow::select_track}}->{ch_r} = $item{dd} }
m: 'm' dd  { $Audio::Ecasound::Flow::state_c{$Audio::Ecasound::Flow::chain{$Audio::Ecasound::Flow::select_track}}->{ch_m} = $item{dd} }


rec: 'rec' wav(s?) { 
	map{$Audio::Ecasound::Flow::state_c{$Audio::Ecasound::Flow::chain{$_}}->{rw} = q(rec)} @{$item{wav}} 
}
mon: 'mon' wav(s?) { 
	map{$Audio::Ecasound::Flow::state_c{$Audio::Ecasound::Flow::chain{$_}}->{rw} = q(mon)} @{$item{wav}} 
}
mute: 'mute' wav(s?) { 
	map{$Audio::Ecasound::Flow::state_c{$Audio::Ecasound::Flow::chain{$_}}->{rw} = q(mute)} @{$item{wav}}  
}

mon: 'mon' {$Audio::Ecasound::Flow::state_c{$Audio::Ecasound::Flow::chain{$Audio::Ecasound::Flow::select_track}} = q(mon); }

mute: 'mute' {$Audio::Ecasound::Flow::state_c{$Audio::Ecasound::Flow::chain{$Audio::Ecasound::Flow::select_track}} = q(mute); }

rec: 'rec' {$Audio::Ecasound::Flow::state_c{$Audio::Ecasound::Flow::chain{$Audio::Ecasound::Flow::select_track}} = q(rec); }

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

